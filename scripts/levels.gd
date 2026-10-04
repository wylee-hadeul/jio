extends RefCounted
## 레벨 데이터와 맵 생성기. make(i)가 i번째 레벨의 레이아웃(맵, 물체, 퍼즐, 정답 순서)을 만든다.
## 같은 레벨은 항상 같은 시드로 만들어지므로 같이 하기에서도 모두 같은 맵을 본다.
##
## 레이아웃 칸 문자: '#' 벽, '.' 불 켜진 바닥, ',' 불 꺼진 바닥, 'o' 기둥, 'O' 어둠 속 기둥, 'R' 비밀 방

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 테마: 셰이더 모양 번호와 색. wall 0 벽지, 1 콘크리트, 2 타일, 3 녹슨 배관, 4 나무 판자, 5 페인트 벽
## floor 0 카펫, 1 콘크리트, 2 타일, 3 물, 4 철망 / ceil 0 형광등 판, 1 전구, 2 어두운 배관
const THEMES := {
	"yellow": {"wall": 0, "wall_a": Color(0.80, 0.72, 0.42), "floor": 0, "floor_a": Color(0.52, 0.45, 0.27),
		"ceil": 0, "ceil_a": Color(0.78, 0.76, 0.66), "light": Color(1.0, 0.97, 0.82), "fog": Color(0.30, 0.26, 0.12), "fog_far": 27.0},
	"concrete": {"wall": 1, "wall_a": Color(0.55, 0.54, 0.50), "floor": 1, "floor_a": Color(0.42, 0.41, 0.38),
		"ceil": 1, "ceil_a": Color(0.45, 0.44, 0.42), "light": Color(1.0, 0.88, 0.65), "fog": Color(0.12, 0.12, 0.12), "fog_far": 22.0},
	"pipes": {"wall": 3, "wall_a": Color(0.45, 0.25, 0.18), "floor": 4, "floor_a": Color(0.25, 0.22, 0.2),
		"ceil": 2, "ceil_a": Color(0.2, 0.15, 0.13), "light": Color(1.0, 0.55, 0.35), "fog": Color(0.18, 0.05, 0.03), "fog_far": 18.0},
	"electric": {"wall": 1, "wall_a": Color(0.32, 0.40, 0.34), "floor": 1, "floor_a": Color(0.25, 0.28, 0.25),
		"ceil": 2, "ceil_a": Color(0.2, 0.22, 0.2), "light": Color(0.75, 1.0, 0.8), "fog": Color(0.02, 0.06, 0.03), "fog_far": 20.0},
	"office": {"wall": 5, "wall_a": Color(0.72, 0.74, 0.72), "floor": 0, "floor_a": Color(0.33, 0.36, 0.42),
		"ceil": 0, "ceil_a": Color(0.82, 0.82, 0.8), "light": Color(0.92, 0.97, 1.0), "fog": Color(0.18, 0.2, 0.22), "fog_far": 26.0},
	"hotel": {"wall": 4, "wall_a": Color(0.45, 0.16, 0.14), "floor": 0, "floor_a": Color(0.42, 0.08, 0.08),
		"ceil": 1, "ceil_a": Color(0.55, 0.48, 0.38), "light": Color(1.0, 0.8, 0.55), "fog": Color(0.12, 0.03, 0.02), "fog_far": 22.0},
	"dark": {"wall": 0, "wall_a": Color(0.62, 0.55, 0.32), "floor": 0, "floor_a": Color(0.4, 0.34, 0.2),
		"ceil": 0, "ceil_a": Color(0.5, 0.48, 0.42), "light": Color(1.0, 0.95, 0.8), "fog": Color(0.0, 0.0, 0.0), "fog_far": 18.0},
	"pool": {"wall": 2, "wall_a": Color(0.86, 0.9, 0.92), "floor": 3, "floor_a": Color(0.55, 0.75, 0.82),
		"ceil": 1, "ceil_a": Color(0.85, 0.88, 0.9), "light": Color(0.9, 1.0, 1.0), "fog": Color(0.55, 0.65, 0.68), "fog_far": 30.0},
	"red": {"wall": 1, "wall_a": Color(0.5, 0.2, 0.18), "floor": 1, "floor_a": Color(0.3, 0.12, 0.1),
		"ceil": 1, "ceil_a": Color(0.3, 0.15, 0.13), "light": Color(1.0, 0.25, 0.2), "fog": Color(0.15, 0.0, 0.0), "fog_far": 20.0},
	"party": {"wall": 0, "wall_a": Color(0.9, 0.62, 0.68), "floor": 0, "floor_a": Color(0.55, 0.3, 0.4),
		"ceil": 0, "ceil_a": Color(0.85, 0.78, 0.8), "light": Color(1.0, 0.85, 0.9), "fog": Color(0.3, 0.12, 0.18), "fog_far": 24.0},
	"parking": {"wall": 1, "wall_a": Color(0.5, 0.5, 0.52), "floor": 1, "floor_a": Color(0.3, 0.3, 0.32),
		"ceil": 1, "ceil_a": Color(0.38, 0.38, 0.4), "light": Color(0.85, 0.95, 1.0), "fog": Color(0.05, 0.06, 0.08), "fog_far": 26.0},
	"moss": {"wall": 1, "wall_a": Color(0.36, 0.45, 0.28), "floor": 0, "floor_a": Color(0.25, 0.33, 0.18),
		"ceil": 1, "ceil_a": Color(0.3, 0.34, 0.26), "light": Color(0.85, 1.0, 0.7), "fog": Color(0.08, 0.12, 0.05), "fog_far": 22.0},
	"school": {"wall": 5, "wall_a": Color(0.62, 0.72, 0.62), "floor": 2, "floor_a": Color(0.55, 0.52, 0.45),
		"ceil": 0, "ceil_a": Color(0.8, 0.8, 0.76), "light": Color(1.0, 0.98, 0.9), "fog": Color(0.15, 0.17, 0.14), "fog_far": 26.0},
	"hospital": {"wall": 2, "wall_a": Color(0.8, 0.84, 0.82), "floor": 2, "floor_a": Color(0.6, 0.64, 0.62),
		"ceil": 0, "ceil_a": Color(0.82, 0.84, 0.84), "light": Color(0.85, 1.0, 0.95), "fog": Color(0.1, 0.13, 0.12), "fog_far": 24.0},
}

