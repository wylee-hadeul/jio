extends Node3D
## 게임 진행 담당: 레벨/플레이어/그것/HUD를 만들고, 조사·숫자 발견·잡힘·엔딩을 처리한다.

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
	"note1": "쪽지 읽기", "note2": "쪽지 읽기", "note4": "쪽지 읽기", "note5": "쪽지 읽기", "note6": "쪽지 읽기",
	"pack": "배낭 뒤지기", "phone": "전화기", "door": "번호판",
}
const DIGIT_TEXT := {
	"digit_ceiling": "천장 타일에 붉은 글씨가 휘갈겨져 있다.\n「7」",
	"digit_pillar": "기둥 뒤쪽 면에 숫자가 적혀 있다.\n「3」",
	"digit_dark": "손전등 불빛 속에 글씨가 떠오른다.\n「9」 ...그것은 어둠 속에서 웃는다.",
}

var level: Level
var player: Player
var entity: Entity
var hud: Hud
var coop: Coop
var playing := false

var _flicker := 1.0
var _flicker_timer := 3.0
var _flicker_seq: Array[float] = []
var _soft_wall_warned := false
var _ending := false


func _ready() -> void:
	level = Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	entity = Entity.new()
	add_child(entity)
	entity.setup(level)
	entity.caught.connect(_on_entity_caught)
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
			entity.despawn()
			playing = false
			hud.close_all_panels()
			hud.toast("방장이 나갔다. 노란 방이 흐려진다...", 5.0)
			_show_title())
	player.teleport(level.cell_center(level.START), 0.0)
	_show_title()
	if G.autoplay:
		var bot := Autoplay.new()
		bot.main = self
		add_child(bot)


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
		options.append(["이어하기", func(): _begin(true)])
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
	hud.show_menu("백룸", "LEVEL 0\n\n소리를 켜고 이어폰을 권장합니다", options)


# --- 같이 하기 ---

## 방을 만든다. code가 비어 있으면 무작위 4자리. 번호가 이미 쓰이면 다른 번호로 다시 시도한다.
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
	var shared: Dictionary = ev.get("flags", {})
	await _begin(false)
	for k in shared:
		G.flags[k] = true
	_apply_progress()
	G.save_game()


func _enter_coop(code: String) -> void:
	G.save_path = G.COOP_SAVE_PATH
	coop.begin()
	hud.room_label = "방 " + code


func _leave_coop() -> void:
	coop.end()
	hud.room_label = ""


## 네트워크 사건을 기다린다(시간 초과 시 빈 사전).
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


## 진행 상황이 생겼을 때의 화면/세계 반영. remote: 동료가 해낸 일.
func apply_flag_effect(k: String, remote: bool) -> void:
	match k:
		"flashlight":
			hud.show_flashlight_button = true
			if remote:
				hud.toast("동료가 손전등 꾸러미를 찾았다. 손전등 버튼이 생겼다.", 4.0)
		"note2":
			hud.show_digits = true
			if remote:
				hud.toast("동료가 출구에 대한 쪽지를 찾았다. 번호 칸이 생겼다.", 4.0)
			if not coop.is_client() and not entity.active:
				entity.spawn_far(player.global_position, player.camera)
		"door_open":
			level.open_door()
			if remote:
				hud.toast("멀리서 철컥, 하고 문 열리는 소리가 났다.", 4.0)
		"digit_ceiling", "digit_pillar", "digit_phone", "digit_dark":
			if remote:
				hud.toast("동료가 숫자를 찾았다.\n번호  " + " ".join(G.digits_found().split("")), 4.0)
		_:
			if remote and k.begins_with("note"):
				hud.toast("동료가 쪽지를 읽었다.", 2.5)


func _begin(resume: bool) -> void:
	hud.toast("...", 0.8)
	await Sfx.build()
	_ending = false
	_soft_wall_warned = false
	entity.despawn()
	level.set_anomaly_passable(false)
	if resume and G.load_game():
		_apply_progress()
		player.teleport(G.checkpoint, G.checkpoint_yaw)
		_start_play()
		return
	G.reset()
	G.checkpoint = level.cell_center(level.START)
	player.teleport(G.checkpoint, 0.0)
	player.flashlight_on = false
	hud.show_flashlight_button = false
	hud.show_digits = false
	hud.show_lines(G.INTRO, func(): _start_play(), true)


func _apply_progress() -> void:
	hud.show_flashlight_button = G.has("flashlight")
	player.flashlight_on = G.has("flashlight")
	hud.show_digits = G.has("note2")
	if G.has("door_open"):
		level.open_door(false)


