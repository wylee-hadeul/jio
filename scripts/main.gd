extends Node3D
## 게임 진행 담당: 레벨을 짓고, 조사·퍼즐·숫자 발견·잡힘·다음 레벨·엔딩·같이 하기를 처리한다.

const Levels := preload("res://scripts/levels.gd")
const Level := preload("res://scripts/level.gd")
const Player := preload("res://scripts/player.gd")
const Entity := preload("res://scripts/entity.gd")
const Hud := preload("res://scripts/hud.gd")
const Autoplay := preload("res://scripts/autoplay.gd")
const Coop := preload("res://scripts/coop.gd")

const INTERACT_DIST := 3.2
const GAZE_DOT := 0.93
const GAZE_DIST := 6.5
const HUM_VOLUME := 0.3
const PROMPTS := {
	"note": "쪽지 읽기", "pack": "배낭 뒤지기", "phone": "전화기", "room_door": "번호판", "exit_door": "출구",
	"elevator": "승강기", "lever": "밸브 돌리기", "breaker": "차단기", "hatch": "천장 문", "key": "열쇠 줍기",
	"balloon": "풍선 터뜨리기", "numdoor": "문 열기",
}
const DIGIT_TEXT := {
	"ceiling": "천장 타일에 붉은 글씨가 휘갈겨져 있다.",
	"floor": "발밑 바닥에 붉은 글씨가 적혀 있다.",
	"pillar": "기둥 뒤쪽 면에 숫자가 적혀 있다.",
	"dark": "손전등 불빛 속에 글씨가 떠오른다.",
	"behind": "처음 서 있던 자리, 등 뒤의 벽에 숫자가 있었다.",
}
const LEVEL0_DIGIT_TEXT := {
	"digit_ceiling": "천장 타일에 붉은 글씨가 휘갈겨져 있다.\n「7」",
	"digit_pillar": "기둥 뒤쪽 면에 숫자가 적혀 있다.\n「3」",
	"digit_dark": "손전등 불빛 속에 글씨가 떠오른다.\n「9」 ...그것은 어둠 속에서 웃는다.",
}

var level: Level
var layout: Dictionary
var player: Player
var entities: Array = []
var hud: Hud
var coop: Coop
var playing := false
## 예전 코드/테스트 호환: 첫 번째 '그것'
var entity: Entity:
	get:
		return entities[0] if not entities.is_empty() else null

var _flicker := 1.0
var _flicker_timer := 3.0
var _flicker_seq: Array[float] = []
var _soft_wall_warned := false
## 테스트용: 켜면 '그것'들이 움직이지 않는다(오토플레이의 레벨 공략 중)
var freeze_entities := false
var _ending := false
var _exiting := false


func _ready() -> void:
	player = Player.new()
	add_child(player)
	coop = Coop.new()
	add_child(coop)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.player = player
	hud.tapped.connect(_on_tap)
	hud.flashlight_pressed.connect(_toggle_flashlight)
	hud.hint_pressed.connect(func(): hud.toast(G.hint(), 5.0))
	hud.menu_pressed.connect(_open_menu)
	hud.eyes_changed.connect(func(closed: bool): Sfx.play("click", -18.0, 0.6 if closed else 0.8))
	hud.ping_pressed.connect(func(): coop.ping())
	coop.setup(self)
	coop.net_event.connect(func(t: String, _d: Dictionary):
		if t == "host_left" and coop.is_client():
			_leave_coop()
			_despawn_all()
			playing = false
			hud.close_all_panels()
			hud.toast("방장이 나갔다. 노란 방이 흐려진다...", 5.0)
			_show_title())
	load_level(0)
	_show_title()
	if G.autoplay:
		var bot := Autoplay.new()
		bot.main = self
		add_child(bot)


# --- 레벨 ---

