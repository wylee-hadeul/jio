extends Node3D
## 레벨 0 맵. 문자 지도에서 벽/바닥/천장/물체를 만들고, 칸 단위 길찾기를 제공한다.
## '#' 벽, '.' 불 켜진 바닥, ',' 불 꺼진 바닥, 'o' 기둥, 'O' 어둠 속 기둥, 'R' 빨간 문 뒤 방

const CELL := 3.0
const HEIGHT := 3.0
const MAP := [
	"#################",
	"#.....#.....#...#",
	"#.o.o.#.o.o.....#",
	"#.........#.#.o.#",
	"###.###.#.#.#####",
	"#.....#.#...#R###",
	"#.o.o...#.o.....#",
	"#.....###...#.o.#",
	"#.#.#.#,,,,,#...#",
	"#.....#,O,,,#.###",
	"#####.#,,,,,....#",
	"#.......,,O,#.o.#",
	"#.o.#.#,,,,,#...#",
	"#...#.#######.#.#",
	"#.o.....o.....#.#",
	"#.......#.......#",
	"#################",
]
const START := Vector2i(3, 15)
const ANOMALY := Vector2i(4, 13)
const SECRET_ROOM := Vector2i(13, 5)
const DOOR_FRONT := Vector2i(13, 6)
const DOOR_WIDTH := 1.2
const DOOR_HEIGHT := 2.2

## 상호작용 물체 배치: id -> [칸, 종류]
const PROPS := {
	"note1": [Vector2i(4, 15), "note"],
	"note2": [Vector2i(5, 7), "note"],
	"pack": [Vector2i(1, 1), "pack"],
	"note4": [Vector2i(1, 11), "note"],
	"note5": [Vector2i(12, 10), "note"],
	"phone": [Vector2i(15, 12), "phone"],
	"note6": [Vector2i(13, 5), "note"],
}

var size := Vector2i(17, 17)
var materials: Array[ShaderMaterial] = []
var light_tex: ImageTexture
var font: Font
var props := {}
var digit_labels := {}
var door_body: StaticBody3D
var door_pivot: Node3D
var anomaly_body: StaticBody3D
var anomaly_area: Area3D

var _shader := preload("res://shaders/backrooms.gdshader")


func _ready() -> void:
	font = load("res://fonts/GowunBatang-Subset.ttf")
	_build_light_map()
	_build_floor_ceiling()
	_build_walls()
	_build_pillars()
	_build_door()
	_build_props()
	_build_digits()


# --- 좌표 ---

func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func cell_center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, y, (c.y + 0.5) * CELL)


