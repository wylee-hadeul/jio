extends Node
## 오토플레이 테스트. 데스크톱: `godot --path . -- --autoplay --shots=<dir>` / 웹: `index.html?autoplay`
## 실제 터치 입력(조이스틱 드래그, 시점 드래그, 화면 탭, 화면 버튼)으로 처음부터 엔딩까지 공략하고,
## 그것(엔티티)의 '보면 멈춤/안 보면 다가옴/잡힘' 동작과 글꼴 누락을 검사한다.

const SHOT_TIMEOUT_SEC := 15.0
const NAV_TIME_SCALE := 4.0
const WAYPOINT_TIMEOUT_SEC := 8.0

var main: Node3D
var passed := 0
var failed := 0
var shots_dir := ""
var _web := OS.has_feature("web")
var _log_file: FileAccess
var _joy_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _web:
		JavaScriptBridge.eval("window.__ap = {logs: [], pending: null, done: false}")
	else:
		shots_dir = ProjectSettings.globalize_path("res://build/test/desktop")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--shots="):
				shots_dir = arg.trim_prefix("--shots=")
		DirAccess.make_dir_recursive_absolute(shots_dir)
		_log_file = FileAccess.open(shots_dir.path_join("autoplay.log"), FileAccess.WRITE)
	_run()


func _run() -> void:
	await _frames(10)
	_log("START web=%s viewport=%s hud=%s" % [_web, _vp(), main.hud.size])
	_check_glyphs()
	_check_map()

	await _shot("00_title")
	await _click_named("Opt_들어가기")
	await _wait_until(func(): return Sfx.ready_built, 30.0)
	await _skip_lines("01_intro")
	_check(main.playing, "인트로 후 플레이 시작")

	await _test_look_drag()
	await _go_read("note1", "02_note1")
	await _look_at(main.level.cell_center(main.level.ANOMALY, 1.5))
	await _shot("03_anomaly_wall")
	await _go_read("note2", "04_note2")
	_check(main.entity.active, "쪽지2 이후 그것 등장")
	_check(main.hud.show_digits, "쪽지2 이후 번호 표시")
	main.entity.despawn()

	await _go_cell(Vector2i(1, 1))
	await _interact("pack")
	await _skip_lines("")
	await _close_note("05_note3")
	_check(G.has("flashlight") and main.player.flashlight_on, "배낭에서 손전등 획득, 켜짐")

	await _go_cell(Vector2i(9, 2))
	await _look_at(main.level.digit_labels["digit_ceiling"].global_position)
	await _seconds(0.3)
	_check(G.has("digit_ceiling"), "천장을 올려다보면 숫자 7 발견")
	await _shot("06_ceiling_7")

	await _go_cell(Vector2i(15, 7))
	await _look_at(main.level.digit_labels["digit_pillar"].global_position)
	await _seconds(0.3)
	_check(G.has("digit_pillar"), "기둥 뒤에서 숫자 3 발견")
	await _shot("07_pillar_3")

	await _go_cell(Vector2i(15, 12))
	_check(main._phone_ringing(), "전화벨이 울리는 중")
	await _interact("phone")
	await _skip_lines("08_phone")
	_check(G.has("digit_phone"), "전화를 받아 숫자 5 획득")

	await _tap_button("flashlight")
	_check(not main.player.flashlight_on, "손전등 버튼으로 끄기")
	await _go_cell(Vector2i(9, 12))
	await _look_at(main.level.digit_labels["digit_dark"].global_position)
	await _seconds(0.3)
	_check(not G.has("digit_dark"), "손전등 없이 어둠 속 숫자는 안 보임")
	await _shot("09_dark_no_light")
	await _tap_button("flashlight")
	await _seconds(0.3)
	_check(G.has("digit_dark"), "손전등을 비추면 숫자 9 발견")
	await _shot("10_dark_9")

	await _go_read("note5", "11_note5")
	await _go_read("note4", "12_note4")
	_check(G.digits_found() == "7359", "번호 네 자리 모두 찾음 (%s)" % G.digits_found())

	await _test_entity()

	await _go_cell(main.level.DOOR_FRONT)
	await _interact("door")
	await _shot("13_keypad")
	await _type_code("1234")
	_check(not G.has("door_open"), "틀린 번호로는 안 열림")
	await _type_code("7359")
	await _seconds(1.8)
	_check(G.has("door_open"), "7359 입력하면 빨간 문 열림")
	await _shot("14_door_open")
	await _go_read("note6", "15_note6")

	await _go_cell(Vector2i(4, 14))
	await _look_at(main.level.cell_center(main.level.ANOMALY, 1.5))
	await _hold_eyes_and_walk(3.0)
	_check(G.has("escaped"), "어긋난 벽에 눈 감고 걸어 들어가면 탈출")
	await _skip_lines("16_ending")
	await _shot("17_end_menu")
	_finish()


