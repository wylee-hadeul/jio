extends Control
## 터치 HUD. 왼쪽 조이스틱(이동), 오른쪽 드래그(시점)/탭(조사), 화면 버튼, 각종 창.
## 멀티터치를 직접 처리하므로 화면 버튼도 손가락 번호로 구분한다.

signal tapped(screen_pos: Vector2)
signal flashlight_pressed
signal eyes_changed(closed: bool)
signal hint_pressed
signal menu_pressed
signal ping_pressed

const JOY_RADIUS := 110.0
const TAP_MAX_MOVE := 16.0
const TAP_MAX_SEC := 0.35
const LOOK_SCALE := 1.0

const COLOR_PAPER := Color("e8e0c8")
const COLOR_INK := Color("2a2118")
const COLOR_PANEL := Color(0.05, 0.045, 0.03, 0.92)
const COLOR_TEXT := Color("efe6c8")
const COLOR_ACCENT := Color("d9c46a")

var player: CharacterBody3D
var show_flashlight_button := false
var show_digits := false
var prompt := ""
var danger := 0.0
## 같이 하기 중이면 "방 1234" 같은 글. 비어 있으면 혼자 하기.
var room_label := ""

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _look_start := Vector2.ZERO
var _look_last := Vector2.ZERO
var _look_time := 0.0
var _look_moved := false
var _eyes_index := -2
var _mouse_down := false
var _mouse_moved := false
var _mouse_start := Vector2.ZERO

var _screen_fx: ColorRect
var _overlay: Control
var _eyes_layer: ColorRect
var _panel_root: Control
var _panels: Array[Control] = []
var _scare: Control
var _scare_t := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_screen_fx = ColorRect.new()
	_screen_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/screen.gdshader")
	_screen_fx.material = sm
	add_child(_screen_fx)

	_eyes_layer = ColorRect.new()
	_eyes_layer.color = Color.BLACK
	_eyes_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_eyes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eyes_layer.visible = false
	var eyes_label := _label("눈을 감고 있다.\n형광등 소리만 들린다.", 30, Color(1, 1, 1, 0.25))
	eyes_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	eyes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyes_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	eyes_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_eyes_layer.add_child(eyes_label)
	add_child(_eyes_layer)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_panel_root = Control.new()
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_root)

	_scare = Control.new()
	_scare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scare.visible = false
	_scare.draw.connect(_draw_scare)
	add_child(_scare)


func _process(delta: float) -> void:
	var sm: ShaderMaterial = _screen_fx.material
	sm.set_shader_parameter("danger", danger)
	_eyes_layer.visible = player != null and player.eyes_closed
	if _scare_t >= 0.0:
		_scare_t += delta
		_scare.position = Vector2(randf_range(-18, 18), randf_range(-18, 18)) * (1.0 - _scare_t)
		_scare.queue_redraw()
		if _scare_t > 0.9:
			_scare_t = -1.0
			_scare.visible = false
			_scare.position = Vector2.ZERO
	_overlay.queue_redraw()


func is_blocked() -> bool:
	return not _panels.is_empty()


# --- 입력 ---

func _input(event: InputEvent) -> void:
	if is_blocked() or player == null:
		_release_all()
		return
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _button_at(event.position) != "":
				_press_button(_button_at(event.position), -3)
				return
			_mouse_down = true
			_mouse_moved = false
			_mouse_start = event.position
		else:
			if _eyes_index == -3:
				_set_eyes(-2, false)
			if _mouse_down and not _mouse_moved:
				tapped.emit(event.position)
			_mouse_down = false
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _mouse_down:
		if event.position.distance_to(_mouse_start) > TAP_MAX_MOVE:
			_mouse_moved = true
		player.look(event.relative * LOOK_SCALE)
	elif event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_F and event.pressed:
			flashlight_pressed.emit()
		elif event.physical_keycode == KEY_SPACE:
			_set_eyes(-4 if event.pressed else -2, event.pressed)
		elif event.physical_keycode == KEY_ESCAPE and event.pressed:
			menu_pressed.emit()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var b := _button_at(pos)
		if b != "":
			_press_button(b, index)
			return
		if pos.x < size.x * 0.45 and _joy_index == -1:
			_joy_index = index
			_joy_origin = pos
			_joy_pos = pos
		elif _look_index == -1:
			_look_index = index
			_look_start = pos
			_look_last = pos
			_look_time = Time.get_ticks_msec() / 1000.0
			_look_moved = false
	else:
		if index == _eyes_index:
			_set_eyes(-2, false)
		if index == _joy_index:
			_joy_index = -1
			player.move_input = Vector2.ZERO
		elif index == _look_index:
			var quick := Time.get_ticks_msec() / 1000.0 - _look_time < TAP_MAX_SEC
			if not _look_moved and quick:
				tapped.emit(pos)
			_look_index = -1


