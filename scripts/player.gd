extends CharacterBody3D
## 1인칭 플레이어. 이동/시점 입력은 HUD(터치)와 키보드에서 받는다.

const SPEED := 2.7
const EYE_HEIGHT := 1.6
const LOOK_SENS := 0.0045
const STEP_INTERVAL := 0.55

## x: 오른쪽(+), y: 앞(+). HUD 조이스틱이 채운다.
var move_input := Vector2.ZERO
var yaw := 0.0
var pitch := 0.0
var frozen := false
var flashlight_on := false
var eyes_closed := false
var camera: Camera3D

var _step_timer := 0.0
var _bob := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 40.0
	add_child(camera)


func look(delta_px: Vector2) -> void:
	if frozen:
		return
	yaw -= delta_px.x * LOOK_SENS
	pitch = clampf(pitch - delta_px.y * LOOK_SENS, deg_to_rad(-80), deg_to_rad(80))


func face_towards(target: Vector3) -> void:
	var d := target - camera.global_position
	yaw = atan2(-d.x, -d.z)
	pitch = atan2(d.y, Vector2(d.x, d.z).length())


func teleport(pos: Vector3, new_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0


func _physics_process(delta: float) -> void:
	rotation.y = yaw
	camera.rotation.x = pitch

	var input := move_input
	var kb := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_up") - Input.get_action_strength("ui_down"))
	if Input.is_physical_key_pressed(KEY_W): kb.y += 1
	if Input.is_physical_key_pressed(KEY_S): kb.y -= 1
	if Input.is_physical_key_pressed(KEY_D): kb.x += 1
	if Input.is_physical_key_pressed(KEY_A): kb.x -= 1
	if kb != Vector2.ZERO:
		input = kb.limit_length(1.0)
	if frozen:
		input = Vector2.ZERO

	var dir := (transform.basis * Vector3(input.x, 0, -input.y))
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()

	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	if moving:
		_bob += delta * 8.0
		_step_timer += delta
		if _step_timer >= STEP_INTERVAL:
			_step_timer = 0.0
			Sfx.play("step", -14.0, randf_range(0.85, 1.1))
	else:
		_bob = lerpf(_bob, round(_bob / PI) * PI, delta * 6.0)
	camera.position.y = EYE_HEIGHT + sin(_bob) * 0.035


func look_dir() -> Vector3:
	return -camera.global_transform.basis.z