# --- 시나리오 조각 ---

func _go_read(note_id: String, shot_name: String) -> void:
	await _go_cell(main.level.PROPS[note_id][0])
	await _interact(note_id)
	await _close_note(shot_name)
	_check(G.has(note_id), "%s 읽음" % note_id)


func _interact(id: String) -> void:
	var body: Node3D = main.level.props.get(id, null)
	var target: Vector3
	if id == "door":
		target = main.level.door_body.global_position + Vector3(0.6, 1.1, 0.0)
	else:
		target = body.global_position + _prop_offset(id)
	await _look_at(target)
	await _tap_center()
	await _frames(6)
	_check(main.hud.is_blocked(), "%s 조사 -> 창 열림" % id)


func _prop_offset(id: String) -> Vector3:
	if id.begins_with("note"):
		return Vector3(0.35, 0.05, 0.4)
	if id == "pack":
		return Vector3(-0.5, 0.2, -0.5)
	if id == "phone":
		return Vector3(0.6, 0.8, 0.6)
	return Vector3.ZERO


func _close_note(shot_name: String) -> void:
	await _wait_until(func(): return main.hud.top_panel() != null and main.hud.top_panel().name == "NotePanel", 5.0)
	await _frames(20)
	if shot_name != "":
		await _shot(shot_name)
	await _click_named("Close")
	await _frames(4)


func _skip_lines(shot_name: String) -> void:
	await _wait_until(func(): return main.hud.top_panel() != null and main.hud.top_panel().name == "LinesPanel", 8.0)
	var shot_taken := false
	var guard := 0
	var panel: Control = main.hud.top_panel()
	while is_instance_valid(panel) and panel == main.hud.top_panel() and guard < 200:
		await _frames(12)
		if not shot_taken and shot_name != "":
			shot_taken = true
			await _shot(shot_name)
		_mouse_click(_vp() * 0.5)
		guard += 1
	_check(guard < 200, "대사창 넘기기 (%s)" % shot_name)


func _type_code(code: String) -> void:
	for ch in code:
		await _click_named("Key_" + ch)
	await _click_named("Key_확인")
	await _frames(10)
	if main.hud.top_panel() != null and main.hud.top_panel().name == "KeypadPanel" and code == G.EXIT_CODE:
		_log("WARN keypad still open after correct code")


func _test_look_drag() -> void:
	var before: float = main.player.yaw
	var start := Vector2(_vp().x * 0.75, _vp().y * 0.5)
	_touch(3, start, true)
	await _frames(1)
	for k in 6:
		_drag(3, start + Vector2(-20.0 * (k + 1), 0))
		await _frames(1)
	_touch(3, start + Vector2(-120, 0), false)
	await _frames(2)
	_check(main.player.yaw > before + 0.2, "오른쪽 화면 드래그로 시점 회전")