func _drag(index: int, pos: Vector2) -> void:
	if index == _joy_index:
		_joy_pos = pos
		var v := (pos - _joy_origin) / JOY_RADIUS
		v = v.limit_length(1.0)
		player.move_input = Vector2(v.x, -v.y)
	elif index == _look_index:
		if pos.distance_to(_look_start) > TAP_MAX_MOVE:
			_look_moved = true
		player.look((pos - _look_last) * LOOK_SCALE)
		_look_last = pos


func _release_all() -> void:
	_joy_index = -1
	_look_index = -1
	_mouse_down = false
	if player:
		player.move_input = Vector2.ZERO
		if player.eyes_closed:
			_set_eyes(-2, false)


func _set_eyes(index: int, closed: bool) -> void:
	_eyes_index = index if closed else -2
	if player and player.eyes_closed != closed:
		player.eyes_closed = closed
		eyes_changed.emit(closed)


## 화면 버튼 배치(뷰포트 좌표).
func buttons() -> Dictionary:
	var out := {
		"eyes": Rect2(size.x - 190, size.y - 210, 160, 160),
		"hint": Rect2(size.x - 190, 24, 76, 76),
		"menu": Rect2(size.x - 100, 24, 76, 76),
	}
	if show_flashlight_button:
		out["flashlight"] = Rect2(size.x - 190, size.y - 390, 160, 150)
	if room_label != "":
		out["ping"] = Rect2(size.x - 190, size.y - 560, 160, 150)
	return out


func _button_at(pos: Vector2) -> String:
	var bs := buttons()
	for k in bs:
		if bs[k].has_point(pos):
			return k
	return ""


func _press_button(id: String, index: int) -> void:
	match id:
		"eyes":
			_set_eyes(index, true)
		"flashlight":
			flashlight_pressed.emit()
		"hint":
			hint_pressed.emit()
		"menu":
			menu_pressed.emit()
		"ping":
			ping_pressed.emit()


# --- 그리기 ---

