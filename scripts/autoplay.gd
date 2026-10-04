extends Node
## 오토플레이 테스트. 데스크톱: `godot --path . -- --autoplay --shots=<dir> [--from=N]` / 웹: `index.html?autoplay`
## 실제 터치 입력(조이스틱/시점 드래그/탭/화면 버튼)으로 모든 레벨을 레이아웃의 정답 순서대로 공략하고,
## 레벨 0에서는 '그것'의 규칙, 손전등, 번호판 오답도 검사한다. 같이 하기 모드(coophost/coopjoin)도 있다.

const Levels := preload("res://scripts/levels.gd")
const SHOT_TIMEOUT_SEC := 15.0
const NAV_TIME_SCALE := 6.0
const WAYPOINT_TIMEOUT_SEC := 8.0

var main: Node3D
var passed := 0
var failed := 0
var shots_dir := ""
var _web := OS.has_feature("web")
var _log_file: FileAccess
var _joy_down := false
var _caught_ids: Array = []


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
	_log("START web=%s viewport=%s hud=%s levels=%d" % [_web, _vp(), main.hud.size, Levels.count()])
	var mode := _url_param("autoplay")
	if mode == "coophost":
		await _run_coop_host(_url_param("aproom"))
		_finish()
		return
	if mode == "coopjoin":
		await _run_coop_join()
		_finish()
		return

	_check_glyphs()
	_check_levels()
	var from := int(_arg("from", _url_param("from") if _web else "0"))
	await _shot("00_title")
	await _click_named("Opt_혼자 하기")
	await _wait_until(func(): return Sfx.ready_built, 30.0)
	await _handle_ui("01_intro")
	_check(main.playing, "인트로 후 플레이 시작")
	main.freeze_entities = true
	await _test_look_drag()
	if from > 0:
		G.set_flag("flashlight")
		main.apply_flag_effect("flashlight", false)
		main.player.flashlight_on = true
		main.go_level(from, false)
		await _handle_ui("")
	for lv in range(from, Levels.count()):
		await _solve_level(lv)
		if main._ending:
			break
	_check(main._ending, "마지막 층에서 탈출 엔딩")
	await _handle_ui("99_ending")
	await _shot("99_end_menu")
	_finish()


# --- 레벨 공략 ---

func _solve_level(lv: int) -> void:
	_check(G.level == lv and main.layout.index == lv, "레벨 %d 시작 (%s %s)" % [lv, main.layout.name, main.layout.title])
	await _seconds(0.3)
	await _shot("L%02d_a_start" % lv)
	var steps: Array = main.layout.solution
	for i in steps.size():
		var st: Dictionary = steps[i]
		if lv == 0:
			await _level0_extra_before(st)
		match st.do:
			"interact":
				await _do_interact(st.id)
			"gaze":
				await _do_gaze(st.key)
			"keypad":
				await _do_keypad(st.id, st.code)
			"noclip":
				await _do_noclip()
		if lv == 0:
			await _level0_extra_after(st)
		if G.level != lv or main._ending:
			break
		if i == steps.size() / 2:
			await _shot("L%02d_b_mid" % lv)
	if not main._ending:
		await _wait_until(func(): return G.level == lv + 1, 6.0)
		_check(G.level == lv + 1, "레벨 %d 탈출 -> 레벨 %d" % [lv, lv + 1])
		await _handle_ui("L%02d_c_card" % (lv + 1))


func _prop(id: String) -> Dictionary:
	return main.level.props.get(id, {})


func _do_interact(id: String) -> void:
	var p := _prop(id)
	if p.is_empty():
		_check(false, "물체 없음: " + id)
		return
	await _go_cell(p.cell)
	await _ensure_flashlight()
	await _look_at(p.target)
	await _tap_center()
	await _frames(4)
	var opened: bool = main.hud.is_blocked() or G.has(id) or G.level != main.layout.index
	_check(opened, "%s 조사" % id)
	await _handle_ui("")


func _do_gaze(key: String) -> void:
	var d: Dictionary = {}
	for dd in main.layout.digits:
		if dd.key == key:
			d = dd
	await _go_cell(d.view)
	await _ensure_flashlight()
	await _look_at(main.level.digit_labels[key].label.global_position)
	await _seconds(0.3)
	_check(G.has(key), "숫자 발견 %s (%s, %s)" % [key, d.kind, d.value])
	await _handle_ui("")