## 그것: 안 보면 다가오고, 보면 멈추고, 닿으면 잡혀서 체크포인트로 돌아간다.
func _test_entity() -> void:
	var p: Vector3 = main.player.global_position
	var lvl = main.level
	var pc: Vector2i = lvl.cell_at(p)
	var spot := Vector2i(-1, -1)
	for c in lvl.open_cells():
		var steps: int = lvl.path(pc, c).size()
		if steps >= 4 and steps <= 6:
			spot = c
			break
	main.entity.place(lvl.cell_center(spot))
	# 등을 돌린다
	var away: Vector3 = p - (lvl.cell_center(spot) - p)
	await _look_at(Vector3(away.x, 1.6, away.z))
	var d0: float = p.distance_to(main.entity.global_position)
	await _seconds(1.5)
	var d1: float = main.player.global_position.distance_to(main.entity.global_position)
	_check(d1 < d0 - 0.5, "안 보고 있으면 그것이 다가온다 (%.1f -> %.1f)" % [d0, d1])
	# 벽 뒤에 가려 있으면 계속 다가오므로, 실제로 보이기 시작한 순간부터 잰다
	var t := 0.0
	while not main.entity.seen and t < 6.0:
		await _look_at(main.entity.global_position + Vector3(0, 2.0, 0))
		t += 0.1
	var e0: Vector3 = main.entity.global_position
	await _seconds(1.5)
	var moved: float = main.entity.global_position.distance_to(e0)
	_check(main.entity.seen and moved < 0.05, "보고 있으면 그것이 멈춘다 (seen=%s, 이동 %.2fm)" % [main.entity.seen, moved])
	await _shot("t1_entity_seen")
	var checkpoint: Vector3 = G.checkpoint
	await _look_at(Vector3(away.x, 1.6, away.z))
	await _wait_until(func(): return not main.playing, 15.0)
	_check(not main.playing, "등 돌리고 있으면 잡힌다")
	await _frames(20)
	await _shot("t2_caught_scare")
	await _skip_lines("t3_caught_text")
	await _frames(5)
	_check(main.playing and main.player.global_position.distance_to(checkpoint) < 0.6, "잡히면 마지막 쪽지 위치에서 다시 시작")
	var steps: int = lvl.path(lvl.cell_at(main.player.global_position), lvl.cell_at(main.entity.global_position)).size()
	_check(main.entity.active and steps >= main.entity.SPAWN_MIN_STEPS, "그것은 멀리서 다시 나타난다 (%d칸)" % steps)
	main.entity.despawn()


func _hold_eyes_and_walk(sec: float) -> void:
	var r: Rect2 = main.hud.buttons()["eyes"]
	_touch(5, r.get_center(), true)
	await _frames(3)
	_check(main.player.eyes_closed, "눈 감기 버튼을 누르는 동안 눈 감음")
	await _shot("t4_eyes_closed")
	_joystick(Vector2(0, -1))
	var t := 0.0
	while t < sec and not G.has("escaped"):
		await get_tree().process_frame
		t += get_process_delta_time()
	_joystick_release()
	_touch(5, r.get_center(), false)
	await _frames(3)


# --- 이동 ---

func _go_cell(target: Vector2i) -> void:
	var lvl = main.level
	var route: Array[Vector2i] = lvl.path(lvl.cell_at(main.player.global_position), target)
	Engine.time_scale = NAV_TIME_SCALE
	var prev: Vector2i = lvl.cell_at(main.player.global_position)
	for i in route.size():
		var c: Vector2i = route[i]
		var next: Vector2i = route[i + 1] if i + 1 < route.size() else c
		var goal: Vector3 = lvl.waypoint(prev, c, next)
		prev = c
		var t := 0.0
		while true:
			var pos: Vector3 = main.player.global_position
			var flat := Vector2(goal.x - pos.x, goal.z - pos.z)
			if flat.length() < 0.45:
				break
			main.player.yaw = atan2(-flat.x, -flat.y)
			main.player.pitch = 0.0
			_joystick(Vector2(0, -1))
			await get_tree().physics_frame
			t += get_physics_process_delta_time() / NAV_TIME_SCALE
			if t > WAYPOINT_TIMEOUT_SEC:
				_check(false, "이동 막힘: %s -> %s" % [lvl.cell_at(pos), c])
				break
	_joystick_release()
	Engine.time_scale = 1.0
	await _frames(3)
	_check(lvl.cell_at(main.player.global_position) == target, "칸 %s 도착" % target)


func _look_at(target: Vector3) -> void:
	main.player.face_towards(target)
	# 회전은 플레이어의 물리 프레임에서 적용되므로 물리 프레임을 기다린다
	for i in 3:
		await get_tree().physics_frame
	await _frames(2)


func _joystick(dir: Vector2) -> void:
	var origin := Vector2(150, _vp().y - 260)
	if not _joy_down:
		_touch(0, origin, true)
		_joy_down = true
	_drag(0, origin + dir * 110.0)


func _joystick_release() -> void:
	if _joy_down:
		_touch(0, Vector2(150, _vp().y - 260), false)
		_joy_down = false


# --- 입력 주입 ---

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	get_viewport().push_input(e, true)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	get_viewport().push_input(e, true)


func _tap_center() -> void:
	var c := _vp() * 0.5
	_touch(1, c, true)
	await _frames(2)
	_touch(1, c, false)
	await _frames(2)


