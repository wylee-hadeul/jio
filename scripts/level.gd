extends Node3D
## 레이아웃(levels.gd가 만든 사전)으로 레벨을 짓는다: 벽/바닥/천장, 물체, 숨은 숫자, 길찾기.
## '#' 벽, '.' 불 켜진 바닥, ',' 불 꺼진 바닥, 'o' 기둥, 'O' 어둠 속 기둥, 'R' 비밀 방

const CELL := 3.0
const HEIGHT := 3.0
const DOOR_WIDTH := 1.2
const DOOR_HEIGHT := 2.2
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var layout: Dictionary
var map: Array = []
var size := Vector2i.ZERO
var start := Vector2i.ZERO
var anomaly := Vector2i(-1, -1)
var anomaly_front := Vector2i(-1, -1)
var secret_room := Vector2i(-1, -1)
var materials: Array[ShaderMaterial] = []
var light_tex: ImageTexture
var font: Font
## id -> {kind, cell, dir, data, body, target(조준점)}
var props := {}
var digit_labels := {}
var door_body: StaticBody3D
var door_pivot: Node3D
var anomaly_body: StaticBody3D

var _shader := preload("res://shaders/backrooms.gdshader")
var _theme: Dictionary
var _lights_out := false


func build(lay: Dictionary) -> void:
	layout = lay
	map = lay.map
	size = Vector2i(map[0].length(), map.size())
	start = lay.start
	anomaly = lay.get("anomaly", Vector2i(-1, -1))
	anomaly_front = lay.get("anomaly_front", Vector2i(-1, -1))
	secret_room = lay.get("secret_room", Vector2i(-1, -1))
	_theme = lay.theme
	font = load("res://fonts/GowunBatang-Subset.ttf")
	_build_light_map()
	_build_floor_ceiling()
	_build_walls()
	_build_pillars()
	for p in lay.props:
		_build_prop(p)
	for d in lay.digits:
		_build_digit(d)


# --- 좌표 ---

func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func cell_center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, y, (c.y + 0.5) * CELL)