## i번째 레벨을 새로 짓는다(진행 플래그는 건드리지 않는다).
func load_level(i: int) -> void:
	if level:
		level.queue_free()
		remove_child(level)
	for e in entities:
		e.queue_free()
	entities.clear()
	layout = Levels.make(i)
	level = Level.new()
	add_child(level)
	level.build(layout)
	var ent: Dictionary = layout.entity
	for n in int(ent.count):
		var e := Entity.new()
		add_child(e)
		e.setup(level)
		e.index = n
		e.mode = ent.get("mode", "weeping")
		e.speed = float(ent.get("speed", 1.9))
		e.caught.connect(_on_entity_caught)
		entities.append(e)
	G.hints = layout.hints
	if i == 0:
		G.digit_keys = ["digit_ceiling", "digit_pillar", "digit_phone", "digit_dark"]
		G.digit_values = {"digit_ceiling": "7", "digit_pillar": "3", "digit_phone": "5", "digit_dark": "9"}
	else:
		G.digit_values = {}
		for d in layout.digits:
			G.digit_values[d.key] = d.value
		for p in layout.props:
			if p.kind == "phone":
				G.digit_values[p.data.digit] = p.data.value
		G.digit_keys = G.digit_values.keys()
		G.digit_keys.sort()
	_soft_wall_warned = false
	_exiting = false


## 다음 레벨(또는 i번째 레벨)로 이동. announce: 같이 하기에서 방장이 모두에게 알린다.
func go_level(i: int, announce: bool) -> void:
	playing = false
	hud.close_all_panels()
	hud.clear_toasts()
	_despawn_all()
	if announce and coop.is_host():
		Net.send({"t": "level", "i": i})
	G.level = i
	G.flags = {}
	load_level(i)
	G.checkpoint = level.cell_center(level.start)
	G.checkpoint_yaw = layout.start_yaw
	player.teleport(G.checkpoint, G.checkpoint_yaw)
	player.eyes_closed = false
	_apply_progress()
	G.save_game()
	Sfx.play("whoosh", -4.0)
	var card: Array = ["%s\n\n%s" % [layout.name, layout.title]]
	card.append_array(layout.intro)
	hud.show_lines(card, func(): _start_play(), true)


## 출구에 닿았을 때. 같이 하기 참가자는 방장에게 부탁한다.
func request_exit() -> void:
	if _exiting:
		return
	if coop.is_client():
		Net.send({"t": "exit"})
		return
	_exiting = true
	if layout.final:
		_final_ending()
		return
	go_level(G.level + 1, true)


# --- 시작/이어하기 ---

func _show_title() -> void:
	playing = false
	hud.visible = true
	hud.room_label = ""
	G.save_path = G.AUTOPLAY_SAVE_PATH if G.autoplay else G.SAVE_PATH
	var options: Array = []
	var invited := Net.url_room()
	if invited != "":
		options.append(["방 %s 참가하기" % invited, func(): _join_room(invited)])
	if G.has_save() and not G.autoplay:
		var saved_level := _saved_level()
		options.append(["이어하기 (%s)" % Levels.level_name(saved_level), func(): _begin(true)])
		options.append(["처음부터", func(): _begin(false)])
	else:
		options.append(["혼자 하기", func(): _begin(false)])
	if Net.enabled:
		options.append(["방 만들기 (같이 하기)", func(): _host_room("")])
		if invited == "":
			options.append(["방 번호로 참가하기", func(): hud.show_keypad(func(code: String) -> bool:
				if code.length() != 4:
					return false
				_join_room.call_deferred(code)
				return true, "방 번호 4자리")])
	hud.show_menu("백룸", "LEVEL 0 부터 LEVEL ? 까지 %d개 층\n\n소리를 켜고 이어폰을 권장합니다" % Levels.count(), options)


func _saved_level() -> int:
	var data = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
	return int(data.get("level", 0)) if typeof(data) == TYPE_DICTIONARY else 0


func _begin(resume: bool) -> void:
	hud.toast("...", 0.8)
	await Sfx.build()
	_ending = false
	_despawn_all()
	if resume and G.load_game():
		load_level(G.level)
		_apply_progress()
		var pos := G.checkpoint if G.checkpoint != Vector3.ZERO else level.cell_center(level.start)
		player.teleport(pos, G.checkpoint_yaw)
		_start_play()
		return
	G.reset()
	load_level(0)
	G.checkpoint = level.cell_center(level.start)
	G.checkpoint_yaw = layout.start_yaw
	player.teleport(G.checkpoint, G.checkpoint_yaw)
	player.flashlight_on = false
	_apply_progress()
	hud.show_lines(G.INTRO, func(): _start_play(), true)


