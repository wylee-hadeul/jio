extends Node3D
## 같이 하기: 동료 아바타, 상태 주고받기, 진행 공유, 부르기, 방장의 '그것' 제어.
## 방장이 '그것'을 움직이고, 누구 하나라도 보고 있으면 멈춘다.

signal net_event(t: String, data: Dictionary)

const SEND_HZ := 15.0
const COLORS := [Color("3b6ea5"), Color("a5493b"), Color("4c8f4a"), Color("8a5aa8")]
const NOT_SHARED := ["escaped"]

var main: Node3D
var active := false
## id -> {node, pos, yaw, pitch, fl, eyes, sees, ping}
var remotes := {}
var _send_t := 0.0
var _entity_targets: Array = []


func setup(m: Node3D) -> void:
	main = m
	Net.message.connect(_on_message)
	G.flag_set.connect(_on_local_flag)


func is_host() -> bool:
	return active and Net.role == "host"


func is_client() -> bool:
	return active and Net.role == "client"


func player_count() -> int:
	return remotes.size() + 1


func begin() -> void:
	active = true
	_send_t = 0.0


func end() -> void:
	for id in remotes.keys():
		_remove(id)
	active = false
	Net.leave()


# --- 매 프레임 ---

func tick(delta: float) -> void:
	if not active:
		return
	for id in remotes:
		var r: Dictionary = remotes[id]
		var n: Node3D = r.node
		n.global_position = n.global_position.lerp(r.pos, clampf(delta * 10.0, 0.0, 1.0))
		n.rotation.y = lerp_angle(n.rotation.y, r.yaw, clampf(delta * 10.0, 0.0, 1.0))
		r.ping = maxf(r.ping - delta, 0.0)
		n.get_node("Ping").visible = r.ping > 0.0
	if is_client():
		for i in mini(main.entities.size(), _entity_targets.size()):
			var e = main.entities[i]
			if e.active:
				e.global_position = e.global_position.lerp(_entity_targets[i], clampf(delta * 12.0, 0.0, 1.0))
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_HZ
		_send_state()


func _my_state() -> Dictionary:
	var p: Vector3 = main.player.global_position
	var sees: Array = []
	for e in main.entities:
		sees.append(e.active and main.playing and e._visible_from(main.player.camera, main.player.eyes_closed))
	return {"p": [p.x, p.y, p.z], "y": main.player.yaw, "pi": main.player.pitch,
		"f": main.player.flashlight_on, "e": main.player.eyes_closed, "s": sees, "on": main.playing, "lv": G.level}


func _send_state() -> void:
	if is_client():
		var st := _my_state()
		st.t = "st"
		Net.send(st)
	elif is_host():
		var pl := {Net.my_id: _my_state()}
		for id in remotes:
			var r: Dictionary = remotes[id]
			pl[id] = {"p": [r.pos.x, r.pos.y, r.pos.z], "y": r.yaw, "pi": r.pitch, "f": r.fl, "e": r.eyes, "s": r.sees, "on": r.on}
		var en: Array = []
		for e in main.entities:
			var ep: Vector3 = e.global_position
			en.append({"a": e.active, "p": [ep.x, ep.y, ep.z]})
		Net.send({"t": "world", "pl": pl, "en": en, "lv": G.level})


# --- 받기 ---

func _on_message(m: Dictionary) -> void:
	var t: String = m.get("t", "")
	var from: String = m.get("_from", "")
	match t:
		"_open", "_connected", "_error", "full":
			net_event.emit(t, m)
		"_join":
			if is_host():
				Net.send({"t": "welcome", "flags": _shared_flags(), "inv": G.inv, "level": G.level, "you": from}, from)
				main.hud.toast("누군가 노란 방에 들어왔다. (%d명)" % (player_count() + 1))
		"_leave":
			if remotes.has(from):
				_remove(from)
				main.hud.toast("동료의 발소리가 사라졌다. (%d명)" % player_count())
			if is_client():
				net_event.emit("host_left", m)
		"welcome":
			net_event.emit("welcome", m)
		"level":
			if is_client():
				main.go_level(int(m.get("i", 0)), false)
		"exit":
			if is_host():
				main.request_exit()
		"st":
			if is_host():
				_update_remote(from, m)
		"world":
			if is_client():
				_apply_world(m)
		"flag":
			var k: String = m.get("k", "")
			if is_host():
				Net.send({"t": "flag", "k": k})
			_apply_remote_flag(k)
		"caught":
			if is_client() and m.get("id", "") == Net.my_id:
				main.on_caught_local()
		"ping":
			if is_host():
				Net.send(m)
			_show_ping(m.get("id", ""))
		"esc":
			if is_host():
				Net.send(m)
			var id: String = m.get("id", "")
			if remotes.has(id):
				_remove(id)
			main.hud.toast("동료가 어긋난 벽 속으로 사라졌다...", 5.0)