func tile(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return "#"
	return MAP[c.y][c.x]


func is_open(c: Vector2i) -> bool:
	return tile(c) in [".", ",", "o", "O"] or (c == SECRET_ROOM and G.has("door_open"))


func is_dark(c: Vector2i) -> bool:
	return tile(c) in [",", "O"]


## 너비 우선 탐색 최단 경로(시작 칸 제외, 도착 칸 포함). 기둥 칸은 통과 가능.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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


## 경로상의 칸 c를 지날 때 실제로 향할 지점. 기둥 칸은 기둥을 비켜 가장자리로 지난다.
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
			if is_open(Vector2i(x, y)) and Vector2i(x, y) != SECRET_ROOM:
				out.append(Vector2i(x, y))
	return out


# --- 재질 ---

func make_material(kind: int, color := Color.WHITE, anomaly := 0.0, emissive := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("anomaly", anomaly)
	m.set_shader_parameter("emissive", emissive)
	m.set_shader_parameter("light_map", light_tex)
	m.set_shader_parameter("map_size", Vector2(size))
	m.set_shader_parameter("cell", CELL)
	materials.append(m)
	return m


func set_shared(param: String, value) -> void:
	for m in materials:
		m.set_shader_parameter(param, value)


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
	# 벽 칸은 이웃한 바닥 칸의 밝기를 따라간다
	var sum := 0.0
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 1, h)
	fs.shape = box
	fs.position = Vector3(w / 2, -0.5, h / 2)
	floor_body.add_child(fs)
	add_child(floor_body)

	var ceil_mi := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	cm.size = Vector2(w, h)
	cm.flip_faces = true
	ceil_mi.mesh = cm
	ceil_mi.position = Vector3(w / 2, HEIGHT, h / 2)
	ceil_mi.material_override = make_material(2)
	add_child(ceil_mi)


## 벽 칸마다 바닥과 맞닿은 면만 모아 한 메시로 만든다. 충돌은 칸마다 상자.
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
			var target := anomaly_st if c == ANOMALY else st
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nt := tile(c + d)
				if nt == "#":
					continue
				if c + d == SECRET_ROOM or (c == SECRET_ROOM):
					continue
				_add_face(target, c, d)
			if c == ANOMALY:
				continue
			_add_box_collider(body, cell_center(c, HEIGHT / 2), Vector3(CELL, HEIGHT, CELL))
	# 빨간 문 뒤 방의 옆/뒷벽 (방 칸이 'R'이라 위 반복에서 빠진다)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		_add_face(st, SECRET_ROOM + d, -d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = make_material(0)
	add_child(mi)

	var ami := MeshInstance3D.new()
	ami.mesh = anomaly_st.commit()
	ami.material_override = make_material(0, Color.WHITE, 1.0)
	add_child(ami)
	anomaly_body = StaticBody3D.new()
	add_child(anomaly_body)
	_add_box_collider(anomaly_body, cell_center(ANOMALY, HEIGHT / 2), Vector3(CELL, HEIGHT, CELL))
	anomaly_area = Area3D.new()
	var s := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(CELL * 0.6, HEIGHT, CELL * 0.6)
	s.shape = b
	anomaly_area.add_child(s)
	anomaly_area.position = cell_center(ANOMALY, HEIGHT / 2)
	add_child(anomaly_area)


## 벽 칸 c에서 방향 d쪽(바닥 칸 쪽)을 보는 면.
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


func _add_box_collider(body: StaticBody3D, pos: Vector3, box_size: Vector3) -> void:
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


## 빨간 문: 방 칸과 문 앞 칸 사이 경계에 문틀 벽 + 문 + EXIT 표시 + 번호판.
func _build_door() -> void:
	var z := SECRET_ROOM.y * CELL + CELL
	var cx := (SECRET_ROOM.x + 0.5) * CELL
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
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		mi.material_override = wall_mat
		mi.position = spec[0]
		add_child(mi)
		_add_box_collider(frame, spec[0], spec[1])

	door_pivot = Node3D.new()
	door_pivot.position = Vector3(cx - DOOR_WIDTH / 2, 0, z)
	add_child(door_pivot)
	door_body = StaticBody3D.new()
	door_body.set_meta("id", "door")
	door_pivot.add_child(door_body)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.08)
	door.mesh = dm
	door.material_override = make_material(3, Color("8e1b1b"))
	door.position = Vector3(DOOR_WIDTH / 2, DOOR_HEIGHT / 2, 0)
	door_body.add_child(door)
	_add_box_collider(door_body, door.position, dm.size)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.05
	km.height = 0.1
	knob.mesh = km
	knob.material_override = make_material(3, Color("c9b27a"))
	knob.position = Vector3(DOOR_WIDTH - 0.12, 1.0, 0.07)
	door_body.add_child(knob)

	# EXIT 표시
	var sign_mi := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.7, 0.26, 0.06)
	sign_mi.mesh = sm
	sign_mi.material_override = make_material(3, Color("0b5e2a"), 0.0, 0.6)
	sign_mi.position = Vector3(cx, DOOR_HEIGHT + 0.3, z + 0.08)
	add_child(sign_mi)
	var exit_label := _label("EXIT", 64, Color("b8ffcf"))
	exit_label.position = Vector3(cx, DOOR_HEIGHT + 0.3, z + 0.115)
	add_child(exit_label)

	# 번호판 (상호작용은 문과 같다)
	var pad := StaticBody3D.new()
	pad.set_meta("id", "door")
	pad.collision_layer = 2
	add_child(pad)
	var pad_mi := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.16, 0.24, 0.05)
	pad_mi.mesh = pm
	pad_mi.material_override = make_material(3, Color("2a2a2a"), 0.0, 0.05)
	pad_mi.position = Vector3(cx + DOOR_WIDTH / 2 + 0.25, 1.3, z + 0.08)
	pad.add_child(pad_mi)
	_add_box_collider(pad, pad_mi.position, Vector3(0.4, 0.5, 0.2))