func _start_play() -> void:
	playing = true
	G.save_game()
	if G.has("note2") and not G.has("escaped") and not coop.is_client():
		entity.spawn_far(player.global_position, player.camera)


# --- 매 프레임 ---

func _process(delta: float) -> void:
	player.frozen = hud.is_blocked() or not playing
	_update_flicker(delta)
	_update_shader()
	coop.tick(delta)
	# 같이 할 때는 방장의 창 때문에 세계가 멈추면 안 된다
	if coop.is_host() and not _ending:
		entity.tick(delta, player, coop.watchers())
	if not playing:
		_update_audio(INF)
		return
	if not coop.active and not hud.is_blocked():
		entity.tick(delta, player)
	var ent_dist := player.global_position.distance_to(entity.global_position) if entity.active else INF
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
	level.set_shared("entity_pos", entity.global_position if entity.active else Vector3(9999, 0, 9999))


func _update_flicker(delta: float) -> void:
	if not _flicker_seq.is_empty():
		_flicker = _flicker_seq.pop_front()
		return
	_flicker = 1.0
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(4.0, 11.0)
		flicker_burst(randi_range(6, 16))


## 형광등이 깜빡이는 연출. n 프레임 동안 밝기를 흔든다.
func flicker_burst(frames: int) -> void:
	for i in frames:
		_flicker_seq.append(randf_range(0.15, 1.0) if i % 3 != 0 else 1.0)


func _update_audio(ent_dist: float) -> void:
	if not Sfx.ready_built:
		return
	var near := clampf((ent_dist - 2.5) / 8.0, 0.0, 1.0)
	Sfx.set_loop("hum", HUM_VOLUME * near * (0.6 + 0.4 * _flicker) if playing else 0.0)
	Sfx.set_loop("drone", clampf(1.0 - (ent_dist - 2.0) / 14.0, 0.0, 1.0) * 0.9 if playing else 0.0)
	Sfx.set_loop("heartbeat", 0.8 if playing and ent_dist < 9.0 else 0.0)
	var ring := 0.0
	if playing and _phone_ringing():
		var d := player.global_position.distance_to(level.props["phone"].global_position)
		ring = clampf(1.0 - d / 30.0, 0.0, 1.0) * 0.8
	Sfx.set_loop("ring", ring)


func _phone_ringing() -> bool:
	return G.has("note2") and not G.has("digit_phone")


# --- 조사 ---

func _ray_target(screen_pos: Vector2) -> Node:
	var cam := player.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * INTERACT_DIST
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
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
	hud.prompt = "전화 받기" if id == "phone" and _phone_ringing() else PROMPTS.get(id, "")


func _on_tap(screen_pos: Vector2) -> void:
	if not playing or player.eyes_closed:
		return
	var t := _ray_target(screen_pos)
	if t == null:
		t = _ray_target(get_viewport().get_visible_rect().size * 0.5)
	if t:
		interact(t.get_meta("id"))


func interact(id: String) -> void:
	if id.begins_with("note"):
		_read_note(id)
	elif id == "pack":
		_open_pack()
	elif id == "phone":
		_use_phone()
	elif id == "door":
		_use_door()


func _read_note(id: String) -> void:
	var first := not G.has(id)
	hud.show_note(G.NOTES[id], func():
		if not first:
			return
		G.checkpoint = player.global_position
		G.checkpoint_yaw = player.yaw
		G.set_flag(id)
		if id == "note2":
			hud.toast("어디선가 전화벨이 울린다.\n...그리고 아주 잠깐, 형광등 소리가 끊겼다.", 5.0)
			flicker_burst(30)
			apply_flag_effect("note2", false)
		elif id == "note6":
			hud.toast("어긋난 벽... 처음 떨어진 곳 근처였다.", 5.0))


func _open_pack() -> void:
	if G.has("flashlight"):
		hud.toast("텅 빈 배낭이다. 지수의 이름표가 달려 있다.")
		return
	G.set_flag("flashlight")
	apply_flag_effect("flashlight", false)
	player.flashlight_on = true
	Sfx.play("click", -6.0)
	hud.show_lines(["배낭 안에 손전등이 있다. 아직 켜진다.", "그 밑에 접힌 쪽지 한 장."], func(): _read_note("note3"))


func _use_phone() -> void:
	if not _phone_ringing():
		hud.toast("수화기 너머엔 아무 소리도 없다.")
		return
	Sfx.set_loop("ring", 0.0)
	Sfx.play("static", -8.0)
	G.set_flag("digit_phone")
	hud.show_lines(G.PHONE_LINES, func(): hud.toast("목소리가 말한 숫자: 5"))