func tile(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return "#"
	return map[c.y][c.x]


func is_open(c: Vector2i) -> bool:
	return tile(c) in [".", ",", "o", "O"] or (c == secret_room and G.has("door_open"))


func is_dark(c: Vector2i) -> bool:
	return tile(c) in [",", "O"] or _lights_out


## 벽에 붙은 물체의 위치/방향: 칸 c에서 d쪽 벽면, 칸 안쪽을 바라본다.
func wall_point(c: Vector2i, d: Vector2i, y: float, inset := 0.06) -> Vector3:
	return cell_center(c, y) + Vector3(d.x, 0, d.y) * (CELL * 0.5 - inset)


func wall_yaw(d: Vector2i) -> float:
	return atan2(float(-d.x), float(-d.y))


## 너비 우선 탐색 최단 경로(시작 칸 제외, 도착 칸 포함). 기둥 칸은 비켜 지나갈 수 있다.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if is_open(n) and not prev.has(n):
				prev[n] = c
				q.append(n)
	var out: Array[Vector2i] = []
	if not prev.has(to):
		return out
	var cur := to
	while cur != from:
		out.push_front(cur)
		cur = prev[cur]
	return out


## 경로상의 칸 c를 지날 때 향할 지점. 기둥 칸은 기둥을 비켜 가장자리로 지난다.
func waypoint(prev: Vector2i, c: Vector2i, next: Vector2i) -> Vector3:
	var center := cell_center(c)
	if not tile(c) in ["o", "O"]:
		return center
	var a := Vector2(c - prev)
	var b := Vector2(next - c)
	var off: Vector2
	if a == Vector2.ZERO or b == Vector2.ZERO or a == b:
		var d := b if a == Vector2.ZERO else a
		off = Vector2(-d.y, d.x)
	else:
		off = b - a
	off = off.normalized() * 0.95
	return center + Vector3(off.x, 0, off.y)


func open_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if is_open(c) and c != secret_room:
				out.append(c)
	return out


# --- 재질/빛 ---

func make_material(kind: int, color := Color.WHITE, anomaly_amount := 0.0, emissive := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("anomaly", anomaly_amount)
	m.set_shader_parameter("emissive", emissive)
	m.set_shader_parameter("light_map", light_tex)
	m.set_shader_parameter("map_size", Vector2(size))
	m.set_shader_parameter("cell", CELL)
	m.set_shader_parameter("wall_style", _theme.wall)
	m.set_shader_parameter("wall_a", _theme.wall_a)
	m.set_shader_parameter("floor_style", _theme.floor)
	m.set_shader_parameter("floor_a", _theme.floor_a)
	m.set_shader_parameter("ceil_style", _theme.ceil)
	m.set_shader_parameter("ceil_a", _theme.ceil_a)
	m.set_shader_parameter("light_color", _theme.light)
	m.set_shader_parameter("fog_color", _theme.fog)
	m.set_shader_parameter("fog_far", _theme.fog_far)
	materials.append(m)
	return m


func set_shared(param: String, value) -> void:
	for m in materials:
		m.set_shader_parameter(param, value)


## 차단기를 모두 내리면 층 전체가 꺼진다.
func set_lights_out(out: bool) -> void:
	_lights_out = out
	set_shared("global_light", 0.0 if out else 1.0)


func _build_light_map() -> void:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	for y in size.y:
		for x in size.x:
			img.set_pixel(x, y, Color(_light_value(Vector2i(x, y)), 0, 0))
	light_tex = ImageTexture.create_from_image(img)


func _light_value(c: Vector2i) -> float:
	var t := tile(c)
	if t in [".", "o"]:
		return 1.0
	if t == "R":
		return 0.55
	if t in [",", "O"]:
		return 0.0
	var sum := 0.0
	var n := 0
	for d in DIRS:
		var nt := tile(c + d)
		if nt != "#":
			sum += 0.0 if nt in [",", "O"] else 1.0
			n += 1
	return sum / n if n > 0 else 1.0


# --- 지오메트리 ---

func _build_floor_ceiling() -> void:
	var w := size.x * CELL
	var h := size.y * CELL
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	floor_mi.mesh = pm
	floor_mi.position = Vector3(w / 2, 0, h / 2)
	floor_mi.material_override = make_material(1)
	add_child(floor_mi)
	var floor_body := StaticBody3D.new()
	_add_box_collider(floor_body, Vector3(w / 2, -0.5, h / 2), Vector3(w, 1, h))
	add_child(floor_body)
	var ceil_mi := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	cm.size = Vector2(w, h)
	cm.flip_faces = true
	ceil_mi.mesh = cm
	ceil_mi.position = Vector3(w / 2, HEIGHT, h / 2)
	ceil_mi.material_override = make_material(2)
	add_child(ceil_mi)


func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anomaly_st := SurfaceTool.new()
	anomaly_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	add_child(body)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if tile(c) != "#":
				continue
			var target := anomaly_st if c == anomaly else st
			for d in DIRS:
				var nt := tile(c + d)
				if nt == "#" or c + d == secret_room:
					continue
				_add_face(target, c, d)
			if c == anomaly:
				continue
			_add_box_collider(body, cell_center(c, HEIGHT / 2), Vector3(CELL, HEIGHT, CELL))
	if secret_room.x >= 0:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			_add_face(st, secret_room + d, -d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = make_material(0)
	add_child(mi)
	if anomaly.x >= 0:
		var ami := MeshInstance3D.new()
		ami.mesh = anomaly_st.commit()
		ami.material_override = make_material(0, Color.WHITE, 1.0)
		add_child(ami)
		anomaly_body = StaticBody3D.new()
		add_child(anomaly_body)
		_add_box_collider(anomaly_body, cell_center(anomaly, HEIGHT / 2), Vector3(CELL, HEIGHT, CELL))


func _add_face(st: SurfaceTool, c: Vector2i, d: Vector2i) -> void:
	var center := cell_center(c) + Vector3(d.x, 0, d.y) * CELL * 0.5
	var right := Vector3(-d.y, 0, d.x) * CELL * 0.5
	var a := center - right
	var b := center + right
	var up := Vector3(0, HEIGHT, 0)
	# Godot은 앞면이 시계 방향. 법선은 면마다 직접 지정해 모서리에서 섞이지 않게 한다.
	st.set_normal(Vector3(d.x, 0, d.y))
	for v in [a, b, b + up, a, b + up, a + up]:
		st.add_vertex(v)


func _add_box_collider(body: CollisionObject3D, pos: Vector3, box_size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)


func _build_pillars() -> void:
	var mat := make_material(0)
	var body := StaticBody3D.new()
	add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, HEIGHT, 0.8)
	for y in size.y:
		for x in size.x:
			if tile(Vector2i(x, y)) in ["o", "O"]:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = mat
				mi.position = cell_center(Vector2i(x, y), HEIGHT / 2)
				add_child(mi)
				_add_box_collider(body, mi.position, mesh.size)


func open_door(animate := true) -> void:
	if door_body == null:
		return
	for c in door_body.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	var angle := deg_to_rad(100)
	if animate:
		create_tween().tween_property(door_pivot, "rotation:y", door_pivot.rotation.y + angle, 1.6).set_trans(Tween.TRANS_SINE)
	else:
		door_pivot.rotation.y += angle


func set_anomaly_passable(passable: bool) -> void:
	if anomaly_body == null:
		return
	for c in anomaly_body.get_children():
		c.disabled = passable


# --- 물체 ---

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, emissive := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = make_material(3, color, 0.0, emissive)
	parent.add_child(mi)
	return mi


func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


## 조사용 몸체: 2번 층 충돌체(플레이어는 통과, 터치 광선만 맞음).
func _prop_body(id: String, pos: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("id", id)
	body.collision_layer = 2
	body.position = pos
	body.rotation.y = yaw
	add_child(body)
	return body


func _build_prop(p: Dictionary) -> void:
	var id: String = p.id
	var kind: String = p.kind
	var c: Vector2i = p.cell
	var d: Vector2i = p.dir
	var entry := {"kind": kind, "cell": c, "dir": d, "data": p.data, "body": null, "target": cell_center(c, 1.0)}
	props[id] = entry
	match kind:
		"note":
			var body := _prop_body(id, cell_center(c))
			var paper := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(0.28, 0.38)
			paper.mesh = pm
			paper.material_override = make_material(3, Color("e9e4d2"))
			paper.position = Vector3(0.35, 0.01, 0.4)
			paper.rotation.y = (hash(id) % 100) / 100.0 - 0.5
			body.add_child(paper)
			_add_box_collider(body, paper.position + Vector3(0, 0.15, 0), Vector3(0.8, 0.4, 0.8))
			entry.body = body
			entry.target = body.position + Vector3(0.35, 0.05, 0.4)
		"pack":
			var body := _prop_body(id, cell_center(c))
			var bag := _mesh(body, _box(Vector3(0.5, 0.4, 0.3)), Vector3(-0.6, 0.2, -0.6), Color("2e3b4f"))
			bag.rotation.y = 0.4
			var tm := CylinderMesh.new()
			tm.top_radius = 0.04
			tm.bottom_radius = 0.05
			tm.height = 0.25
			var torch := _mesh(body, tm, Vector3(-0.25, 0.05, -0.4), Color("444444"))
			torch.rotation.z = PI / 2
			_add_box_collider(body, Vector3(-0.5, 0.25, -0.5), Vector3(1.0, 0.6, 0.8))
			entry.body = body
			entry.target = body.position + Vector3(-0.5, 0.2, -0.5)
		"phone":
			var pos := cell_center(c) + Vector3(d.x, 0, d.y) * 0.9 if d != Vector2i.ZERO else cell_center(c) + Vector3(0.6, 0, 0.6)
			var body := _prop_body(id, pos)
			_mesh(body, _box(Vector3(0.8, 0.75, 0.6)), Vector3(0, 0.375, 0), Color("4a3424"))
			_mesh(body, _box(Vector3(0.3, 0.12, 0.22)), Vector3(0, 0.81, 0), Color("6b1d1d"))
			_add_box_collider(body, Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.7))
			entry.body = body
			entry.target = pos + Vector3(0, 0.8, 0)
		"room_door":
			_build_room_door(id, p)
		"exit_door", "elevator", "numdoor":
			_build_wall_door(id, p)
		"lever":
			var body := _prop_body(id, wall_point(c, d, 1.3), wall_yaw(d))
			_mesh(body, _box(Vector3(0.45, 0.45, 0.12)), Vector3.ZERO, Color("5a4632"))
			var wheel := _mesh(body, _box(Vector3(0.36, 0.08, 0.08)), Vector3(0, 0, 0.1), Color("b03a2e"))
			wheel.name = "Handle"
			var lamp := _mesh(body, _box(Vector3(0.08, 0.08, 0.04)), Vector3(0, 0.3, 0.07), Color("8a1010"), 0.6)
			lamp.name = "Lamp"
			_add_box_collider(body, Vector3(0, 0, 0.1), Vector3(0.7, 0.8, 0.4))
			entry.body = body
			entry.target = body.position
		"breaker":
			var body := _prop_body(id, wall_point(c, d, 1.35), wall_yaw(d))
			_mesh(body, _box(Vector3(0.4, 0.55, 0.14)), Vector3.ZERO, Color("6d7277"))
			var sw := _mesh(body, _box(Vector3(0.08, 0.2, 0.08)), Vector3(0, 0.08, 0.1), Color("d9c46a"), 0.3)
			sw.name = "Handle"
			var lamp := _mesh(body, _box(Vector3(0.07, 0.07, 0.04)), Vector3(0.13, 0.2, 0.08), Color("20c040"), 0.8)
			lamp.name = "Lamp"
			_add_box_collider(body, Vector3(0, 0, 0.1), Vector3(0.7, 0.8, 0.4))
			entry.body = body
			entry.target = body.position
		"hatch":
			var body := _prop_body(id, cell_center(c, HEIGHT - 0.02))
			var q := _mesh(body, _box(Vector3(1.1, 0.03, 1.1)), Vector3.ZERO, Color("2a2a2a"))
			q.name = "Panel"
			var sign := _label("EXIT", 70, Color("6dff9a"))
			sign.rotation = Vector3(PI / 2, 0, 0)
			sign.position = Vector3(0, -0.03, 0)
			sign.name = "Sign"
			sign.visible = false
			body.add_child(sign)
			_add_box_collider(body, Vector3(0, -0.15, 0), Vector3(1.3, 0.4, 1.3))
			entry.body = body
			entry.target = body.position
		"key":
			var body := _prop_body(id, cell_center(c) + Vector3(0.4, 0, -0.3))
			var k := _mesh(body, _box(Vector3(0.22, 0.03, 0.07)), Vector3(0, 0.03, 0), Color("e6c34a"), 0.5)
			k.rotation.y = 0.7
			_mesh(body, _box(Vector3(0.09, 0.03, 0.09)), Vector3(-0.12, 0.03, -0.1), Color("e6c34a"), 0.5)
			_add_box_collider(body, Vector3(0, 0.2, 0), Vector3(0.8, 0.5, 0.8))
			entry.body = body
			entry.target = body.position + Vector3(0, 0.05, 0)
		"balloon":
			var body := _prop_body(id, cell_center(c) + Vector3(-0.3, 0, 0.3))
			var sp := SphereMesh.new()
			sp.radius = 0.28
			sp.height = 0.66
			var colors := [Color("e04848"), Color("4878e0"), Color("e0c048"), Color("48c070"), Color("c048c0")]
			_mesh(body, sp, Vector3(0, 1.55, 0), colors[hash(id) % colors.size()], 0.15)
			_mesh(body, _box(Vector3(0.01, 1.2, 0.01)), Vector3(0, 0.75, 0), Color("dddddd"))
			_add_box_collider(body, Vector3(0, 1.4, 0), Vector3(0.8, 1.2, 0.8))
			entry.body = body
			entry.target = body.position + Vector3(0, 1.55, 0)
		"cooler":
			var body := _prop_body(id, cell_center(c) + Vector3(-0.8, 0, -0.8))
			_mesh(body, _box(Vector3(0.4, 1.0, 0.4)), Vector3(0, 0.5, 0), Color("dedede"))
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.16
			cyl.bottom_radius = 0.16
			cyl.height = 0.42
			_mesh(body, cyl, Vector3(0, 1.21, 0), Color("6aa8d8"), 0.1)
			entry.body = body
		"chair":
			var body := _prop_body(id, cell_center(c) + Vector3(0.8, 0, 0.8))
			body.rotation.y = (hash(id) % 628) / 100.0
			_mesh(body, _box(Vector3(0.45, 0.06, 0.45)), Vector3(0, 0.45, 0), Color("3a3a40"))
			_mesh(body, _box(Vector3(0.45, 0.5, 0.06)), Vector3(0, 0.72, -0.2), Color("3a3a40"))
			_mesh(body, _box(Vector3(0.05, 0.45, 0.05)), Vector3(0, 0.22, 0), Color("222222"))
			entry.body = body
		"arrows":
			var route: Array = p.data.route
			for i in range(0, route.size() - 1, 2):
				var a: Vector2i = route[i]
				var b: Vector2i = route[i + 1]
				var dir := b - a
				var arrow := _label("→", 160, Color("e8e8e8"))
				arrow.position = cell_center(a, 0.02)
				arrow.rotation = Vector3(-PI / 2, atan2(float(-dir.y), float(dir.x)), 0)
				add_child(arrow)


## 레벨 0: 빨간 문 뒤 비밀 방(문틀 벽 + 회전 문 + EXIT 표시 + 번호판).
func _build_room_door(id: String, p: Dictionary) -> void:
	var front: Vector2i = p.cell
	var d: Vector2i = p.dir
	var room: Vector2i = front + d
	var z := room.y * CELL + CELL
	var cx := (room.x + 0.5) * CELL
	var wall_mat := make_material(0)
	var side_w := (CELL - DOOR_WIDTH) / 2
	var frame := StaticBody3D.new()
	add_child(frame)
	for spec in [
		[Vector3(cx - DOOR_WIDTH / 2 - side_w / 2, HEIGHT / 2, z), Vector3(side_w, HEIGHT, 0.12)],
		[Vector3(cx + DOOR_WIDTH / 2 + side_w / 2, HEIGHT / 2, z), Vector3(side_w, HEIGHT, 0.12)],
		[Vector3(cx, (HEIGHT + DOOR_HEIGHT) / 2, z), Vector3(DOOR_WIDTH, HEIGHT - DOOR_HEIGHT, 0.12)],
	]:
		var mi := MeshInstance3D.new()
		mi.mesh = _box(spec[1])
		mi.material_override = wall_mat
		mi.position = spec[0]
		add_child(mi)
		_add_box_collider(frame, spec[0], spec[1])
	door_pivot = Node3D.new()
	door_pivot.position = Vector3(cx - DOOR_WIDTH / 2, 0, z)
	add_child(door_pivot)
	door_body = StaticBody3D.new()
	door_body.set_meta("id", id)
	door_pivot.add_child(door_body)
	_mesh(door_body, _box(Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.08)), Vector3(DOOR_WIDTH / 2, DOOR_HEIGHT / 2, 0), Color("8e1b1b"))
	_add_box_collider(door_body, Vector3(DOOR_WIDTH / 2, DOOR_HEIGHT / 2, 0), Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.08))
	var km := SphereMesh.new()
	km.radius = 0.05
	km.height = 0.1
	_mesh(door_body, km, Vector3(DOOR_WIDTH - 0.12, 1.0, 0.07), Color("c9b27a"))
	_mesh(self, _box(Vector3(0.7, 0.26, 0.06)), Vector3(cx, DOOR_HEIGHT + 0.3, z + 0.08), Color("0b5e2a"), 0.6)
	var exit_label := _label("EXIT", 64, Color("b8ffcf"))
	exit_label.position = Vector3(cx, DOOR_HEIGHT + 0.3, z + 0.115)
	add_child(exit_label)
	var pad := _prop_body(id, Vector3(cx + DOOR_WIDTH / 2 + 0.25, 1.3, z + 0.08))
	_mesh(pad, _box(Vector3(0.16, 0.24, 0.05)), Vector3.ZERO, Color("2a2a2a"), 0.05)
	_add_box_collider(pad, Vector3.ZERO, Vector3(0.4, 0.5, 0.2))
	props[id].body = door_body
	props[id].target = Vector3(cx, 1.1, z)