func _draw_overlay() -> void:
	if player == null or not visible:
		return
	var font := get_theme_default_font()
	var c := size * 0.5
	if not player.eyes_closed:
		_overlay.draw_circle(c, 3.0, Color(1, 1, 1, 0.55))
		if prompt != "":
			var w := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			_overlay.draw_string_outline(font, c + Vector2(-w / 2, 56), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color(0, 0, 0, 0.8))
			_overlay.draw_string(font, c + Vector2(-w / 2, 56), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLOR_ACCENT)
	if _joy_index != -1:
		_overlay.draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.08))
		_overlay.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 3)
		_overlay.draw_circle(_joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS), 42, Color(1, 1, 1, 0.3))
	elif not player.eyes_closed:
		var hint_pos := Vector2(120, size.y - 160)
		_overlay.draw_arc(hint_pos, 70, 0, TAU, 40, Color(1, 1, 1, 0.12), 3)
		_overlay.draw_string(font, hint_pos + Vector2(-34, 10), "이동", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.25))
	var bs := buttons()
	for k in bs:
		var r: Rect2 = bs[k]
		var active: bool = (k == "eyes" and player.eyes_closed) or (k == "flashlight" and player.flashlight_on)
		var center := r.get_center()
		var rad: float = min(r.size.x, r.size.y) * 0.5
		_overlay.draw_circle(center, rad, Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.35) if active else Color(0, 0, 0, 0.35))
		_overlay.draw_arc(center, rad, 0, TAU, 40, Color(1, 1, 1, 0.35), 2)
		var text: String = {"eyes": "눈 감기", "flashlight": "손전등", "hint": "?", "menu": "||", "ping": "부르기"}[k]
		var fs := 30 if k in ["hint", "menu"] else 26
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_overlay.draw_string(font, center + Vector2(-tw / 2, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))
	if room_label != "":
		var rw := font.get_string_size(room_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_overlay.draw_string(font, Vector2(size.x / 2 - rw / 2, 52), room_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
	if show_digits:
		var digits := "번호  " + " ".join(G.digits_found().split(""))
		_overlay.draw_string_outline(font, Vector2(28, 66), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.7))
		_overlay.draw_string(font, Vector2(28, 66), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, COLOR_TEXT)


func scare() -> void:
	_scare.visible = true
	_scare_t = 0.0
	Sfx.play("sting", 2.0)
	Input.vibrate_handheld(400)


func _draw_scare() -> void:
	var s := size
	var flash: float = clampf(1.0 - _scare_t * 8.0, 0.0, 1.0)
	_scare.draw_rect(Rect2(Vector2(-40, -40), s + Vector2(80, 80)), Color(0.0, 0.0, 0.0))
	var c := s * 0.5 + Vector2(0, -40)
	var k: float = s.x / 720.0 * (1.0 + _scare_t * 0.35)
	# 눈
	for side in [-1.0, 1.0]:
		var e := c + Vector2(150 * side, -150) * k
		_scare.draw_circle(e, 62 * k, Color(1, 0.97, 0.9))
		_scare.draw_circle(e, 7 * k, Color(0, 0, 0))
		_scare.draw_arc(e, 62 * k, 0, TAU, 40, Color(0.5, 0.0, 0.0, 0.8), 6 * k)
	# 찢어진 웃음
	var pts := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 25:
		var t := -1.0 + i / 12.0
		pts.append(c + Vector2(t * 300, 40 + 150 * (1.0 - t * t) * 0.6) * k)
		bottom.append(c + Vector2(t * 300, 70 + 260 * (1.0 - t * t) * 0.7) * k)
	bottom.reverse()
	var mouth := pts + bottom
	_scare.draw_colored_polygon(mouth, Color(0.92, 0.9, 0.8))
	for i in 24:
		var t := -1.0 + i / 12.0 + 1.0 / 24.0
		var top := c + Vector2(t * 300, 40 + 150 * (1.0 - t * t) * 0.6) * k
		var bot := c + Vector2(t * 300, 70 + 260 * (1.0 - t * t) * 0.7) * k
		_scare.draw_line(top, bot, Color(0.1, 0.0, 0.0), 5 * k)
	_scare.draw_rect(Rect2(Vector2(-40, -40), s + Vector2(80, 80)), Color(0.7, 0.0, 0.0, flash * 0.7))


# --- 창 ---

func _push_panel(p: Control) -> void:
	_panels.append(p)
	_panel_root.add_child(p)


func close_panel(p: Control) -> void:
	_panels.erase(p)
	if is_instance_valid(p):
		_panel_root.remove_child(p)
		p.queue_free()


func close_all_panels() -> void:
	for p in _panels.duplicate():
		close_panel(p)


func top_panel() -> Control:
	return _panels.back() if not _panels.is_empty() else null


func _dim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	return dim


## 쪽지: 종이 질감 패널 + 손글씨 느낌 글.
func show_note(text: String, on_close: Callable) -> void:
	Sfx.play("paper", -4.0)
	var dim := _dim()
	dim.name = "NotePanel"
	var paper := PanelContainer.new()
	var sb := _box(COLOR_PAPER, 6, 44)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	paper.add_theme_stylebox_override("panel", sb)
	paper.custom_minimum_size = Vector2(600, 0)
	paper.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	paper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	paper.grow_vertical = Control.GROW_DIRECTION_BOTH
	paper.rotation_degrees = -1.5
	dim.add_child(paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 30)
	paper.add_child(v)
	var label := _label(text, 32, COLOR_INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(510, 0)
	v.add_child(label)
	var close := _button("닫기", COLOR_INK, COLOR_PAPER)
	close.name = "Close"
	close.pressed.connect(func():
		close_panel(dim)
		if on_close.is_valid():
			on_close.call())
	v.add_child(close)
	_push_panel(dim)
	paper.pivot_offset = paper.size * 0.5


## 대사/독백: 화면 아래 자막. 아무 데나 누르면 다음 줄.
func show_lines(lines: Array, on_done: Callable, fullscreen := false) -> void:
	var root := ColorRect.new()
	root.name = "LinesPanel"
	root.color = Color(0, 0, 0, 1.0 if fullscreen else 0.0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.0) if fullscreen else COLOR_PANEL, 10, 30))
	if fullscreen:
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		box.position.y -= 230
	box.custom_minimum_size = Vector2(640, 0)
	# 글 상자가 탭을 삼키지 않도록: 탭은 전부 root가 받는다.
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 18)
	box.add_child(v)
	var label := _label("", 32 if fullscreen else 30, COLOR_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if fullscreen else HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(580, 0)
	v.add_child(label)
	var more := _label("▶ 화면을 누르세요", 22, Color(1, 1, 1, 0.4))
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(more)
	var state := {"i": 0, "tween": null}
	var type_line := func(text: String):
		label.text = text
		label.visible_ratio = 0.0
		state.tween = create_tween()
		state.tween.tween_property(label, "visible_ratio", 1.0, 0.03 * text.length())
	type_line.call(lines[0])
	root.gui_input.connect(func(e: InputEvent):
		var press: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)
		if not press:
			return
		root.accept_event()
		if label.visible_ratio < 1.0:
			# 타자 효과 중이면 한 번에 다 보여 준다
			state.tween.kill()
			label.visible_ratio = 1.0
			return
		state.i += 1
		if state.i >= lines.size():
			close_panel(root)
			if on_done.is_valid():
				on_done.call()
			return
		type_line.call(lines[state.i]))
	_push_panel(root)


