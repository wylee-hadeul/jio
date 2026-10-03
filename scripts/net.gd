extends Node
## 같이 하기 네트워크. 웹에서만 동작한다.
## PeerJS 공개 중계 서버로 서로를 찾고, 브라우저끼리 WebRTC 데이터 채널로 직접 주고받는다.
## 방장(host)이 중심: 참가자(client)는 방장에게만 보내고, 방장이 모두에게 다시 뿌린다.

signal message(msg: Dictionary)

const PEER_PREFIX := "jio-backrooms-"
const MAX_PLAYERS := 4

const GLUE := """
(function(){
if (window.__net) return;
var ICE = {config: {iceServers: [
	{urls: 'stun:stun.l.google.com:19302'},
	{urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject'},
	{urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject'},
	{urls: 'turn:openrelay.metered.ca:443?transport=tcp', username: 'openrelayproject', credential: 'openrelayproject'}
]}};
var net = window.__net = {inbox: [], conns: {}, peer: null, id: '', status: 'idle'};
function push(m) { net.inbox.push(m); }
function load(cb) {
	if (window.Peer) return cb();
	var s = document.createElement('script');
	s.src = 'https://unpkg.com/peerjs@1.5.4/dist/peerjs.min.js';
	s.onload = cb;
	s.onerror = function(){ net.status = 'error'; push({t: '_error', e: 'load'}); };
	document.head.appendChild(s);
}
function wire(c) {
	c.on('open', function(){ net.conns[c.peer] = c; push({t: '_join', id: c.peer}); });
	c.on('data', function(d){
		try { var m = typeof d === 'string' ? JSON.parse(d) : d; m._from = c.peer; push(m); } catch (e) {}
	});
	var gone = function(){ if (net.conns[c.peer]) { delete net.conns[c.peer]; push({t: '_leave', id: c.peer}); } };
	c.on('close', gone);
	c.on('error', gone);
}
function onError(e){ net.status = 'error'; push({t: '_error', e: e.type || String(e)}); }
net.host = function(code) {
	load(function(){
		var p = net.peer = new Peer(%s + code, ICE);
		net.status = 'connecting';
		p.on('open', function(id){ net.id = id; net.status = 'hosting'; push({t: '_open', id: id}); });
		p.on('connection', function(c){
			if (Object.keys(net.conns).length >= %d - 1) { c.on('open', function(){ c.send(JSON.stringify({t: 'full'})); setTimeout(function(){ c.close(); }, 500); }); return; }
			wire(c);
		});
		p.on('error', onError);
	});
};
net.join = function(code) {
	load(function(){
		var p = net.peer = new Peer(undefined, ICE);
		net.status = 'connecting';
		p.on('open', function(id){
			net.id = id;
			var c = p.connect(%s + code, {reliable: true});
			wire(c);
			c.on('open', function(){ net.status = 'joined'; push({t: '_connected', id: id}); });
		});
		p.on('error', onError);
	});
};
net.send = function(json, to) {
	for (var k in net.conns) {
		if (!to || k === to) { try { net.conns[k].send(json); } catch (e) {} }
	}
};
net.leave = function() {
	try { if (net.peer) net.peer.destroy(); } catch (e) {}
	net.peer = null; net.conns = {}; net.status = 'idle'; net.inbox = [];
};
net.poll = function() { var a = net.inbox; net.inbox = []; return JSON.stringify(a); };
net.share = function(url, text) {
	if (navigator.share) { navigator.share({title: '백룸 - 같이 하기', text: text, url: url}).catch(function(){}); return 'share'; }
	try { navigator.clipboard.writeText(url); return 'copied'; } catch (e) { return 'fail'; }
};
})();
"""

var enabled := OS.has_feature("web")
## "", "host", "client"
var role := ""
var room := ""
var my_id := ""
var _glued := false


func _glue() -> void:
	if _glued:
		return
	JavaScriptBridge.eval(GLUE % [JSON.stringify(PEER_PREFIX), MAX_PLAYERS, JSON.stringify(PEER_PREFIX)])
	_glued = true


func host(code: String) -> void:
	_glue()
	role = "host"
	room = code
	JavaScriptBridge.eval("window.__net.host(%s)" % JSON.stringify(code))


func join(code: String) -> void:
	_glue()
	role = "client"
	room = code
	JavaScriptBridge.eval("window.__net.join(%s)" % JSON.stringify(code))


func leave() -> void:
	if enabled and _glued:
		JavaScriptBridge.eval("window.__net.leave()")
	role = ""
	room = ""
	my_id = ""


func send(msg: Dictionary, to := "") -> void:
	if role == "":
		return
	JavaScriptBridge.eval("window.__net.send(%s, %s)" % [JSON.stringify(JSON.stringify(msg)), JSON.stringify(to)])


func peer_count() -> int:
	if role == "" or not _glued:
		return 0
	return int(JavaScriptBridge.eval("Object.keys(window.__net.conns).length"))


func _process(_delta: float) -> void:
	if role == "" or not _glued:
		return
	var raw = JavaScriptBridge.eval("window.__net.poll()")
	if typeof(raw) != TYPE_STRING or raw == "[]":
		return
	var arr = JSON.parse_string(raw)
	if typeof(arr) != TYPE_ARRAY:
		return
	for m in arr:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if m.get("t") in ["_open", "_connected"]:
			my_id = str(m.get("id", ""))
		message.emit(m)


## 주소창의 ?room=1234 를 읽는다.
func url_room() -> String:
	if not enabled:
		return ""
	var q := str(JavaScriptBridge.eval("location.search"))
	var re := RegEx.create_from_string("room=(\\d{4})")
	var m := re.search(q)
	return m.get_string(1) if m else ""


func invite_url() -> String:
	var base := str(JavaScriptBridge.eval("location.origin + location.pathname"))
	return "%s?room=%s" % [base, room]


func share_invite() -> String:
	_glue()
	return str(JavaScriptBridge.eval("window.__net.share(%s, %s)" % [
		JSON.stringify(invite_url()), JSON.stringify("백룸에 같이 들어가자. 방 번호 " + room)]))


static func random_code() -> String:
	return "%04d" % (randi() % 9000 + 1000)