func _use_door() -> void:
	if G.has("door_open"):
		hud.toast("문은 열려 있다. 안쪽이 이상하게 어둡다.")
		return
	hud.show_keypad(func(code: String) -> bool:
		if code == G.EXIT_CODE:
			Sfx.play("unlock")
			G.set_flag("door_open")
			apply_flag_effect("door_open", false)
			hud.toast("철컥. 빨간 문이 열린다.", 3.0)
			return true
		Sfx.play("buzz", -4.0)
		flicker_burst(40)
		return false)


func _toggle_flashlight() -> void:
	if not G.has("flashlight") or not playing:
		return
	player.flashlight_on = not player.flashlight_on
	Sfx.play("click", -8.0)


# --- 숫자 발견 (시선) ---

func _update_digit_labels() -> void:
	var cam := player.camera
	for key in level.digit_labels:
		var label: Label3D = level.digit_labels[key]
		var d := cam.global_position.distance_to(label.global_position)
		var a := 1.0 - smoothstep(6.0, 18.0, d)
		if key == "digit_dark":
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
		var label: Label3D = level.digit_labels[key]
		var to := label.global_position - cam.global_position
		if to.length() > GAZE_DIST or to.normalized().dot(player.look_dir()) < GAZE_DOT:
			continue
		if key == "digit_dark" and label.modulate.a < 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, label.global_position - to.normalized() * 0.05)
		q.exclude = [player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		G.set_flag(key)
		if key == "digit_dark":
			Sfx.play("sting", -10.0, 0.6)
		else:
			Sfx.play("paper", -10.0)
		hud.toast(DIGIT_TEXT[key], 4.5)


# --- 어긋난 벽 / 엔딩 ---

func _check_anomaly() -> void:
	var passable: bool = player.eyes_closed and G.has("note6")
	level.set_anomaly_passable(passable)
	var center: Vector3 = level.cell_center(level.ANOMALY)
	var flat := Vector2(player.global_position.x - center.x, player.global_position.z - center.z)
	if passable and absf(flat.x) < level.CELL * 0.4 and absf(flat.y) < level.CELL * 0.4:
		_escape()
	elif player.eyes_closed and not G.has("note6") and not _soft_wall_warned \
			and absf(flat.x) < level.CELL * 0.62 and absf(flat.y) < level.CELL * 0.62:
		_soft_wall_warned = true
		hud.toast("손끝에 닿은 벽이 물렁하다.\n...하지만 아직 발이 떨어지지 않는다.", 4.0)


func _escape() -> void:
	if _ending:
		return
	_ending = true
	playing = false
	entity.despawn()
	G.set_flag("escaped")
	coop.announce_escape()
	Sfx.stop_all()
	Sfx.play("whoosh")
	hud.show_lines(G.ENDING, func():
		hud.show_menu("탈출", "LEVEL 0을 벗어났다.\n...아니면, 처음으로 돌아왔다.", [["처음으로", func():
			_leave_coop()
			G.reset()
			_show_title()]]), true)


func _on_entity_caught(id: String) -> void:
	if id == "":
		on_caught_local()
		return
	# 동료가 잡혔다(방장만 여기로 온다): 알리고 '그것'은 멀리 보낸다
	coop.send_caught(id)
	var victim: Vector3 = coop.remotes[id].pos if coop.remotes.has(id) else player.global_position
	entity.spawn_far(victim, player.camera)
	hud.toast("어디선가 비명이 들렸다.", 3.0)


func on_caught_local() -> void:
	if not playing:
		return
	playing = false
	hud.scare()
	await get_tree().create_timer(1.0).timeout
	hud.show_lines(G.CAUGHT_LINES, func():
		player.teleport(G.checkpoint, G.checkpoint_yaw)
		player.eyes_closed = false
		playing = true
		if not coop.active:
			entity.spawn_far(player.global_position, player.camera)
		elif coop.is_host():
			entity.spawn_far(player.global_position, player.camera), true)


func _open_menu() -> void:
	if not playing or hud.is_blocked():
		return
	var sub := "찾은 번호  " + " ".join(G.digits_found().split(""))
	var options: Array = [["계속하기", func(): pass]]
	if coop.active:
		sub += "\n\n방 %s  |  %d명" % [Net.room, coop.player_count()]
		options.append(["초대 링크 보내기", func():
			var r := Net.share_invite()
			hud.toast("초대 링크를 복사했다.\n" + Net.invite_url() if r == "copied" else "방 번호 " + Net.room, 5.0)])
		options.append(["방 나가기", func():
			_leave_coop()
			entity.despawn()
			playing = false
			_show_title()])
	else:
		options.append(["처음부터", func():
			G.reset()
			entity.despawn()
			playing = false
			_begin(false)])
	hud.show_menu("일시정지", sub, options, false)