## 벽에 붙은 문: 출구 문 / 승강기 / 번호 문.
func _build_wall_door(id: String, p: Dictionary) -> void:
	var c: Vector2i = p.cell
	var d: Vector2i = p.dir
	var kind: String = p.kind
	var body := _prop_body(id, wall_point(c, d, 0.0, 0.05), wall_yaw(d))
	body.collision_layer = 3
	var door_color: Color = {"exit_door": Color("5a5f66"), "elevator": Color("8f959c"), "numdoor": Color("5b3a22")}[kind]
	_mesh(body, _box(Vector3(1.5, 2.45, 0.08)), Vector3(0, 1.225, -0.02), Color("2a2622"))
	if kind == "elevator":
		var left := _mesh(body, _box(Vector3(0.6, 2.2, 0.06)), Vector3(-0.3, 1.1, 0.03), door_color)
		left.name = "Left"
		var right := _mesh(body, _box(Vector3(0.6, 2.2, 0.06)), Vector3(0.3, 1.1, 0.03), door_color)
		right.name = "Right"
		var counter := _label("0 / %d" % int(p.data.get("count", 0)), 60, Color("ffb347"))
		counter.position = Vector3(0, 2.5, 0.07)
		counter.name = "Counter"
		body.add_child(counter)
	else:
		var leaf := _mesh(body, _box(Vector3(1.2, 2.2, 0.06)), Vector3(0, 1.1, 0.03), door_color)
		leaf.name = "Leaf"
		_mesh(body, _box(Vector3(0.08, 0.08, 0.08)), Vector3(0.45, 1.0, 0.09), Color("c9b27a"))
	if kind == "exit_door":
		_mesh(body, _box(Vector3(0.7, 0.26, 0.06)), Vector3(0, 2.6, 0.03), Color("0b5e2a"), 0.6)
		var sign := _label("EXIT", 64, Color("b8ffcf"))
		sign.position = Vector3(0, 2.6, 0.07)
		body.add_child(sign)
		var needs: Array = p.data.get("needs", [])
		if p.data.get("code", "") != "":
			_mesh(body, _box(Vector3(0.16, 0.24, 0.05)), Vector3(0.85, 1.3, 0.04), Color("2a2a2a"), 0.05)
		elif not needs.is_empty():
			var counter := _label("0 / %d" % needs.size(), 50, Color("ffb347"))
			counter.position = Vector3(0, 2.32, 0.07)
			counter.name = "Counter"
			body.add_child(counter)
	elif kind == "numdoor":
		var plate := _label(str(p.data.number), 70, Color("e6d3a0"))
		plate.position = Vector3(0, 1.75, 0.07)
		body.add_child(plate)
	_add_box_collider(body, Vector3(0, 1.1, 0.1), Vector3(1.5, 2.3, 0.3))
	props[id].body = body
	props[id].target = body.position + Vector3(0, 1.2, 0)