func _update_remote(id: String, m: Dictionary) -> void:
	if id == Net.my_id or id == "":
		return
	var fresh := not remotes.has(id)
	if fresh:
		_add(id)
	var r: Dictionary = remotes[id]
	var p: Array = m.get("p", [0, 0, 0])
	r.pos = Vector3(p[0], p[1], p[2])
	if fresh:
		r.node.global_position = r.pos
	r.yaw = float(m.get("y", 0.0))
	r.pitch = float(m.get("pi", 0.0))
	r.fl = bool(m.get("f", false))
	r.eyes = bool(m.get("e", false))
	var s = m.get("s", [])
	r.sees = s if typeof(s) == TYPE_ARRAY else []
	r.on = bool(m.get("on", true))
	r.node.visible = r.on


func _apply_world(m: Dictionary) -> void:
	var pl: Dictionary = m.get("pl", {})
	for id in pl:
		if id != Net.my_id:
			_update_remote(id, pl[id])
	for id in remotes.keys():
		if not pl.has(id):
			_remove(id)
	if int(m.get("lv", G.level)) != G.level:
		return
	var en: Array = m.get("en", [])
	_entity_targets.resize(en.size())
	for i in mini(en.size(), main.entities.size()):
		var e = main.entities[i]
		var was: bool = e.active
		e.active = bool(en[i].get("a", false))
		e.visible = e.active
		var ep: Array = en[i].get("p", [9999, 0, 9999])
		_entity_targets[i] = Vector3(ep[0], ep[1], ep[2])
		if e.active and not was:
			e.global_position = _entity_targets[i]


# --- 진행 공유 ---

func _shared_flags() -> Dictionary:
	var out := {}
	for k in G.flags:
		if G.flags[k] and not k in NOT_SHARED:
			out[k] = true
	return out


func _on_local_flag(k: String) -> void:
	if not active or k in NOT_SHARED:
		return
	Net.send({"t": "flag", "k": k})


func _apply_remote_flag(k: String) -> void:
	if k == "" or k in NOT_SHARED or G.has(k):
		return
	G.flags[k] = true
	G.save_game()
	main.apply_flag_effect(k, true)


# --- 부르기 / 탈출 알림 ---

func ping() -> void:
	if not active:
		return
	Net.send({"t": "ping", "id": Net.my_id})
	Sfx.play("call", -6.0)
	main.hud.toast("「여기야!」", 1.5)


func _show_ping(id: String) -> void:
	if id == Net.my_id or not remotes.has(id):
		return
	remotes[id].ping = 3.0
	var d: float = main.player.global_position.distance_to(remotes[id].pos)
	Sfx.play("call", clampf(-4.0 - d * 0.6, -24.0, -4.0))
	main.hud.toast("동료가 부른다. (%dm)" % int(d), 2.5)


func announce_escape() -> void:
	if active:
		Net.send({"t": "esc", "id": Net.my_id})


# --- '그것' (방장 전용) ---

## 방장이 '그것'을 움직일 때 쓰는 동료 목록.
func watchers() -> Array:
	var out: Array = []
	for id in remotes:
		var r: Dictionary = remotes[id]
		if r.on:
			out.append({"id": id, "pos": r.pos, "sees": r.sees})
	return out


func send_caught(id: String) -> void:
	Net.send({"t": "caught", "id": id})


func remote_flashlights() -> Array:
	var out: Array = []
	for id in remotes:
		var r: Dictionary = remotes[id]
		if r.fl and r.on:
			var dir := Vector3(-sin(r.yaw) * cos(r.pitch), sin(r.pitch), -cos(r.yaw) * cos(r.pitch))
			out.append([r.pos + Vector3(0, 1.5, 0), dir])
	return out


# --- 아바타 ---

func _add(id: String) -> void:
	var idx := remotes.size() + 1
	var color: Color = COLORS[idx % COLORS.size()]
	var root := Node3D.new()
	add_child(root)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.45
	body.mesh = cap
	body.position.y = 0.75
	body.material_override = main.level.make_material(3, color)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.17
	sp.height = 0.34
	head.mesh = sp
	head.position.y = 1.62
	head.material_override = main.level.make_material(3, Color("d9b48f"))
	root.add_child(head)
	var torch := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.035
	tm.bottom_radius = 0.045
	tm.height = 0.22
	torch.mesh = tm
	torch.rotation.x = PI / 2
	torch.position = Vector3(0.22, 1.25, -0.25)
	torch.material_override = main.level.make_material(3, Color("333333"))
	root.add_child(torch)
	var tag := Label3D.new()
	tag.text = "동료 %d" % idx
	tag.font = main.level.font
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(color.lightened(0.4), 0.85)
	tag.position.y = 2.05
	tag.no_depth_test = true
	root.add_child(tag)
	var ping_tag := Label3D.new()
	ping_tag.name = "Ping"
	ping_tag.text = "!"
	ping_tag.font = main.level.font
	ping_tag.font_size = 160
	ping_tag.pixel_size = 0.004
	ping_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ping_tag.modulate = Color("ffd34d")
	ping_tag.position.y = 2.55
	ping_tag.no_depth_test = true
	ping_tag.visible = false
	root.add_child(ping_tag)
	remotes[id] = {"node": root, "pos": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0, "fl": false,
		"eyes": false, "sees": [], "on": true, "ping": 0.0, "tag": tag.text}


func _remove(id: String) -> void:
	if remotes.has(id):
		remotes[id].node.queue_free()
		remotes.erase(id)