## 레벨 목록. puzzle: code/keys/levers/lights/count/doors/chase/balloons/noclip
## spots(code): ceiling 위, pillar 뒤, phone 목소리, dark 어둠, floor 아래, behind 처음
const DEFS := [
	{},  # 0은 손으로 만든 맵 (level0)
	{"name": "LEVEL 1", "title": "창고", "theme": "concrete", "size": 17, "seed": 101, "loops": 0.18, "rooms": 3, "pillars": 0.25, "dark": 2,
		"puzzle": "keys", "n": 2, "entity": {"count": 1, "speed": 1.9},
		"intro": ["벽을 통과하자 차가운 콘크리트 냄새가 났다.\n천장에는 알전구가 흔들린다."],
		"notes": ["레벨 1.\n여긴 그나마 살 만하대.\n상자마다 아몬드 물이 있다던데\n전부 비어 있었어.\n\n- 지수"]},
	{"name": "LEVEL 2", "title": "파이프 복도", "theme": "pipes", "size": 17, "seed": 202, "loops": 0.06, "rooms": 1, "pillars": 0.0, "dark": 2,
		"puzzle": "levers", "n": 3, "entity": {"count": 1, "speed": 2.2},
		"intro": ["뜨겁다. 배관에서 김이 샌다.\n멀리서 쇠가 부딪히는 소리."],
		"notes": ["숨이 막혀.\n배관 소리가 꼭 누가 따라오는 발소리 같아.\n\n- 지수"]},
	{"name": "LEVEL 3", "title": "전기실", "theme": "electric", "size": 17, "seed": 303, "loops": 0.2, "rooms": 2, "pillars": 0.15, "dark": 1,
		"puzzle": "lights", "n": 3, "entity": {"count": 1, "speed": 1.9},
		"intro": ["윙- 하는 소리가 머리를 울린다.\n초록빛 전등 아래, 차단기 상자들."],
		"notes": ["불을 끄면 보이는 것들이 있어.\n레벨 0에서 배웠잖아.\n\n- 지수"]},
	{"name": "LEVEL 4", "title": "빈 사무실", "theme": "office", "size": 19, "seed": 404, "loops": 0.3, "rooms": 4, "pillars": 0.3, "dark": 2,
		"puzzle": "count", "entity": {"count": 1, "speed": 2.0},
		"intro": ["끝없는 칸막이 사무실.\n모니터는 꺼져 있는데, 누가 방금까지 앉아 있던 것 같다."],
		"notes": ["누가 여기서 일했던 걸까.\n책상마다 같은 메모가 붙어 있어.\n「퇴근하지 마세요」\n\n- 지수"]},
	{"name": "LEVEL 5", "title": "호텔 복도", "theme": "hotel", "size": 19, "seed": 505, "loops": 0.08, "rooms": 1, "pillars": 0.0, "dark": 2,
		"puzzle": "doors", "n": 5, "entity": {"count": 1, "speed": 2.0},
		"intro": ["붉은 카펫. 똑같은 문들.\n어느 방에서 텔레비전 소리가 새어 나온다."],
		"notes": ["틀린 문을 열면 처음으로 돌아가.\n세 번 돌아갔어.\n네 번째는 무서워서 못 열겠어.\n\n- 지수"]},
	{"name": "LEVEL 6", "title": "불 꺼진 층", "theme": "dark", "size": 17, "seed": 606, "loops": 0.2, "rooms": 2, "pillars": 0.2, "dark": 0, "all_dark": true,
		"puzzle": "code", "spots": ["floor", "dark", "phone", "dark"], "entity": {"count": 2, "speed": 1.8},
		"intro": ["여기도 노란 방이다.\n그런데 형광등이 하나도 켜져 있지 않다."],
		"notes": ["손전등 배터리가 얼마나 남았지.\n그것들은 어둠 속에서 더 빨라.\n\n- 지수"]},
	{"name": "LEVEL 37", "title": "수영장 방", "theme": "pool", "size": 19, "seed": 3737, "loops": 0.35, "rooms": 5, "pillars": 0.2, "dark": 0,
		"puzzle": "code", "spots": ["ceiling", "pillar", "floor"], "mirror": true, "entity": {"count": 0},
		"intro": ["하얀 타일, 찰랑이는 물소리.\n이상하게 마음이 편해진다.\n...그래서 더 무섭다."],
		"notes": ["여기선 아무것도 쫓아오지 않아.\n그런데 자꾸 누가 수영장 바닥에서\n나를 올려다보는 것 같아.\n\n- 지수"]},
	{"name": "LEVEL !", "title": "도망쳐", "theme": "red", "size": 19, "seed": 1111, "loops": 0.1, "rooms": 1, "pillars": 0.0, "dark": 1,
		"puzzle": "chase", "entity": {"count": 1, "speed": 2.3, "mode": "chase"},
		"intro": ["사이렌. 붉은 비상등.\n뒤에서 무언가 달려오는 소리가 난다.\n\n뛰어."],
		"notes": []},
	{"name": "LEVEL FUN", "title": "파티 =)", "theme": "party", "size": 17, "seed": 7777, "loops": 0.25, "rooms": 3, "pillars": 0.2, "dark": 1,
		"puzzle": "balloons", "n": 5, "entity": {"count": 2, "speed": 1.9},
		"intro": ["「파티에 온 걸 환영해! =)」\n벽에 삐뚤빼뚤한 글씨.\n풍선이 둥둥 떠 있다."],
		"notes": ["웃는 얼굴들이 파티에 초대했어.\n절대 대답하지 마.\n\n- 지수"]},
	{"name": "LEVEL 10", "title": "지하 주차장", "theme": "parking", "size": 19, "seed": 1010, "loops": 0.35, "rooms": 3, "pillars": 0.35, "dark": 2,
		"puzzle": "code", "spots": ["behind", "pillar", "ceiling", "dark"], "entity": {"count": 2, "speed": 2.0},
		"intro": ["차 한 대 없는 주차장.\n바닥의 화살표가 전부 벽을 가리킨다."],
		"notes": ["여기까지 온 사람은 별로 없대.\n나는 몇 번째로 여기 온 걸까.\n\n- 지수"]},
	{"name": "LEVEL 11", "title": "이끼 낀 방", "theme": "moss", "size": 19, "seed": 1112, "loops": 0.2, "rooms": 3, "pillars": 0.2, "dark": 3,
		"puzzle": "keys", "n": 3, "entity": {"count": 2, "speed": 2.0},
		"intro": ["벽지 위로 이끼가 번져 있다.\n축축하고, 숨 쉬는 것 같은 벽."],
		"notes": ["벽이 숨을 쉬어.\n귀를 대 보면 누가 안에서 속삭여.\n「나가지 마」\n\n- 지수"]},
	{"name": "LEVEL 12", "title": "학교 복도", "theme": "school", "size": 19, "seed": 1213, "loops": 0.1, "rooms": 2, "pillars": 0.0, "dark": 2,
		"puzzle": "doors", "n": 6, "entity": {"count": 2, "speed": 2.0},
		"intro": ["종소리가 울린다.\n아무도 없는 교실들, 칠판에 적힌 같은 문장.\n「나가는 문은 하나뿐」"],
		"notes": ["칠판마다 내 이름이 적혀 있었어.\n지각한 학생 명단에.\n\n- 지수"]},
	{"name": "LEVEL 13", "title": "병원", "theme": "hospital", "size": 19, "seed": 1313, "loops": 0.2, "rooms": 3, "pillars": 0.15, "dark": 2,
		"puzzle": "levers", "n": 4, "entity": {"count": 2, "speed": 2.2},
		"intro": ["소독약 냄새.\n바퀴 달린 침대가 혼자 굴러간다."],
		"notes": ["병실 침대에 누가 누워 있었어.\n얼굴을 보려고 했는데 시트가 비어 있었어.\n\n- 지수"]},
	{"name": "LEVEL 14", "title": "정전", "theme": "electric", "size": 19, "seed": 1414, "loops": 0.25, "rooms": 3, "pillars": 0.2, "dark": 3,
		"puzzle": "lights", "n": 4, "entity": {"count": 3, "speed": 1.8},
		"intro": ["이번엔 차단기가 네 개다.\n그리고 무언가 셋이 웃고 있다."],
		"notes": ["어둠이 출구고, 어둠이 그것들의 집이야.\n둘 다 맞아.\n\n- 지수"]},
	{"name": "LEVEL 15", "title": "끝없는 사무실", "theme": "office", "size": 21, "seed": 1515, "loops": 0.35, "rooms": 5, "pillars": 0.3, "dark": 3,
		"puzzle": "count", "entity": {"count": 3, "speed": 1.9},
		"intro": ["또 사무실.\n이번엔 책상 위에 내 사진이 놓여 있다."],
		"notes": ["사원증에 내 사진이 붙어 있었어.\n입사일은 내가 태어나기 전이야.\n\n- 지수"]},
	{"name": "LEVEL 16", "title": "붉은 방", "theme": "red", "size": 19, "seed": 1616, "loops": 0.2, "rooms": 3, "pillars": 0.2, "dark": 3,
		"puzzle": "code", "spots": ["dark", "phone", "ceiling", "dark"], "entity": {"count": 3, "speed": 2.1},
		"intro": ["모든 것이 붉다.\n심장 소리가 벽에서 들린다."],
		"notes": ["이제 거의 다 왔어.\n이상하지. 출구에 가까워질수록\n돌아가고 싶어져.\n\n- 지수"]},
	{"name": "LEVEL 17", "title": "거울 수영장", "theme": "pool", "size": 19, "seed": 1717, "loops": 0.3, "rooms": 4, "pillars": 0.25, "dark": 2,
		"puzzle": "code", "spots": ["floor", "dark", "pillar", "ceiling"], "mirror": true, "entity": {"count": 1, "speed": 2.0},
		"intro": ["다시 수영장.\n물에 비친 내가 나보다 조금 늦게 움직인다."],
		"notes": ["물속의 나한테 말을 걸었어.\n대답했어.\n「먼저 가」\n\n- 지수"]},
	{"name": "LEVEL ?", "title": "노란 방, 다시", "theme": "yellow", "size": 17, "seed": 9999, "loops": 0.25, "rooms": 3, "pillars": 0.3, "dark": 1,
		"puzzle": "noclip", "final": true, "entity": {"count": 2, "speed": 2.0},
		"intro": ["노란 벽지. 축축한 카펫. 형광등 소리.\n...처음 그 방이다."],
		"notes": ["또 여기야.\n처음 떨어진 그 방.\n\n이번엔 알아.\n어긋난 벽 앞에서 눈을 감고 걸으면 돼.\n\n그리고 이걸 읽는 너.\n글씨를 잘 봐.\n이건 네 글씨야."]},
]

