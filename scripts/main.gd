extends Node3D
## 게임 진행 담당: 레벨/플레이어/그것/HUD를 만들고, 조사·숫자 발견·잡힘·엔딩을 처리한다.

const Level := preload("res://scripts/level.gd")
const Player := preload("res://scripts/player.gd")
const Entity := preload("res://scripts/entity.gd")
const Hud := preload("res://scripts/hud.gd")
const Autoplay := preload("res://scripts/autoplay.gd")

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
	entity.caught.connect(_on_caught)
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
	var options: Array = []
	if G.has_save() and not G.autoplay:
		options.append(["이어하기", func(): _begin(true)])
		options.append(["처음부터", func(): _begin(false)])
	else:
		options.append(["들어가기", func(): _begin(false)])
	hud.show_menu("백룸", "LEVEL 0\n\n소리를 켜고 이어폰을 권장합니다", options)


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
	if G.has("note2") and not G.has("escaped"):
		entity.spawn_far(player.global_position, player.camera)


# --- 매 프레임 ---

func _process(delta: float) -> void:
	player.frozen = hud.is_blocked() or not playing
	_update_flicker(delta)
	_update_shader()
	if not playing:
		_update_audio(INF)
		return
	if not hud.is_blocked():
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
	level.set_shared("cam_dir", player.look_dir())
	level.set_shared("flash_on", 1.0 if player.flashlight_on else 0.0)
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
			hud.show_digits = true
			hud.toast("어디선가 전화벨이 울린다.\n...그리고 아주 잠깐, 형광등 소리가 끊겼다.", 5.0)
			flicker_burst(30)
			entity.spawn_far(player.global_position, player.camera)
		elif id == "note6":
			hud.toast("어긋난 벽... 처음 떨어진 곳 근처였다.", 5.0))


func _open_pack() -> void:
	if G.has("flashlight"):
		hud.toast("텅 빈 배낭이다. 지수의 이름표가 달려 있다.")
		return
	G.set_flag("flashlight")
	hud.show_flashlight_button = true
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
			level.open_door()
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
	Sfx.stop_all()
	Sfx.play("whoosh")
	hud.show_lines(G.ENDING, func():
		hud.show_menu("탈출", "LEVEL 0을 벗어났다.\n...아니면, 처음으로 돌아왔다.", [["처음부터", func():
			G.reset()
			_begin(false)]]), true)


func _on_caught() -> void:
	playing = false
	hud.scare()
	await get_tree().create_timer(1.0).timeout
	hud.show_lines(G.CAUGHT_LINES, func():
		player.teleport(G.checkpoint, G.checkpoint_yaw)
		player.eyes_closed = false
		playing = true
		entity.spawn_far(player.global_position, player.camera), true)


func _open_menu() -> void:
	if not playing or hud.is_blocked():
		return
	hud.show_menu("일시정지", "찾은 번호  " + " ".join(G.digits_found().split("")), [
		["계속하기", func(): pass],
		["처음부터", func():
			G.reset()
			entity.despawn()
			playing = false
			_begin(false)],
	], false)