func open_door(animate := true) -> void:
	for c in door_body.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	if animate:
		create_tween().tween_property(door_pivot, "rotation:y", deg_to_rad(100), 1.6).set_trans(Tween.TRANS_SINE)
	else:
		door_pivot.rotation.y = deg_to_rad(100)


func set_anomaly_passable(passable: bool) -> void:
	for c in anomaly_body.get_children():
		c.disabled = passable


# --- 물체 ---

func _build_props() -> void:
	for id in PROPS:
		var c: Vector2i = PROPS[id][0]
		var kind: String = PROPS[id][1]
		var body := StaticBody3D.new()
		body.set_meta("id", id)
		# 조사용 충돌체는 2번 층: 플레이어(1번 층만 감지)는 통과하고, 터치 광선만 맞는다.
		body.collision_layer = 2
		body.position = cell_center(c)
		add_child(body)
		props[id] = body
		match kind:
			"note":
				var paper := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(0.28, 0.38)
				paper.mesh = pm
				paper.material_override = make_material(3, Color("e9e4d2"))
				paper.position = Vector3(0.35, 0.01, 0.4)
				paper.rotation.y = randf_range(-0.6, 0.6)
				body.add_child(paper)
				_add_box_collider(body, paper.position + Vector3(0, 0.15, 0), Vector3(0.8, 0.4, 0.8))
			"pack":
				var bag := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.4, 0.3)
				bag.mesh = bm
				bag.material_override = make_material(3, Color("2e3b4f"))
				bag.position = Vector3(-0.6, 0.2, -0.6)
				bag.rotation.y = 0.4
				body.add_child(bag)
				var torch := MeshInstance3D.new()
				var tm := CylinderMesh.new()
				tm.top_radius = 0.04
				tm.bottom_radius = 0.05
				tm.height = 0.25
				torch.mesh = tm
				torch.material_override = make_material(3, Color("444444"))
				torch.position = Vector3(-0.25, 0.05, -0.4)
				torch.rotation.z = PI / 2
				body.add_child(torch)
				_add_box_collider(body, Vector3(-0.5, 0.25, -0.5), Vector3(1.0, 0.6, 0.8))
			"phone":
				var table := MeshInstance3D.new()
				var tbm := BoxMesh.new()
				tbm.size = Vector3(0.8, 0.75, 0.6)
				table.mesh = tbm
				table.material_override = make_material(3, Color("4a3424"))
				table.position = Vector3(0.6, 0.375, 0.6)
				body.add_child(table)
				var phone := MeshInstance3D.new()
				var phm := BoxMesh.new()
				phm.size = Vector3(0.3, 0.12, 0.22)
				phone.mesh = phm
				phone.material_override = make_material(3, Color("6b1d1d"))
				phone.position = Vector3(0.6, 0.81, 0.6)
				body.add_child(phone)
				_add_box_collider(body, Vector3(0.6, 0.5, 0.6), Vector3(0.9, 1.0, 0.7))


## 숨은 숫자: 천장(위), 기둥 뒷면(뒤), 어둠 속 벽(어둠).
func _build_digits() -> void:
	var ceil_label := _label("7", 220, Color("7a1010"))
	ceil_label.position = cell_center(Vector2i(9, 1), HEIGHT - 0.01)
	ceil_label.rotation = Vector3(PI / 2, 0, 0)
	add_child(ceil_label)
	digit_labels["digit_ceiling"] = ceil_label

	var pillar := Vector2i(14, 7)
	var pl := _label("3", 150, Color("7a1010"))
	pl.position = cell_center(pillar, 1.6) + Vector3(0.41, 0, 0)
	pl.rotation = Vector3(0, PI / 2, 0)
	add_child(pl)
	digit_labels["digit_pillar"] = pl

	var dark := _label("9", 200, Color("8c1414"))
	dark.position = Vector3((9 + 0.5) * CELL, 1.85, 13 * CELL - 0.01)
	dark.rotation = Vector3(0, PI, 0)
	add_child(dark)
	digit_labels["digit_dark"] = dark
	var scrawl := _label("그것은 어둠 속에서 웃는다", 46, Color("8c1414"))
	scrawl.position = Vector3(0, -0.55, 0)
	dark.add_child(scrawl)


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