func _do_keypad(id: String, code: String) -> void:
	var p := _prop(id)
	await _go_cell(p.cell)
	await _look_at(p.target)
	await _tap_center()
	await _wait_until(func(): return _top_name() == "KeypadPanel", 4.0)
	if main.layout.index == 0:
		await _shot("L00_keypad")
		await _type_code("1234")
		_check(not G.has("door_open"), "틀린 번호로는 안 열림")
	await _type_code(code)
	await _seconds(1.8)
	_check(G.has("door_open") or G.has("exit_open"), "%s 번호 %s 입력 -> 열림" % [id, code])


func _do_noclip() -> void:
	var front: Vector2i = main.level.anomaly_front
	await _go_cell(front)
	await _look_at(main.level.cell_center(main.level.anomaly, 1.5))
	await _shot("L%02d_noclip_wall" % G.level)
	var r: Rect2 = main.hud.buttons()["eyes"]
	_touch(5, r.get_center(), true)
	await _frames(3)
	_check(main.player.eyes_closed, "눈 감기 버튼")
	var lv: int = G.level
	_joystick(Vector2(0, -1))
	var t := 0.0
	while t < 4.0 and G.level == lv and not main._ending:
		await get_tree().process_frame
		t += get_process_delta_time()
	_joystick_release()
	_touch(5, r.get_center(), false)
	await _frames(3)
	_check(G.level != lv or main._ending, "어긋난 벽에 눈 감고 들어가기")


## 창(쪽지/대사/번호판)이 열려 있으면 닫거나 넘긴다.
func _handle_ui(shot_name: String) -> void:
	var guard := 0
	var shot_taken := false
	await _frames(3)
	while main.hud.is_blocked() and guard < 300:
		guard += 1
		var top := _top_name()
		if shot_name != "" and not shot_taken:
			await _frames(25)
			await _shot(shot_name)
			shot_taken = true
		if top == "NotePanel":
			await _frames(10)
			await _click_named("Close")
		elif top == "LinesPanel":
			await _frames(8)
			_mouse_click(_vp() * 0.5)
			await _frames(2)
		elif top == "KeypadPanel":
			await _click_named("Close")
		elif top == "MenuPanel":
			break
		else:
			await _frames(5)
	await _frames(3)


func _level0_extra_before(st: Dictionary) -> void:
	if st.do == "gaze" and st.key == "digit_dark":
		await _tap_button("flashlight")
		_check(not main.player.flashlight_on, "손전등 버튼으로 끄기")
		await _go_cell(Vector2i(9, 12))
		await _look_at(main.level.digit_labels["digit_dark"].label.global_position)
		await _seconds(0.3)
		_check(not G.has("digit_dark"), "손전등 없이 어둠 속 숫자는 안 보임")
		await _shot("L00_dark_no_light")
		await _tap_button("flashlight")


func _level0_extra_after(st: Dictionary) -> void:
	if st.do == "interact" and st.id == "note2":
		_check(main.entity.active, "쪽지2 이후 그것 등장")
		_check(main.hud.show_digits, "쪽지2 이후 번호 표시")
	if st.do == "interact" and st.id == "pack":
		_check(G.has("flashlight") and main.player.flashlight_on, "배낭에서 손전등 획득")
	if st.do == "interact" and st.id == "note4":
		_check(G.digits_found() == "7359", "번호 네 자리 모두 찾음 (%s)" % G.digits_found())
		await _test_entity()


func _ensure_flashlight() -> void:
	if G.has("flashlight") and not main.player.flashlight_on and main.hud.buttons().has("flashlight"):
		await _tap_button("flashlight")


func _type_code(code: String) -> void:
	for ch in code:
		await _click_named("Key_" + ch)
	await _click_named("Key_확인")
	await _frames(10)


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
	main.freeze_entities = false
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
	var away: Vector3 = p - (lvl.cell_center(spot) - p)
	await _look_at(Vector3(away.x, 1.6, away.z))
	var d0: float = p.distance_to(main.entity.global_position)
	await _seconds(1.5)
	var d1: float = main.player.global_position.distance_to(main.entity.global_position)
	_check(d1 < d0 - 0.5, "안 보고 있으면 그것이 다가온다 (%.1f -> %.1f)" % [d0, d1])
	var t := 0.0
	while not main.entity.seen and t < 6.0:
		await _look_at(main.entity.global_position + Vector3(0, 2.0, 0))
		t += 0.1
	var e0: Vector3 = main.entity.global_position
	await _seconds(1.5)
	var moved: float = main.entity.global_position.distance_to(e0)
	_check(main.entity.seen and moved < 0.05, "보고 있으면 그것이 멈춘다 (이동 %.2fm)" % moved)
	await _shot("L00_entity_seen")
	var checkpoint: Vector3 = G.checkpoint
	await _look_at(Vector3(away.x, 1.6, away.z))
	await _wait_until(func(): return not main.playing, 15.0)
	_check(not main.playing, "등 돌리고 있으면 잡힌다")
	await _frames(20)
	await _shot("L00_caught_scare")
	await _wait_until(func(): return _top_name() == "LinesPanel", 4.0)
	await _handle_ui("")
	await _frames(5)
	_check(main.playing and main.player.global_position.distance_to(checkpoint) < 0.6, "잡히면 마지막 쪽지 위치에서 다시 시작")
	main.freeze_entities = true