## 빨간 문 번호판.
func show_keypad(on_submit: Callable, title := "") -> void:
	var dim := _dim()
	dim.name = "KeypadPanel"
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1b1b1b"), 18, 30))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	if title != "":
		var tl := _label(title, 28, COLOR_TEXT)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tl)
	var display := _label("_ _ _ _", 64, Color("ff5a4a"))
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.custom_minimum_size = Vector2(420, 90)
	v.add_child(display)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var state := {"code": ""}
	var refresh := func():
		var shown := ""
		for i in 4:
			shown += (state.code[i] if i < state.code.length() else "_") + (" " if i < 3 else "")
		display.text = shown
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "지움", "0", "확인"]:
		var b := _button(key, Color("e8e0c8"), Color("333333"))
		b.name = "Key_" + key
		b.custom_minimum_size = Vector2(130, 100)
		b.pressed.connect(func():
			Sfx.play("beep", -6.0)
			if key == "지움":
				state.code = state.code.substr(0, max(state.code.length() - 1, 0))
			elif key == "확인":
				var ok: bool = on_submit.call(state.code)
				if ok:
					close_panel(dim)
					return
				state.code = ""
				display.add_theme_color_override("font_color", Color("ff1a1a"))
				var tw := create_tween()
				tw.tween_property(panel, "position:x", panel.position.x + 14, 0.05)
				tw.tween_property(panel, "position:x", panel.position.x - 14, 0.05)
				tw.tween_property(panel, "position:x", panel.position.x, 0.05)
			elif state.code.length() < 4:
				state.code += key
			refresh.call())
		grid.add_child(b)
	var close := _button("돌아가기", COLOR_TEXT, Color("333333"))
	close.name = "Close"
	close.pressed.connect(func(): close_panel(dim))
	v.add_child(close)
	_push_panel(dim)


## 선택지 메뉴(제목, 일시정지 등).
func show_menu(title: String, subtitle: String, options: Array, fullscreen := true) -> Control:
	var root := ColorRect.new()
	root.name = "MenuPanel"
	root.color = Color(0, 0, 0, 1.0 if fullscreen else 0.75)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.custom_minimum_size = Vector2(520, 0)
	root.add_child(v)
	var t := _label(title, 96, COLOR_ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if subtitle != "":
		var st := _label(subtitle, 28, Color(1, 1, 1, 0.55))
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(st)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	v.add_child(spacer)
	for opt in options:
		var b := _button(opt[0], COLOR_TEXT, Color(0.15, 0.13, 0.08))
		b.name = "Opt_" + opt[0]
		b.custom_minimum_size = Vector2(520, 96)
		var cb: Callable = opt[1]
		b.pressed.connect(func():
			close_panel(root)
			cb.call())
		v.add_child(b)
	_push_panel(root)
	return root


func clear_toasts() -> void:
	for c in get_children():
		if c.is_in_group("toast"):
			c.queue_free()


## 짧은 알림(힌트, 숫자 발견 등). 몇 초 뒤 사라지고 입력을 막지 않는다.
func toast(text: String, sec := 3.5) -> void:
	var p := PanelContainer.new()
	p.add_to_group("toast")
	p.add_theme_stylebox_override("panel", _box(COLOR_PANEL, 10, 22))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.position.y = 120
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 28, COLOR_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	add_child(p)
	var tw := create_tween()
	tw.tween_interval(sec)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# --- 스타일 ---

func _box(color: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, fg: Color, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.add_theme_font_size_override("font_size", 32)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_stylebox_override("normal", _box(bg, 12, 10))
	b.add_theme_stylebox_override("hover", _box(bg, 12, 10))
	b.add_theme_stylebox_override("pressed", _box(bg.lightened(0.15), 12, 10))
	b.add_theme_stylebox_override("focus", _box(bg, 12, 10))
	return b