func set_counter(id: String, done: int, total: int) -> void:
	if not props.has(id) or props[id].body == null:
		return
	var counter := props[id].body.get_node_or_null("Counter") as Label3D
	if counter:
		counter.text = "%d / %d" % [done, total]
		counter.modulate = Color("6dff9a") if done >= total else Color("ffb347")


func open_wall_door(id: String) -> void:
	var body: Node3D = props[id].body
	var left := body.get_node_or_null("Left") as Node3D
	var right := body.get_node_or_null("Right") as Node3D
	var leaf := body.get_node_or_null("Leaf") as Node3D
	var tw := create_tween().set_parallel()
	if left and right:
		tw.tween_property(left, "position:x", -0.85, 1.2)
		tw.tween_property(right, "position:x", 0.85, 1.2)
	if leaf:
		tw.tween_property(leaf, "position:y", 1.1 + 2.4, 1.4)
	var void_panel := _mesh(body, _box(Vector3(1.2, 2.2, 0.02)), Vector3(0, 1.1, -0.01), Color(0, 0, 0))
	void_panel.name = "Void"


func set_prop_state(id: String, on: bool) -> void:
	if not props.has(id) or props[id].body == null:
		return
	var body: Node3D = props[id].body
	var handle := body.get_node_or_null("Handle") as Node3D
	var lamp := body.get_node_or_null("Lamp") as MeshInstance3D
	if handle:
		match props[id].kind:
			"lever":
				handle.rotation.z = PI / 2 if on else 0.0
			"breaker":
				handle.position.y = -0.08 if on else 0.08
	if lamp:
		var lit: Color = Color("20c040") if (props[id].kind == "lever") == on else Color("8a1010")
		(lamp.material_override as ShaderMaterial).set_shader_parameter("base_color", lit)