# --- 같이 하기 ---

func _run_coop_host(code: String) -> void:
	main.hud.close_all_panels()
	main._host_room(code)
	await _wait_until(func(): return main.coop.is_host(), 30.0)
	_check(main.coop.is_host() and Net.room == code, "방 만들기 (방 %s)" % code)
	_log("HOSTING " + code)
	await _handle_ui("h1_intro")
	main.entity.caught.connect(func(id: String): _caught_ids.append(id))
	await _wait_until(func(): return main.coop.remotes.size() >= 1, 90.0)
	_check(main.coop.remotes.size() >= 1, "동료 접속")
	await _seconds(4.0)
	var friend: Vector3 = main.coop.remotes.values()[0].pos
	_check(friend.distance_to(main.level.cell_center(main.level.start)) > 1.5, "동료가 움직인 위치가 보인다 (%s)" % friend)
	await _look_at(friend + Vector3(0, 1.5, 0))
	await _seconds(0.5)
	await _shot("h2_host_sees_friend")
	await _do_interact("note1")

	var lvl = main.level
	var fc: Vector2i = lvl.cell_at(main.coop.remotes.values()[0].pos)
	var spot := Vector2i(-1, -1)
	for c in lvl.open_cells():
		if lvl.tile(c) in ["o", "O"]:
			continue
		if lvl.path(fc, c).size() == 3:
			spot = c
			break
	main.entity.place(lvl.cell_center(spot))
	var away: Vector3 = main.player.global_position * 2.0 - lvl.cell_center(spot)
	await _look_at(Vector3(away.x, 1.6, away.z))
	_log("ENTITY placed %s (friend %s)" % [spot, fc])
	await _wait_until(func(): return _remote_sees(), 30.0)
	_check(_remote_sees(), "동료가 그것을 보고 있다는 신호 수신")
	var e0: Vector3 = main.entity.global_position
	await _seconds(2.0)
	var moved: float = main.entity.global_position.distance_to(e0)
	var host_sees: bool = main.entity._visible_from(main.player.camera, false)
	_check(not host_sees and moved < 0.05, "나는 등을 돌려도 동료가 보고 있으면 멈춘다 (내 시야=%s, 이동 %.2fm)" % [host_sees, moved])
	await _shot("h3_entity_frozen_by_friend")
	await _wait_until(func(): return not _caught_ids.is_empty(), 40.0)
	_check(not _caught_ids.is_empty() and _caught_ids[0] != "", "동료가 눈을 돌리자 그것이 동료를 잡았다")
	# 다음 레벨로 같이 넘어가는지: 방장이 레벨 1로 보낸다
	await _seconds(4.0)
	main.go_level(1, true)
	await _handle_ui("h4_level1_card")
	_check(G.level == 1, "방장 레벨 1 이동")
	await _seconds(8.0)


func _remote_sees() -> bool:
	for r in main.coop.remotes.values():
		for s in r.sees:
			if s:
				return true
	return false


