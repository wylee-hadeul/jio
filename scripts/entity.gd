extends Node3D
## '그것'. 플레이어가 보고 있으면 멈추고, 시선을 돌리거나 눈을 감으면 칸 단위 최단 경로로 다가온다.

## 잡힌 사람: "" 이면 이 기기의 플레이어, 아니면 동료의 네트워크 id
signal caught(id: String)

const SPEED := 1.9
const CATCHUP_SPEED := 3.4
const CATCHUP_DIST := 15.0
const CATCH_DIST := 1.25
const VIEW_DIST := 24.0
const REPATH_SEC := 0.4
const SPAWN_MIN_STEPS := 9

var level: Node3D
var active := false
var seen := false
var _path: Array[Vector2i] = []
var _repath := 0.0
var _face: MeshInstance3D


func setup(lvl: Node3D) -> void:
	level = lvl
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 2.3
	body.mesh = cap
	body.position.y = 1.15
	body.material_override = level.make_material(3, Color(0.015, 0.012, 0.01))
	add_child(body)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.08, 1.5, 0.08)
		arm.mesh = am
		arm.position = Vector3(0.32 * side, 1.15, 0.0)
		arm.rotation.z = 0.08 * side
		arm.material_override = body.material_override
		add_child(arm)
	_face = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.62)
	_face.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/smile.gdshader")
	_face.material_override = fm
	_face.position = Vector3(0, 2.05, 0.26)
	add_child(_face)
	visible = false


func spawn_far(player_pos: Vector3, camera: Camera3D) -> void:
	var from: Vector2i = level.cell_at(player_pos)
	var best := Vector2i(-1, -1)
	var best_len := -1
	var cells: Array[Vector2i] = level.open_cells()
	cells.shuffle()
	for c in cells:
		var steps: int = level.path(from, c).size()
		if steps < SPAWN_MIN_STEPS:
			continue
		global_position = level.cell_center(c)
		if _visible_from(camera, false):
			continue
		best = c
		break
	if best.x < 0:
		# 조건에 맞는 칸이 없으면 가장 먼 칸
		for c in cells:
			var steps: int = level.path(from, c).size()
			if steps > best_len:
				best_len = steps
				best = c
	global_position = level.cell_center(best)
	_path.clear()
	active = true
	visible = true


func place(pos: Vector3) -> void:
	global_position = pos
	_path.clear()
	_repath = 0.0
	active = true
	visible = true


func despawn() -> void:
	_path.clear()
	active = false
	visible = false
	global_position = Vector3(9999, 0, 9999)


## watchers: 동료 목록 [{id, pos, sees}]. 누구 하나라도 보고 있으면 멈추고, 가장 가까운 사람을 쫓는다.
func tick(delta: float, player: CharacterBody3D, watchers: Array = []) -> void:
	if not active:
		return
	var cam: Camera3D = player.camera
	seen = _visible_from(cam, player.eyes_closed)
	var target_id := ""
	var target_pos: Vector3 = player.global_position
	var best := Vector2(target_pos.x - global_position.x, target_pos.z - global_position.z).length()
	for w in watchers:
		if w.sees:
			seen = true
		var d := Vector2(w.pos.x - global_position.x, w.pos.z - global_position.z).length()
		if d < best:
			best = d
			target_id = w.id
			target_pos = w.pos
	# 얼굴은 쫓는 사람을 향한다
	var to_target := target_pos - global_position
	rotation.y = atan2(to_target.x, to_target.z)
	var flat := Vector2(to_target.x, to_target.z)
	if flat.length() < CATCH_DIST:
		if target_id == "":
			active = false
		caught.emit(target_id)
		return
	if seen:
		return

	_repath -= delta
	if _repath <= 0.0 or _path.is_empty():
		_repath = REPATH_SEC
		_path = level.path(level.cell_at(global_position), level.cell_at(target_pos))
	var target: Vector3
	if _path.size() <= 1:
		target = target_pos
	else:
		var here: Vector2i = level.cell_at(global_position)
		target = level.waypoint(here, _path[0], _path[1])
		if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 0.3:
			_path.pop_front()
	var speed := CATCHUP_SPEED if flat.length() > CATCHUP_DIST else SPEED
	var step := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if step.length() > 0.001:
		global_position += step.normalized() * min(step.length(), speed * delta)


func _visible_from(cam: Camera3D, eyes_closed: bool) -> bool:
	if eyes_closed:
		return false
	var space := get_world_3d().direct_space_state
	# 몸의 가운데뿐 아니라 양쪽 가장자리도 확인: 모서리에 반쯤 걸쳐 보여도 '보는 중'이다
	var side: Vector3 = cam.global_transform.basis.x * 0.3
	for off in [Vector3(0, 2.05, 0), Vector3(0, 1.2, 0), Vector3(0, 0.4, 0),
			Vector3(0, 1.6, 0) + side, Vector3(0, 1.6, 0) - side, Vector3(0, 0.7, 0) + side, Vector3(0, 0.7, 0) - side]:
		var p: Vector3 = global_position + off
		if cam.global_position.distance_to(p) > VIEW_DIST:
			continue
		if not cam.is_position_in_frustum(p):
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, p)
		q.collide_with_areas = false
		var player := cam.get_parent()
		if player is CollisionObject3D:
			q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
	return false