const SPOT_WORD := {"ceiling": "위", "pillar": "뒤", "phone": "목소리", "dark": "어둠", "floor": "아래", "behind": "처음"}
const DECOR_NAMES := {"cooler": "정수기", "chair": "의자"}


static func count() -> int:
	return DEFS.size()


static func level_name(i: int) -> String:
	if i == 0:
		return "LEVEL 0"
	return DEFS[clampi(i, 1, DEFS.size() - 1)].name


static func make(index: int) -> Dictionary:
	if index == 0:
		return _level0()
	return _generate(index, DEFS[index])


# --- 레벨 0 (손으로 만든 맵) ---

static func _level0() -> Dictionary:
	var map := [
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
	var notes: Dictionary = G.NOTES
	var props: Array = []
	for id in ["note1", "note2", "note4", "note5", "note6"]:
		var cell: Vector2i = {"note1": Vector2i(4, 15), "note2": Vector2i(5, 7), "note4": Vector2i(1, 11),
			"note5": Vector2i(12, 10), "note6": Vector2i(13, 5)}[id]
		props.append({"id": id, "kind": "note", "cell": cell, "dir": Vector2i.ZERO, "data": {"text": notes[id]}})
	props.append({"id": "pack", "kind": "pack", "cell": Vector2i(1, 1), "dir": Vector2i.ZERO, "data": {"note": "note3", "text": notes["note3"]}})
	props.append({"id": "phone", "kind": "phone", "cell": Vector2i(15, 12), "dir": Vector2i.ZERO,
		"data": {"digit": "digit_phone", "value": "5", "lines": G.PHONE_LINES}})
	props.append({"id": "door", "kind": "room_door", "cell": Vector2i(13, 6), "dir": Vector2i(0, -1), "data": {"code": "7359"}})
	var digits := [
		{"key": "digit_ceiling", "kind": "ceiling", "cell": Vector2i(9, 1), "dir": Vector2i.ZERO, "value": "7", "view": Vector2i(9, 2)},
		{"key": "digit_pillar", "kind": "pillar", "cell": Vector2i(14, 7), "dir": Vector2i(1, 0), "value": "3", "view": Vector2i(15, 7)},
		{"key": "digit_dark", "kind": "dark", "cell": Vector2i(9, 12), "dir": Vector2i(0, 1), "value": "9", "view": Vector2i(9, 12),
			"scrawl": "그것은 어둠 속에서 웃는다"},
	]
	var steps := [
		{"do": "interact", "id": "note1"}, {"do": "interact", "id": "note2"}, {"do": "interact", "id": "pack"},
		{"do": "gaze", "key": "digit_ceiling"}, {"do": "gaze", "key": "digit_pillar"},
		{"do": "interact", "id": "phone"}, {"do": "gaze", "key": "digit_dark"},
		{"do": "interact", "id": "note5"}, {"do": "interact", "id": "note4"},
		{"do": "keypad", "id": "door", "code": "7359"}, {"do": "interact", "id": "note6"},
		{"do": "noclip"},
	]
	return {
		"index": 0, "name": "LEVEL 0", "title": "노란 방", "theme": THEMES["yellow"], "map": map,
		"start": Vector2i(3, 15), "start_yaw": 0.0, "props": props, "digits": digits,
		"anomaly": Vector2i(4, 13), "anomaly_front": Vector2i(4, 14), "secret_room": Vector2i(13, 5),
		"exit": {"kind": "noclip", "needs": ["note6"]},
		"entity": {"count": 1, "speed": 1.9, "mode": "weeping", "spawn": "note2"},
		"intro": G.INTRO, "hints": G.HINTS, "solution": steps, "final": false, "code": "7359",
	}


# --- 생성기 ---

static func _generate(index: int, d: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var w: int = d.size
	var h: int = d.size
	var g := _maze(rng, w, h, float(d.get("loops", 0.2)), int(d.get("rooms", 2)))
	_add_pillars(rng, g, float(d.get("pillars", 0.2)))
	if d.get("all_dark", false):
		for y in h:
			for x in w:
				if g[y][x] == ".":
					g[y][x] = ","
				elif g[y][x] == "o":
					g[y][x] = "O"
	else:
		for i in int(d.get("dark", 1)):
			_dark_blob(rng, g, rng.randi_range(2, 3))

	var ctx := {"g": g, "rng": rng, "used": {}, "w": w, "h": h}
	# 시작: 벽을 등지고, 앞으로 길게 트인 칸 (어두운 레벨이면 불 꺼진 칸도 가능)
	var start_pick: Dictionary = _pick_start(ctx, not d.get("all_dark", false))
	var start: Vector2i = start_pick.cell
	var back: Vector2i = start_pick.dir
	ctx.start = start
	ctx.dist = _distances(g, start)
	ctx.used[start] = true
	var start_yaw := atan2(float(back.x), float(back.y))  # 등진 벽의 반대쪽을 본다

	var props: Array = []
	var digits: Array = []
	var steps: Array = []
	var notes_text: Array = d.get("notes", [])
	var puzzle: String = d.puzzle
	var exit := {"kind": "door", "needs": []}
	var code := ""
	var hints: Array = []
	var clue := ""

	match puzzle:
		"code":
			var spots: Array = d.spots
			var words: Array = []
			var values: Array = []
			for i in spots.size():
				var kind: String = spots[i]
				var v := str(rng.randi_range(1, 9))
				values.append(v)
				words.append(SPOT_WORD[kind])
				var key := "digit_%d" % i
				if kind == "phone":
					var p := _pick(ctx, {"lit": not d.get("all_dark", false), "wall": true, "min": 4})
					props.append({"id": "phone", "kind": "phone", "cell": p.cell, "dir": p.dir, "data": {"digit": key, "value": v,
						"lines": ["(지지직...)", "「...들려요? 숫자를 불러 줄게요.」", "「%s.」" % _num_word(v), "「...%s. 잊지 마요.」" % _num_word(v), "(뚝.)"]}})
					steps.append({"do": "interact", "id": "phone"})
					hints.append([key, "어디선가 전화벨이 울린다. 소리를 따라가 받아 보자."])
				else:
					digits.append(_make_digit(ctx, key, kind, v, start, back, d.get("mirror", false)))
					steps.append({"do": "gaze", "key": key})
					hints.append([key, _spot_hint(kind)])
			code = "".join(values)
			if d.get("mirror", false):
				code = "".join(_reversed(values))
				clue = "숫자는 %d개. 찾는 순서는 %s.\n\n그런데 여기 숫자들은 전부 물에 비친 모습이야.\n거울 속에선 순서도 뒤집혀.\n마지막에 찾은 것부터 적어." % [spots.size(), ", ".join(words)]
			else:
				clue = "숫자는 %d개.\n순서는 %s.\n\n여기 사람들은 앞만 봐." % [spots.size(), ", ".join(words)]
			exit = {"kind": "door", "needs": [], "code": code}
		"keys":
			var n: int = d.n
			for i in n:
				var p := _pick(ctx, {"dark": i == 0 and _has_dark(g), "min": 3})
				props.append({"id": "key_%d" % i, "kind": "key", "cell": p.cell, "dir": Vector2i.ZERO, "data": {}})
				steps.append({"do": "interact", "id": "key_%d" % i})
				exit.needs.append("key_%d" % i)
			clue = "출구 문은 열쇠 %d개로 잠겨 있어.\n하나는 불 꺼진 곳에 떨어뜨렸어.\n반짝이는 걸 찾아." % n
			hints.append(["key_0", "열쇠가 반짝인다. 어두운 곳은 손전등으로 비춰 보자."])
		"levers":
			var n: int = d.n
			for i in n:
				var p := _pick(ctx, {"wall": true, "dark": i == 0 and _has_dark(g), "min": 3})
				props.append({"id": "lever_%d" % i, "kind": "lever", "cell": p.cell, "dir": p.dir, "data": {}})
				steps.append({"do": "interact", "id": "lever_%d" % i})
				exit.needs.append("lever_%d" % i)
			exit.kind = "elevator"
			clue = "밸브 %d개를 전부 돌려야\n승강기에 전기가 들어와.\n승강기 옆 숫자가 다 차면 가." % n
			hints.append(["lever_0", "벽의 밸브를 찾아 돌리자. 승강기 옆 숫자가 남은 개수다."])
		"lights":
			var n: int = d.n
			for i in n:
				var p := _pick(ctx, {"wall": true, "lit": true, "min": 3})
				props.append({"id": "breaker_%d" % i, "kind": "breaker", "cell": p.cell, "dir": p.dir, "data": {}})
				steps.append({"do": "interact", "id": "breaker_%d" % i})
				exit.needs.append("breaker_%d" % i)
			exit.kind = "hatch"
			clue = "차단기 %d개를 전부 내려.\n완전히 어두워지면\n천장에서 빛나는 게 보일 거야.\n손전등은 꺼 두는 게 좋아." % n
			hints.append(["breaker_0", "차단기를 모두 내리면 어둠 속에서 천장의 출구가 빛난다."])
		"count":
			var a := rng.randi_range(3, 7)
			var b := rng.randi_range(2, 6)
			for i in a:
				var p := _pick(ctx, {"dark": i == 0 and _has_dark(g), "min": 2})
				props.append({"id": "cooler_%d" % i, "kind": "cooler", "cell": p.cell, "dir": Vector2i.ZERO, "data": {}})
			for i in b:
				var p := _pick(ctx, {"dark": i == 0 and _has_dark(g), "min": 2})
				props.append({"id": "chair_%d" % i, "kind": "chair", "cell": p.cell, "dir": Vector2i.ZERO, "data": {}})
			code = "%d%d" % [a, b]
			exit = {"kind": "door", "needs": [], "code": code}
			clue = "출구 비밀번호는 두 자리.\n정수기의 수, 그다음 의자의 수.\n불 꺼진 곳까지 빠짐없이 세어."
			hints.append(["exit_open", "정수기와 의자를 세어 보자. 어두운 구석에도 숨어 있다."])
		"doors":
			var n: int = d.n
			var nums := _door_numbers(rng, n)
			var riddle: Array = _door_riddle(rng, nums)
			var answer: int = riddle[1]
			for i in n:
				var p := _pick(ctx, {"wall": true, "min": 3})
				props.append({"id": "numdoor_%d" % i, "kind": "numdoor", "cell": p.cell, "dir": p.dir,
					"data": {"number": nums[i], "correct": nums[i] == answer}})
				if nums[i] == answer:
					steps.append({"do": "interact", "id": "numdoor_%d" % i})
			exit.kind = "numdoor"
			clue = "문 %d개 중 출구는 하나.\n%s\n\n틀리면 처음으로 돌아가." % [n, riddle[0]]
			hints.append(["exit_open", riddle[0]])
		"chase":
			clue = ""
			hints.append(["exit_open", "뛰어. 초록 EXIT까지. 멈추면 잡힌다."])
		"balloons":
			var n: int = d.n
			for i in n:
				var p := _pick(ctx, {"dark": i == 0 and _has_dark(g), "min": 3})
				props.append({"id": "balloon_%d" % i, "kind": "balloon", "cell": p.cell, "dir": Vector2i.ZERO, "data": {}})
				steps.append({"do": "interact", "id": "balloon_%d" % i})
				exit.needs.append("balloon_%d" % i)
			clue = "풍선 %d개를 전부 터뜨리면\n파티가 끝나고 문이 열린대.\n\n웃는 애들이 쳐다보면, 너도 쳐다봐." % n
			hints.append(["balloon_0", "풍선을 모두 터뜨리자. 문 옆 숫자가 남은 개수다."])
		"noclip":
			exit.kind = "noclip"
			hints.append(["escaped", "무늬가 반 칸 어긋난 벽을 찾아, 그 앞에서 눈을 감고 걸어 들어가자."])

	# 출구: 시작에서 가장 먼 곳
	var anomaly := Vector2i(-1, -1)
	var anomaly_front := Vector2i(-1, -1)
	match exit.kind:
		"door", "elevator":
			var p := _pick(ctx, {"wall": true, "far": true, "inner_wall": true})
			props.append({"id": "exit", "kind": "exit_door" if exit.kind == "door" else "elevator", "cell": p.cell, "dir": p.dir,
				"data": {"code": exit.get("code", ""), "needs": exit.needs, "count": exit.needs.size()}})
			if exit.get("code", "") != "":
				steps.append({"do": "keypad", "id": "exit", "code": exit.code})
			steps.append({"do": "interact", "id": "exit"})
		"hatch":
			var p := _pick(ctx, {"far": true})
			props.append({"id": "exit", "kind": "hatch", "cell": p.cell, "dir": Vector2i.ZERO, "data": {"needs": exit.needs}})
			steps.append({"do": "interact", "id": "exit"})
		"noclip":
			var p := _pick(ctx, {"wall": true, "far": true, "inner_wall": true, "lit": true})
			anomaly_front = p.cell
			anomaly = p.cell + p.dir
			steps.append({"do": "noclip"})
	if puzzle == "chase":
		var arrows := _route(g, start, (props.back() as Dictionary).cell) if not props.is_empty() else []
		props.append({"id": "arrows", "kind": "arrows", "cell": start, "dir": Vector2i.ZERO, "data": {"route": arrows}})

	# 쪽지: 단서 쪽지는 시작 가까이, 이야기 쪽지는 흩어 놓는다
	var note_ids: Array = []
	if clue != "":
		var p := _pick(ctx, {"lit": not d.get("all_dark", false), "near": true})
		props.append({"id": "note_clue", "kind": "note", "cell": p.cell, "dir": Vector2i.ZERO, "data": {"text": clue + "\n\n- 지수"}})
		note_ids.append("note_clue")
	for i in notes_text.size():
		var p := _pick(ctx, {"min": 2, "near": i == 0 and clue == ""})
		props.append({"id": "note_%d" % i, "kind": "note", "cell": p.cell, "dir": Vector2i.ZERO, "data": {"text": notes_text[i]}})
		note_ids.append("note_%d" % i)
	if not note_ids.is_empty():
		steps.push_front({"do": "interact", "id": note_ids[0]})
		hints.push_front([note_ids[0], "근처에 쪽지가 있다. 바닥을 살펴보자."])
	if exit.kind == "noclip":
		hints.push_front(["note_0", "근처의 쪽지를 읽자."])

	var e: Dictionary = d.get("entity", {})
	var map: Array = []
	for row in g:
		map.append("".join(row))
	return {
		"index": index, "name": d.name, "title": d.title, "theme": THEMES[d.theme], "map": map,
		"start": start, "start_yaw": start_yaw, "props": props, "digits": digits,
		"anomaly": anomaly, "anomaly_front": anomaly_front, "secret_room": Vector2i(-1, -1),
		"exit": exit,
		"entity": {"count": int(e.get("count", 0)), "speed": float(e.get("speed", 1.9)), "mode": e.get("mode", "weeping"),
			"spawn": "start" if e.get("mode", "weeping") == "chase" else "note"},
		"intro": d.intro, "hints": hints, "solution": steps, "final": d.get("final", false), "code": code,
	}


## 등 뒤(dir)는 벽, 앞(-dir)은 가장 길게 트인 칸을 고른다.
static func _pick_start(ctx: Dictionary, lit: bool) -> Dictionary:
	var g: Array = ctx.g
	var best := {"cell": Vector2i(1, 1), "dir": Vector2i(-1, 0)}
	var best_run := -1.0
	for y in range(1, ctx.h - 1):
		for x in range(1, ctx.w - 1):
			var t: String = g[y][x]
			if not (t == "." or (not lit and t == ",")):
				continue
			for d in DIRS:
				var c := Vector2i(x, y)
				if g[y + d.y][x + d.x] != "#":
					continue
				var run := 0
				var n: Vector2i = c - d
				while _walkable(g, n):
					run += 1
					n -= d
				var score: float = run + ctx.rng.randf() * 0.5
				if score > best_run:
					best_run = score
					best = {"cell": c, "dir": d}
	return best


static func _maze(rng: RandomNumberGenerator, w: int, h: int, loops: float, rooms: int) -> Array:
	var g: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append("#")
		g.append(row)
	var stack: Array = [Vector2i(1, 1)]
	g[1][1] = "."
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array = []
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var n: Vector2i = c + d
			if n.x > 0 and n.y > 0 and n.x < w - 1 and n.y < h - 1 and g[n.y][n.x] == "#":
				opts.append(d)
		if opts.is_empty():
			stack.pop_back()
			continue
		var d: Vector2i = opts[rng.randi() % opts.size()]
		g[c.y + d.y / 2][c.x + d.x / 2] = "."
		g[c.y + d.y][c.x + d.x] = "."
		stack.append(c + d)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if g[y][x] != "#":
				continue
			var horiz: bool = g[y][x - 1] == "." and g[y][x + 1] == "."
			var vert: bool = g[y - 1][x] == "." and g[y + 1][x] == "."
			if (horiz or vert) and rng.randf() < loops:
				g[y][x] = "."
	for i in rooms:
		var rw := rng.randi_range(2, 4)
		var rh := rng.randi_range(2, 4)
		var rx := rng.randi_range(1, w - 1 - rw)
		var ry := rng.randi_range(1, h - 1 - rh)
		for y in range(ry, ry + rh):
			for x in range(rx, rx + rw):
				g[y][x] = "."
	return g


static func _add_pillars(rng: RandomNumberGenerator, g: Array, chance: float) -> void:
	var h := g.size()
	var w: int = g[0].size()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if g[y][x] != ".":
				continue
			var all_open := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if g[y + dy][x + dx] == "#" or g[y + dy][x + dx] == "o":
						if not (dx == 0 and dy == 0):
							all_open = false
			if all_open and rng.randf() < chance:
				g[y][x] = "o"


static func _dark_blob(rng: RandomNumberGenerator, g: Array, radius: int) -> void:
	var cells: Array = []
	for y in g.size():
		for x in g[0].size():
			if g[y][x] == ".":
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return
	var c: Vector2i = cells[rng.randi() % cells.size()]
	for y in range(c.y - radius, c.y + radius + 1):
		for x in range(c.x - radius, c.x + radius + 1):
			if y <= 0 or x <= 0 or y >= g.size() - 1 or x >= g[0].size() - 1:
				continue
			if absi(x - c.x) + absi(y - c.y) > radius:
				continue
			if g[y][x] == ".":
				g[y][x] = ","
			elif g[y][x] == "o":
				g[y][x] = "O"


static func _has_dark(g: Array) -> bool:
	for row in g:
		if "," in row:
			return true
	return false


static func _distances(g: Array, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if _walkable(g, n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist


static func _route(g: Array, from: Vector2i, to: Vector2i) -> Array:
	var prev := {from: from}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if _walkable(g, n) and not prev.has(n):
				prev[n] = c
				q.append(n)
	var out: Array = []
	var cur := to
	while prev.has(cur) and cur != from:
		out.push_front(cur)
		cur = prev[cur]
	return out


static func _walkable(g: Array, c: Vector2i) -> bool:
	if c.y < 0 or c.x < 0 or c.y >= g.size() or c.x >= g[0].size():
		return false
	return g[c.y][c.x] in [".", ",", "o", "O"]


## 조건에 맞는 칸 고르기. opts: lit/dark(bool), wall(벽 붙은 칸, dir 반환), min(시작에서 최소 거리),
## far(가장 먼 쪽), near(가까운 쪽), inner_wall(맵 바깥 테두리가 아닌 벽), spread(다른 물체와 떨어지게, 기본 true)
static func _pick(ctx: Dictionary, opts: Dictionary) -> Dictionary:
	var g: Array = ctx.g
	var rng: RandomNumberGenerator = ctx.rng
	var dist: Dictionary = ctx.get("dist", {})
	var cands: Array = []
	for y in range(1, ctx.h - 1):
		for x in range(1, ctx.w - 1):
			var c := Vector2i(x, y)
			var t: String = g[y][x]
			if not t in [".", ","]:
				continue
			if ctx.used.has(c):
				continue
			if opts.get("lit", false) and t != ".":
				continue
			if opts.get("dark", false) and t != ",":
				continue
			if not dist.is_empty():
				if not dist.has(c):
					continue
				if dist[c] < int(opts.get("min", 0)):
					continue
			var dirs: Array = []
			if opts.get("wall", false):
				for d in DIRS:
					var n: Vector2i = c + d
					if g[n.y][n.x] != "#":
						continue
					if opts.get("inner_wall", false) and (n.x == 0 or n.y == 0 or n.x == ctx.w - 1 or n.y == ctx.h - 1):
						continue
					dirs.append(d)
				if dirs.is_empty():
					continue
			cands.append({"cell": c, "dir": dirs[rng.randi() % dirs.size()] if not dirs.is_empty() else Vector2i.ZERO})
	if cands.is_empty():
		# 조건을 완화해서 다시
		var relaxed := opts.duplicate()
		for k in ["dark", "lit", "inner_wall", "min"]:
			if relaxed.has(k):
				relaxed.erase(k)
				return _pick(ctx, relaxed)
		return {"cell": ctx.get("start", Vector2i(1, 1)), "dir": Vector2i(-1, 0)}
	var chosen: Dictionary
	if opts.get("far", false) and not dist.is_empty():
		cands.sort_custom(func(a, b): return dist[a.cell] > dist[b.cell])
		chosen = cands[rng.randi() % mini(3, cands.size())]
	elif opts.get("near", false) and not dist.is_empty():
		cands.sort_custom(func(a, b): return dist[a.cell] < dist[b.cell])
		chosen = cands[rng.randi() % mini(3, cands.size())]
	elif opts.get("spread", true) and not ctx.used.is_empty():
		# 이미 놓인 물체들과 가장 먼 후보들 중에서
		for cand in cands:
			var best := 999
			for u in ctx.used:
				best = mini(best, absi(cand.cell.x - u.x) + absi(cand.cell.y - u.y))
			cand.score = best + rng.randf()
		cands.sort_custom(func(a, b): return a.score > b.score)
		chosen = cands[rng.randi() % mini(4, cands.size())]
	else:
		chosen = cands[rng.randi() % cands.size()]
	ctx.used[chosen.cell] = true
	return chosen


static func _make_digit(ctx: Dictionary, key: String, kind: String, v: String, start: Vector2i, back: Vector2i, mirror: bool) -> Dictionary:
	var g: Array = ctx.g
	match kind:
		"ceiling", "floor":
			var p := _pick(ctx, {"lit": true, "min": 3})
			var view: Vector2i = p.cell
			for d in DIRS:
				if _walkable(g, p.cell + d) and not g[p.cell.y + d.y][p.cell.x + d.x] in ["o", "O"]:
					view = p.cell + d
					break
			return {"key": key, "kind": kind, "cell": p.cell, "dir": Vector2i.ZERO, "value": v, "view": view, "mirror": mirror}
		"pillar":
			var pillars: Array = []
			for y in g.size():
				for x in g[0].size():
					var c := Vector2i(x, y)
					if g[y][x] == "o" and not ctx.used.has(c):
						pillars.append(c)
			if pillars.is_empty():
				return _make_digit(ctx, key, "ceiling", v, start, back, mirror)
			var c: Vector2i = pillars[ctx.rng.randi() % pillars.size()]
			ctx.used[c] = true
			# 시작점에서 더 먼 쪽 면 = '뒤'
			var dist: Dictionary = ctx.dist
			var best := Vector2i(1, 0)
			var best_d := -1
			for d in DIRS:
				var n: Vector2i = c + d
				if dist.has(n) and dist[n] > best_d and not g[n.y][n.x] in ["o", "O"]:
					best_d = dist[n]
					best = d
			return {"key": key, "kind": "pillar", "cell": c, "dir": best, "value": v, "view": c + best, "mirror": mirror}
		"dark":
			var p := _pick(ctx, {"dark": true, "wall": true, "min": 2})
			return {"key": key, "kind": "dark", "cell": p.cell, "dir": p.dir, "value": v, "view": p.cell, "mirror": mirror}
		"behind":
			return {"key": key, "kind": "behind", "cell": start, "dir": back, "value": v, "view": start, "mirror": mirror}
	return {}


static func _spot_hint(kind: String) -> String:
	return {
		"ceiling": "'위'. 천장 전체를 올려다보자. 화면 오른쪽을 위로 끌면 고개를 든다.",
		"pillar": "'뒤'. 기둥은 돌아서 뒤쪽 면까지 보자.",
		"dark": "'어둠'. 불 꺼진 곳의 벽을 손전등으로 비춰 보자.",
		"floor": "'아래'. 발밑을 보자. 화면 오른쪽을 아래로 끌면 고개를 숙인다.",
		"behind": "'처음'. 이 층에 처음 떨어졌을 때 등 뒤에 있던 벽을 보자.",
	}.get(kind, "")


static func _num_word(v: String) -> String:
	return ["영", "하나", "둘", "셋", "넷", "다섯", "여섯", "일곱", "여덟", "아홉"][int(v)]


static func _reversed(a: Array) -> Array:
	var b := a.duplicate()
	b.reverse()
	return b


static func _door_numbers(rng: RandomNumberGenerator, n: int) -> Array:
	var floor_no := rng.randi_range(2, 9)
	var nums: Array = []
	while nums.size() < n:
		var v := floor_no * 100 + rng.randi_range(1, 30)
		if not v in nums:
			nums.append(v)
	return nums


## 수수께끼 [문장, 답]. 답이 하나로 정해지는 문장만 고른다.
static func _door_riddle(rng: RandomNumberGenerator, nums: Array) -> Array:
	var tries: Array = []
	var sums := {}
	for v in nums:
		var s := 0
		for ch in str(v):
			s += int(ch)
		sums[v] = s
	for v in nums:
		var same := 0
		for u in nums:
			if sums[u] == sums[v]:
				same += 1
		if same == 1:
			tries.append(["출구 번호의 숫자를 모두 더하면 %d." % sums[v], v])
	var sorted := nums.duplicate()
	sorted.sort()
	tries.append(["출구는 두 번째로 큰 번호의 방.", sorted[sorted.size() - 2]])
	tries.append(["출구는 가장 작은 번호의 방.", sorted[0]])
	var odd: Array = nums.filter(func(v): return v % 2 == 1)
	if odd.size() == 1:
		tries.append(["출구 번호는 이 층에서 유일한 홀수.", odd[0]])
	return tries[rng.randi() % tries.size()]