func _run_coop_join() -> void:
	var code := _url_param("room")
	await _click_named("Opt_방 %s 참가하기" % code)
	await _wait_until(func(): return main.coop.is_client(), 60.0)
	_check(main.coop.is_client(), "초대 링크로 방 %s 참가" % code)
	await _handle_ui("j1_intro")
	_check(main.playing, "참가 후 플레이 시작")
	main.freeze_entities = false
	await _go_cell(Vector2i(1, 15))
	await _wait_until(func(): return main.coop.remotes.size() >= 1, 20.0)
	_check(main.coop.remotes.size() >= 1, "방장 아바타 수신")
	if main.coop.remotes.size() >= 1:
		await _look_at(main.coop.remotes.values()[0].pos + Vector3(0, 1.5, 0))
	await _seconds(0.5)
	await _shot("j2_client_sees_host")
	await _wait_until(func(): return G.has("note1"), 60.0)
	_check(G.has("note1"), "방장이 읽은 쪽지가 공유됨")
	await _wait_until(func(): return main.entity.active, 60.0)
	_check(main.entity.active, "방장이 움직이는 그것이 보인다")
	var t := 0.0
	while t < 8.0:
		await _look_at(main.entity.global_position + Vector3(0, 1.8, 0))
		await _seconds(0.2)
		t += 0.3
		if t > 2.0 and t < 2.4:
			await _shot("j3_client_watching")
	var away: Vector3 = main.player.global_position * 2.0 - main.entity.global_position
	await _look_at(Vector3(away.x, 1.6, away.z))
	await _wait_until(func(): return not main.playing, 40.0)
	_check(not main.playing, "눈을 돌리자 잡힘 (참가자 화면)")
	await _seconds(0.3)
	await _shot("j4_caught")
	await _handle_ui("")
	await _seconds(0.5)
	_check(main.playing, "참가자도 체크포인트에서 다시 시작")
	await _wait_until(func(): return G.level == 1, 30.0)
	_check(G.level == 1, "방장을 따라 레벨 1로 이동")
	await _handle_ui("j5_level1_card")
	await _seconds(2.0)
	await _shot("j6_level1")


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
			if main.hud.is_blocked():
				_joystick_release()
				Engine.time_scale = 1.0
				await _handle_ui("")
				Engine.time_scale = NAV_TIME_SCALE
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
	if lvl.cell_at(main.player.global_position) != target:
		_check(false, "칸 %s 도착 실패 (현재 %s)" % [target, lvl.cell_at(main.player.global_position)])


func _look_at(target: Vector3) -> void:
	main.player.face_towards(target)
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


func _top_name() -> String:
	var top: Control = main.hud.top_panel()
	return top.name if top else ""


# --- 정적 검사 ---

func _check_glyphs() -> void:
	var font: Font = load("res://fonts/GowunBatang-Subset.ttf")
	var texts: Array = G.all_text()
	for i in Levels.count():
		var lay: Dictionary = Levels.make(i)
		texts.append(lay.name)
		texts.append(lay.title)
		texts.append_array(lay.intro)
		for h in lay.hints:
			texts.append(h[1])
		for p in lay.props:
			if p.data.has("text"):
				texts.append(p.data.text)
			if p.data.has("lines"):
				texts.append_array(p.data.lines)
	# 스크립트 소스의 모든 문자열 리터럴도 검사(데스크톱에서 소스를 읽을 수 있을 때)
	var lit := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string("res://scripts/" + f)
			for m in lit.search_all(src):
				texts.append(m.get_string().replace("\\n", "\n"))
	var missing := {}
	for t in texts:
		for ch in str(t):
			if ch in ["\n", " ", "\t", "\r"]:
				continue
			if not font.has_char(ch.unicode_at(0)):
				missing[ch] = true
	_check(missing.is_empty(), "글꼴에 없는 글자 없음 %s" % ("" if missing.is_empty() else str(missing.keys())))


## 모든 레벨: 정답 순서에 나오는 칸이 시작점에서 걸어서 닿는지, 같은 시드면 같은 맵인지.
func _check_levels() -> void:
	for i in Levels.count():
		var lay: Dictionary = Levels.make(i)
		var g: Array = lay.map
		var reach := _reach(g, lay.start)
		var bad: Array = []
		for p in lay.props:
			if p.cell != lay.get("secret_room", Vector2i(-1, -1)) and not reach.has(p.cell):
				bad.append(p.id)
		for d in lay.digits:
			if not reach.has(d.view):
				bad.append(d.key)
		if lay.exit.kind == "noclip" and not reach.has(lay.anomaly_front):
			bad.append("anomaly")
		var again: Dictionary = Levels.make(i)
		_check(bad.is_empty() and str(again.map) == str(lay.map), "레벨 %d %s: 모든 단서에 길 있음, 같은 시드 같은 맵 %s" % [i, lay.title, bad])


func _reach(g: Array, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n.x < 0 or n.y >= g.size() or n.x >= g[0].length():
				continue
			if g[n.y][n.x] in [".", ",", "o", "O"] and not seen.has(n):
				seen[n] = true
				q.append(n)
	return seen


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


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.trim_prefix("--%s=" % key)
	return default


func _url_param(key: String) -> String:
	if not _web:
		return ""
	var q := str(JavaScriptBridge.eval("location.search"))
	var re := RegEx.create_from_string(key + "=([A-Za-z0-9]+)")
	var m := re.search(q)
	return m.get_string(1) if m else ""


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