## 저장된/공유된 진행을 화면과 세계에 반영한다.
func _apply_progress() -> void:
	hud.show_flashlight_button = G.has("flashlight")
	if not G.has("flashlight"):
		player.flashlight_on = false
	hud.show_digits = not G.digit_keys.is_empty() and (G.level != 0 or G.has("note2"))
	for k in G.flags.keys():
		apply_flag_effect(k, false, true)
	_update_counters()


func _start_play() -> void:
	playing = true
	G.save_game()
	_maybe_spawn()


## 레벨의 '그것' 등장 규칙: start 즉시 / note 첫 쪽지 뒤 / note2 레벨 0의 두 번째 쪽지 뒤
func _maybe_spawn() -> void:
	if coop.is_client() or _ending or entities.is_empty() or entities[0].active:
		return
	var rule: String = layout.entity.get("spawn", "note")
	var go := false
	match rule:
		"start":
			go = true
		"note2":
			go = G.has("note2")
		"note":
			for k in G.flags:
				if str(k).begins_with("note"):
					go = true
	if go:
		_spawn_all(player.global_position)


func _spawn_all(near: Vector3) -> void:
	for e in entities:
		e.spawn_far(near, player.camera)


func _despawn_all() -> void:
	for e in entities:
		e.despawn()


# --- 같이 하기 ---

func _host_room(code: String) -> void:
	hud.toast("방을 만드는 중...", 2.0)
	await Sfx.build()
	for attempt in 4:
		var c := code if code != "" and attempt == 0 else Net.random_code()
		Net.host(c)
		var ev := await _wait_net(["_open", "_error"], 15.0)
		if ev.get("t") == "_open":
			_enter_coop(c)
			await _begin(false)
			hud.toast("방 번호 %s\n일시정지(||) 메뉴에서 초대 링크를 보낼 수 있다." % c, 6.0)
			return
		Net.leave()
		if ev.get("e", "") != "unavailable-id":
			break
	hud.toast("방을 만들지 못했다. 인터넷 연결을 확인해 주세요.", 5.0)
	_show_title()


func _join_room(code: String) -> void:
	hud.toast("방 %s 에 들어가는 중..." % code, 3.0)
	await Sfx.build()
	Net.join(code)
	var ev := await _wait_net(["_connected", "_error"], 20.0)
	if ev.get("t") != "_connected":
		Net.leave()
		hud.toast("방 %s 을(를) 찾지 못했다." % code, 5.0)
		_show_title()
		return
	ev = await _wait_net(["welcome", "full", "host_left"], 15.0)
	if ev.get("t") != "welcome":
		Net.leave()
		hud.toast("방이 가득 찼거나 응답이 없다." if ev.get("t") == "full" else "방장과 연결이 끊겼다.", 5.0)
		_show_title()
		return
	_enter_coop(code)
	_ending = false
	G.reset()
	G.inv = ev.get("inv", {})
	G.level = int(ev.get("level", 0))
	load_level(G.level)
	for k in ev.get("flags", {}):
		G.flags[k] = true
	G.checkpoint = level.cell_center(level.start)
	G.checkpoint_yaw = layout.start_yaw
	player.teleport(G.checkpoint, G.checkpoint_yaw)
	_apply_progress()
	G.save_game()
	var card: Array = ["%s\n\n%s" % [layout.name, layout.title]]
	if G.level == 0:
		card = G.INTRO.duplicate()
	hud.show_lines(card, func(): _start_play(), true)


func _enter_coop(code: String) -> void:
	G.save_path = G.COOP_SAVE_PATH
	coop.begin()
	hud.room_label = "방 " + code


func _leave_coop() -> void:
	coop.end()
	hud.room_label = ""