func _tap_button(id: String) -> void:
	if not main.hud.buttons().has(id):
		_check(false, "화면 버튼 없음: " + id)
		return
	var r: Rect2 = main.hud.buttons()[id]
	_touch(2, r.get_center(), true)
	await _frames(2)
	_touch(2, r.get_center(), false)
	await _frames(2)


func _mouse_click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = pos
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		get_viewport().push_input(e, true)


func _click_named(node_name: String) -> void:
	await _wait_until(func(): return _find_button(node_name) != null, 8.0)
	var b: Control = _find_button(node_name)
	if b == null:
		_check(false, "버튼 없음: " + node_name)
		return
	var pos := b.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	get_viewport().push_input(move, true)
	var down := InputEventMouseButton.new()
	down.position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_viewport().push_input(down, true)
	await _frames(1)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)
	await _frames(3)


func _find_button(node_name: String) -> Control:
	var top: Control = main.hud.top_panel()
	if top == null:
		return null
	return top.find_child(node_name, true, false)


# --- 정적 검사 ---

func _check_glyphs() -> void:
	var font: Font = load("res://fonts/GowunBatang-Subset.ttf")
	var texts: Array = G.all_text()
	texts.append_array(main.DIGIT_TEXT.values())
	texts.append_array(main.PROMPTS.values())
	texts.append_array(["백룸", "LEVEL 0", "들어가기", "이어하기", "처음부터", "일시정지", "계속하기", "탈출", "닫기",
		"돌아가기", "지움", "확인", "눈 감기", "손전등", "이동", "번호", "▶ 화면을 누르세요", "||", "?",
		"눈을 감고 있다.\n형광등 소리만 들린다.", "어디선가 전화벨이 울린다.\n...그리고 아주 잠깐, 형광등 소리가 끊겼다.",
		"텅 빈 배낭이다. 지수의 이름표가 달려 있다.", "수화기 너머엔 아무 소리도 없다.", "목소리가 말한 숫자: 5",
		"문은 열려 있다. 안쪽이 이상하게 어둡다.", "철컥. 빨간 문이 열린다.", "어긋난 벽... 처음 떨어진 곳 근처였다.",
		"손끝에 닿은 벽이 물렁하다.\n...하지만 아직 발이 떨어지지 않는다.", "LEVEL 0을 벗어났다.\n...아니면, 처음으로 돌아왔다.",
		"배낭 안에 손전등이 있다. 아직 켜진다.", "그 밑에 접힌 쪽지 한 장.", "찾은 번호", "소리를 켜고 이어폰을 권장합니다"])
	var missing := {}
	for t in texts:
		for ch in str(t):
			if ch in ["\n", " "]:
				continue
			if not font.has_char(ch.unicode_at(0)):
				missing[ch] = true
	_check(missing.is_empty(), "글꼴에 없는 글자 없음 %s" % ("" if missing.is_empty() else str(missing.keys())))


func _check_map() -> void:
	var lvl = main.level
	for id in lvl.PROPS:
		var c: Vector2i = lvl.PROPS[id][0]
		if c == lvl.SECRET_ROOM:
			continue
		_check(not lvl.path(lvl.START, c).is_empty(), "시작점에서 %s 까지 길 있음" % id)


# --- 기록 ---

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	if _web:
		JavaScriptBridge.eval("window.__ap.pending = '%s'" % shot_name)
		var waited := 0.0
		while JavaScriptBridge.eval("window.__ap.pending") != null and waited < SHOT_TIMEOUT_SEC:
			await get_tree().create_timer(0.1, true, false, true).timeout
			waited += 0.1
	else:
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	_log("SHOT " + shot_name)


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		_log("PASS " + label)
	else:
		failed += 1
		_log("FAIL " + label)


func _finish() -> void:
	_log("DONE pass=%d fail=%d" % [passed, failed])
	if _web:
		JavaScriptBridge.eval("window.__ap.done = true")
	else:
		_log_file.flush()
		get_tree().quit(1 if failed > 0 else 0)


func _log(msg: String) -> void:
	var line := "[AUTOPLAY] " + msg
	print(line)
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()
	if _web:
		JavaScriptBridge.eval("window.__ap.logs.push(%s)" % JSON.stringify(line))


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func _seconds(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