func remove_prop(id: String) -> void:
	if props.has(id) and props[id].body:
		props[id].body.queue_free()
		props[id].body = null


func reveal_hatch(id: String) -> void:
	var body: Node3D = props[id].body
	var sign := body.get_node("Sign") as Label3D
	sign.visible = true
	var panel := body.get_node("Panel") as MeshInstance3D
	(panel.material_override as ShaderMaterial).set_shader_parameter("base_color", Color("1f7a3a"))
	(panel.material_override as ShaderMaterial).set_shader_parameter("emissive", 1.2)


# --- 숨은 숫자 ---

func _build_digit(d: Dictionary) -> void:
	var c: Vector2i = d.cell
	var dir: Vector2i = d.dir
	var label := _label(d.value, 200, Color("7a1010"))
	match d.kind:
		"ceiling":
			label.position = cell_center(c, HEIGHT - 0.01)
			label.rotation = Vector3(PI / 2, 0, 0)
		"floor":
			label.position = cell_center(c, 0.02)
			label.rotation = Vector3(-PI / 2, 0, 0)
		"pillar":
			label.font_size = 150
			label.position = cell_center(c, 1.6) + Vector3(dir.x, 0, dir.y) * 0.41
			label.rotation = Vector3(0, atan2(float(dir.x), float(dir.y)), 0)
		"dark", "behind":
			label.position = wall_point(c, dir, 1.85, 0.01)
			label.rotation = Vector3(0, wall_yaw(dir), 0)
			if d.get("scrawl", "") != "":
				var scrawl := _label(d.scrawl, 30, Color("8c1414"))
				scrawl.position = Vector3(0, -0.55, 0)
				label.add_child(scrawl)
	if d.get("mirror", false):
		label.scale.x = -1.0
	add_child(label)
	digit_labels[d.key] = {"label": label, "kind": d.kind, "value": d.value}


func _label(text: String, px: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = px
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	return l