func _wait_net(kinds: Array, timeout: float) -> Dictionary:
	var box := {"ev": {}}
	var cb := func(t: String, data: Dictionary):
		if t in kinds and box.ev.is_empty():
			var d := data.duplicate()
			d.t = t
			box.ev = d
	coop.net_event.connect(cb)
	var t := 0.0
	while box.ev.is_empty() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	coop.net_event.disconnect(cb)
	return box.ev


# --- 진행 반영 ---

## 플래그 k가 켜졌을 때 세계/화면 반영. remote: 동료가 해낸 일, silent: 불러오기 중(알림/소리 없음).
func apply_flag_effect(k: String, remote: bool, silent := false) -> void:
	var says := remote and not silent
	if k == "flashlight":
		hud.show_flashlight_button = true
		if says:
			hud.toast("동료가 손전등을 찾았다. 손전등 버튼이 생겼다.", 4.0)
	elif k == "note2" and G.level == 0:
		hud.show_digits = true
		if says:
			hud.toast("동료가 출구에 대한 쪽지를 찾았다. 번호 칸이 생겼다.", 4.0)
	elif k == "door_open":
		level.open_door(not silent)
		if says:
			hud.toast("멀리서 철컥, 하고 문 열리는 소리가 났다.", 4.0)
	elif k == "exit_open":
		_open_exit(silent)
		if says:
			hud.toast("어딘가에서 출구가 열렸다.", 4.0)
	elif k.begins_with("lever_") or k.begins_with("breaker_"):
		level.set_prop_state(k, true)
		if says:
			hud.toast("동료가 %s를 움직였다." % ("밸브" if k.begins_with("lever") else "차단기"), 3.0)
	elif k.begins_with("key_") or k.begins_with("balloon_"):
		level.remove_prop(k)
		if says:
			hud.toast("동료가 %s." % ("열쇠를 주웠다" if k.begins_with("key") else "풍선을 터뜨렸다"), 3.0)
	elif G.digit_values.has(k):
		if says:
			hud.toast("동료가 숫자를 찾았다.\n번호  " + " ".join(G.digits_found().split("")), 4.0)
	elif k.begins_with("note") and says:
		hud.toast("동료가 쪽지를 읽었다.", 2.5)
	_update_counters()
	_check_all_done()
	if not silent and playing:
		_maybe_spawn()


func _update_counters() -> void:
	if not level.props.has("exit"):
		return
	var needs: Array = layout.exit.get("needs", [])
	if needs.is_empty():
		return
	var done := 0
	for n in needs:
		if G.has(n):
			done += 1
	level.set_counter("exit", done, needs.size())


## 열쇠/밸브/차단기/풍선을 모두 모으면 출구가 열린다.
func _check_all_done() -> void:
	var ex: Dictionary = layout.exit
	if G.has("exit_open") or ex.kind in ["noclip", "numdoor"] or ex.get("code", "") != "":
		return
	var needs: Array = ex.get("needs", [])
	if needs.is_empty():
		return
	for n in needs:
		if not G.has(n):
			return
	G.set_flag("exit_open")
	apply_flag_effect("exit_open", false)
	match ex.kind:
		"hatch":
			hud.toast("완전한 어둠.\n...천장에서 무언가 초록빛으로 빛난다.", 5.0)
		"elevator":
			Sfx.play("unlock")
			hud.toast("띵. 승강기에 불이 들어왔다.", 4.0)
		_:
			Sfx.play("unlock")
			hud.toast("철컥. 어딘가의 출구가 열렸다.", 4.0)


func _open_exit(silent: bool) -> void:
	if not level.props.has("exit"):
		return
	match layout.exit.kind:
		"hatch":
			level.set_lights_out(true)
			level.reveal_hatch("exit")
		"door", "elevator":
			if level.props["exit"].body.get_node_or_null("Void") == null:
				level.open_wall_door("exit")
	if not silent:
		flicker_burst(20)


# --- 매 프레임 ---

func _process(delta: float) -> void:
	player.frozen = hud.is_blocked() or not playing
	_update_flicker(delta)
	_update_shader()
	coop.tick(delta)
	if coop.is_host() and not _ending and not freeze_entities:
		for e in entities:
			e.tick(delta, player, coop.watchers())
	if not playing:
		_update_audio(INF)
		return
	if not coop.active and not hud.is_blocked() and not freeze_entities:
		for e in entities:
			e.tick(delta, player)
	var ent_dist := INF
	for e in entities:
		if e.active:
			ent_dist = minf(ent_dist, player.global_position.distance_to(e.global_position))
	_update_audio(ent_dist)
	hud.danger = clampf(1.0 - (ent_dist - 2.0) / 10.0, 0.0, 1.0)
	_update_prompt()
	_update_digit_labels()
	if not hud.is_blocked():
		_check_gaze_digits()
		_check_anomaly()


func _update_shader() -> void:
	var cam := player.camera
	level.set_shared("cam_pos", cam.global_position)
	var fl_pos := PackedVector3Array([cam.global_position, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var fl_dir := PackedVector3Array([player.look_dir(), Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	var fl_on := PackedFloat32Array([1.0 if player.flashlight_on else 0.0, 0.0, 0.0, 0.0])
	var i := 1
	for light in coop.remote_flashlights():
		if i >= 4:
			break
		fl_pos[i] = light[0]
		fl_dir[i] = light[1]
		fl_on[i] = 1.0
		i += 1
	level.set_shared("fl_pos", fl_pos)
	level.set_shared("fl_dir", fl_dir)
	level.set_shared("fl_on", fl_on)
	level.set_shared("flicker", _flicker)
	var ep := PackedVector3Array([Vector3(9999, 0, 9999), Vector3(9999, 0, 9999), Vector3(9999, 0, 9999)])
	for n in mini(3, entities.size()):
		if entities[n].active:
			ep[n] = entities[n].global_position
	level.set_shared("entity_pos", ep)


func _update_flicker(delta: float) -> void:
	if not _flicker_seq.is_empty():
		_flicker = _flicker_seq.pop_front()
		return
	_flicker = 1.0
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(4.0, 11.0)
		flicker_burst(randi_range(6, 16))


func flicker_burst(frames: int) -> void:
	for i in frames:
		_flicker_seq.append(randf_range(0.15, 1.0) if i % 3 != 0 else 1.0)


func _update_audio(ent_dist: float) -> void:
	if not Sfx.ready_built:
		return
	var near := clampf((ent_dist - 2.5) / 8.0, 0.0, 1.0)
	var hum := HUM_VOLUME * near * (0.6 + 0.4 * _flicker) if playing else 0.0
	if layout.exit.kind == "hatch" and G.has("exit_open"):
		hum = 0.0
	Sfx.set_loop("hum", hum)
	Sfx.set_loop("drone", clampf(1.0 - (ent_dist - 2.0) / 14.0, 0.0, 1.0) * 0.9 if playing else 0.0)
	Sfx.set_loop("heartbeat", 0.8 if playing and ent_dist < 9.0 else 0.0)
	var ring := 0.0
	if playing and _phone_ringing():
		var d := player.global_position.distance_to(level.props["phone"].target)
		ring = clampf(1.0 - d / 30.0, 0.0, 1.0) * 0.8
	Sfx.set_loop("ring", ring)


func _phone_ringing() -> bool:
	if not level.props.has("phone"):
		return false
	var key: String = level.props["phone"].data.digit
	return not G.has(key) and (G.level != 0 or G.has("note2"))


# --- 조사 ---

func _ray_target(screen_pos: Vector2) -> Node:
	var cam := player.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * INTERACT_DIST
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	# 물체 바로 옆에 서서 누르면 광선이 조사용 상자 안에서 시작한다: 그때도 맞은 것으로 친다
	q.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var n: Node = hit.collider
	return n if n.has_meta("id") else null


func _update_prompt() -> void:
	var t := _ray_target(get_viewport().get_visible_rect().size * 0.5)
	if t == null or player.eyes_closed:
		hud.prompt = ""
		return
	var id: String = t.get_meta("id")
	if not level.props.has(id):
		hud.prompt = ""
		return
	var kind: String = level.props[id].kind
	hud.prompt = "전화 받기" if kind == "phone" and _phone_ringing() else PROMPTS.get(kind, "")


func _on_tap(screen_pos: Vector2) -> void:
	if not playing or player.eyes_closed:
		return
	var t := _ray_target(screen_pos)
	if t == null:
		t = _ray_target(get_viewport().get_visible_rect().size * 0.5)
	if t:
		interact(t.get_meta("id"))


func interact(id: String) -> void:
	if not level.props.has(id):
		return
	var p: Dictionary = level.props[id]
	match p.kind:
		"note":
			_read_note(id, p.data.text)
		"pack":
			_open_pack(p)
		"phone":
			_use_phone(p)
		"room_door":
			_use_room_door(p)
		"exit_door", "elevator":
			_use_exit(p)
		"hatch":
			if G.has("exit_open"):
				hud.show_lines(["천장 문을 밀어 올린다.\n...그 위로 몸을 끌어 올린다."], func(): request_exit())
			else:
				hud.toast("천장에 손잡이 같은 것이 있다.\n너무 어두워서... 아니, 너무 밝아서 잘 안 보인다.")
		"lever", "breaker":
			if G.has(id):
				hud.toast("이미 %s." % ("돌려 놓았다" if p.kind == "lever" else "내려 놓았다"))
				return
			Sfx.play("buzz" if p.kind == "breaker" else "click", -8.0, 0.7)
			G.set_flag(id)
			apply_flag_effect(id, false)
			var needs: Array = layout.exit.get("needs", [])
			var done := needs.filter(func(n): return G.has(n)).size()
			hud.toast("%s (%d / %d)" % ["밸브를 끝까지 돌렸다" if p.kind == "lever" else "차단기를 내렸다. 주변이 웅 하고 울린다", done, needs.size()], 2.5)
		"key", "balloon":
			Sfx.play("click" if p.kind == "key" else "buzz", -4.0, 1.4 if p.kind == "key" else 2.5)
			G.set_flag(id)
			apply_flag_effect(id, false)
			var needs: Array = layout.exit.get("needs", [])
			var done := needs.filter(func(n): return G.has(n)).size()
			hud.toast("%s (%d / %d)" % ["차가운 열쇠를 주웠다" if p.kind == "key" else "펑! 풍선이 터졌다", done, needs.size()], 2.5)
		"numdoor":
			_use_numdoor(p)


func _read_note(id: String, text: String) -> void:
	var first := not G.has(id)
	hud.show_note(text, func():
		if not first:
			return
		G.checkpoint = player.global_position
		G.checkpoint_yaw = player.yaw
		G.set_flag(id)
		if G.level == 0 and id == "note2":
			hud.toast("어디선가 전화벨이 울린다.\n...그리고 아주 잠깐, 형광등 소리가 끊겼다.", 5.0)
			flicker_burst(30)
		elif G.level == 0 and id == "note6":
			hud.toast("어긋난 벽... 처음 떨어진 곳 근처였다.", 5.0)
		apply_flag_effect(id, false))


func _open_pack(p: Dictionary) -> void:
	if G.has("flashlight"):
		hud.toast("텅 빈 배낭이다. 지수의 이름표가 달려 있다.")
		return
	G.set_flag("flashlight")
	apply_flag_effect("flashlight", false)
	player.flashlight_on = true
	Sfx.play("click", -6.0)
	hud.show_lines(["배낭 안에 손전등이 있다. 아직 켜진다.", "그 밑에 접힌 쪽지 한 장."], func(): _read_note(p.data.note, p.data.text))


func _use_phone(p: Dictionary) -> void:
	if not _phone_ringing():
		hud.toast("수화기 너머엔 아무 소리도 없다.")
		return
	Sfx.set_loop("ring", 0.0)
	Sfx.play("static", -8.0)
	var key: String = p.data.digit
	G.set_flag(key)
	apply_flag_effect(key, false)
	hud.show_lines(p.data.lines, func(): hud.toast("목소리가 말한 숫자: %s" % p.data.value))


func _use_room_door(p: Dictionary) -> void:
	if G.has("door_open"):
		hud.toast("문은 열려 있다. 안쪽이 이상하게 어둡다.")
		return
	hud.show_keypad(func(code: String) -> bool:
		if code == p.data.code:
			Sfx.play("unlock")
			G.set_flag("door_open")
			apply_flag_effect("door_open", false)
			hud.toast("철컥. 빨간 문이 열린다.", 3.0)
			return true
		Sfx.play("buzz", -4.0)
		flicker_burst(40)
		return false)


func _use_exit(p: Dictionary) -> void:
	if G.has("exit_open"):
		hud.show_lines(["문 너머는 완전한 어둠이다.\n...한 걸음 내디딘다."], func(): request_exit())
		return
	var code: String = p.data.get("code", "")
	if code != "":
		hud.show_keypad(func(entered: String) -> bool:
			if entered == code:
				Sfx.play("unlock")
				G.set_flag("exit_open")
				apply_flag_effect("exit_open", false)
				hud.toast("철컥. 문이 열렸다. 들어가자.", 3.0)
				return true
			Sfx.play("buzz", -4.0)
			flicker_burst(40)
			return false, "%d자리" % code.length())
		return
	var needs: Array = p.data.get("needs", [])
	if needs.is_empty():
		G.set_flag("exit_open")
		apply_flag_effect("exit_open", false)
		request_exit()
		return
	var done := needs.filter(func(n): return G.has(n)).size()
	var what: String = {"elevator": "전기가 들어오지 않는다", "exit_door": "잠겨 있다"}[p.kind]
	hud.toast("%s. (%d / %d)" % [what, done, needs.size()], 2.5)


func _use_numdoor(p: Dictionary) -> void:
	if p.data.correct:
		G.set_flag("exit_open")
		Sfx.play("unlock")
		hud.show_lines(["%d호. 문이 스르르 열린다.\n안쪽에서 바람이 분다." % p.data.number], func(): request_exit())
		return
	Sfx.play("buzz", -2.0)
	hud.scare()
	await get_tree().create_timer(0.9).timeout
	hud.show_lines(["%d호 안에는 웃는 얼굴이 가득했다." % p.data.number, "...정신을 차리자 처음 그 자리다."], func():
		player.teleport(level.cell_center(level.start), layout.start_yaw))


func _toggle_flashlight() -> void:
	if not G.has("flashlight") or not playing:
		return
	player.flashlight_on = not player.flashlight_on
	Sfx.play("click", -8.0)


# --- 숫자 발견 (시선) ---

func _update_digit_labels() -> void:
	var cam := player.camera
	for key in level.digit_labels:
		var info: Dictionary = level.digit_labels[key]
		var label: Label3D = info.label
		var d := cam.global_position.distance_to(label.global_position)
		var a := 1.0 - smoothstep(6.0, 18.0, d)
		if info.kind == "dark" or level.is_dark(level.cell_at(label.global_position)):
			var to := (label.global_position - cam.global_position).normalized()
			var cone := smoothstep(0.86, 0.97, to.dot(player.look_dir())) if player.flashlight_on else 0.0
			a *= cone * clampf(1.0 - d / 16.0, 0.0, 1.0) * 1.4
		label.modulate.a = clampf(a, 0.0, 1.0)
		for child in label.get_children():
			if child is Label3D:
				child.modulate.a = label.modulate.a


func _check_gaze_digits() -> void:
	var cam := player.camera
	for key in level.digit_labels:
		if G.has(key):
			continue
		var info: Dictionary = level.digit_labels[key]
		var label: Label3D = info.label
		var to := label.global_position - cam.global_position
		if to.length() > GAZE_DIST or to.normalized().dot(player.look_dir()) < GAZE_DOT:
			continue
		if label.modulate.a < 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, label.global_position - to.normalized() * 0.05)
		q.exclude = [player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		G.set_flag(key)
		apply_flag_effect(key, false)
		Sfx.play("sting" if info.kind == "dark" else "paper", -10.0, 0.6 if info.kind == "dark" else 1.0)
		if G.level == 0:
			hud.toast(LEVEL0_DIGIT_TEXT[key], 4.5)
		else:
			var extra := "\n(물에 비친 것처럼 좌우가 뒤집혀 있다)" if label.scale.x < 0 else ""
			hud.toast("%s\n「%s」%s" % [DIGIT_TEXT.get(info.kind, ""), info.value, extra], 4.5)


# --- 어긋난 벽 / 엔딩 ---

func _anomaly_ready() -> bool:
	for n in layout.exit.get("needs", []):
		if not G.has(n):
			return false
	return true


func _check_anomaly() -> void:
	if level.anomaly.x < 0:
		return
	var passable: bool = player.eyes_closed and _anomaly_ready()
	level.set_anomaly_passable(passable)
	var center: Vector3 = level.cell_center(level.anomaly)
	var flat := Vector2(player.global_position.x - center.x, player.global_position.z - center.z)
	if passable and absf(flat.x) < level.CELL * 0.4 and absf(flat.y) < level.CELL * 0.4:
		_through_wall()
	elif player.eyes_closed and not _anomaly_ready() and not _soft_wall_warned \
			and absf(flat.x) < level.CELL * 0.62 and absf(flat.y) < level.CELL * 0.62:
		_soft_wall_warned = true
		hud.toast("손끝에 닿은 벽이 물렁하다.\n...하지만 아직 발이 떨어지지 않는다.", 4.0)


func _through_wall() -> void:
	if _exiting:
		return
	G.set_flag("escaped")
	player.eyes_closed = false
	if coop.is_client():
		Net.send({"t": "exit"})
		_exiting = true
		return
	request_exit()


func _final_ending() -> void:
	if _ending:
		return
	_ending = true
	playing = false
	_despawn_all()
	coop.announce_escape()
	Sfx.stop_all()
	Sfx.play("whoosh")
	hud.close_all_panels()
	hud.show_lines(G.ENDING, func():
		hud.show_menu("탈출", "%d개 층을 지나 노란 방을 벗어났다.\n...아니면, 처음으로 돌아왔다." % Levels.count(), [["처음으로", func():
			_leave_coop()
			G.reset()
			load_level(0)
			_show_title()]]), true)


func _on_entity_caught(id: String) -> void:
	if id == "":
		on_caught_local()
		return
	coop.send_caught(id)
	var victim: Vector3 = coop.remotes[id].pos if coop.remotes.has(id) else player.global_position
	for e in entities:
		if e.global_position.distance_to(victim) < 3.0:
			e.spawn_far(victim, player.camera)
	hud.toast("어디선가 비명이 들렸다.", 3.0)


func on_caught_local() -> void:
	if not playing:
		return
	playing = false
	hud.scare()
	await get_tree().create_timer(1.0).timeout
	hud.show_lines(G.CAUGHT_LINES, func():
		var pos := G.checkpoint if G.checkpoint != Vector3.ZERO else level.cell_center(level.start)
		player.teleport(pos, G.checkpoint_yaw)
		player.eyes_closed = false
		playing = true
		if not coop.is_client():
			for e in entities:
				if e.active or layout.entity.get("spawn", "") == "start":
					e.spawn_far(player.global_position, player.camera), true)


func _open_menu() -> void:
	if not playing or hud.is_blocked():
		return
	var sub := "%s · %s" % [layout.name, layout.title]
	if not G.digit_keys.is_empty():
		sub += "\n찾은 번호  " + " ".join(G.digits_found().split(""))
	var options: Array = [["계속하기", func(): pass]]
	if coop.active:
		sub += "\n\n방 %s  |  %d명" % [Net.room, coop.player_count()]
		options.append(["초대 링크 보내기", func():
			var r := Net.share_invite()
			hud.toast("초대 링크를 복사했다.\n" + Net.invite_url() if r == "copied" else "방 번호 " + Net.room, 5.0)])
		options.append(["방 나가기", func():
			_leave_coop()
			_despawn_all()
			playing = false
			_show_title()])
	else:
		options.append(["처음부터", func():
			G.reset()
			_despawn_all()
			playing = false
			_begin(false)])
	hud.show_menu("일시정지", sub, options, false)
