extends Node
## 진행 상태, 이야기 텍스트, 저장/불러오기. 오토로드 "G".

const SAVE_PATH := "user://save.json"
const AUTOPLAY_SAVE_PATH := "user://save_autoplay.json"
const EXIT_CODE := "7359"

const INTRO := [
	"평범한 퇴근길이었다.\n계단에서 발을 헛디딘 순간,\n세상이 노랗게 번졌다.",
	"눈을 뜨자 끝없이 이어진 노란 방.\n축축한 카펫 냄새.\n그리고 멈추지 않는 형광등 소리.",
	"왼쪽을 끌어 걷고, 오른쪽을 끌어 둘러본다.\n궁금한 것은 손가락으로 눌러 조사한다.",
]

const NOTES := {
	"note1": "여기는 레벨 0.\n\n형광등 소리가 갑자기 멈추면\n그게 가까이 있다는 뜻이야.\n\n뒤돌아보지 말고, 아니,\n꼭 뒤돌아봐.\n\n- 지수",
	"note2": "출구를 찾았어.\n초록색 EXIT 아래 빨간 문.\n\n문에는 숫자 네 개가 필요해.\n숫자는 이 층 곳곳에 숨겨 뒀어.\n\n순서는 위, 뒤, 목소리, 어둠.\n\n여기 사람들은 앞만 봐.\n\n- 지수",
	"note3": "배낭에 손전등을 두고 간다.\n\n그것은 내가 보고 있을 때는\n움직이지 않았어.\n\n눈을 감는 순간이 제일 무서워.\n절대 오래 감지 마.\n\n- 지수",
	"note4": "벽지가 어긋난 벽을 봤어.\n무늬가 반 칸쯤 밀려 있었어.\n\n처음 여기 떨어지던 날,\n계단도 그렇게 어긋나 보였는데.\n\n- 지수",
	"note5": "이게 몇 번째 쪽지일까.\n\n쓰면 쓸수록 글씨가 낯익어.\n누군가 내 글씨를 흉내 내는 것 같아.\n\n아니면 내가 누군가를...\n\n- 지수",
	"note6": "빨간 문 너머엔 아무것도 없었어.\n출구 표시는 미끼야.\n\n우리가 여기 어떻게 들어왔는지 기억해?\n발을 헛디뎌 벽을 통과했지.\n나가는 길도 똑같아.\n\n어긋난 벽 앞에서 눈을 감고, 걸어.\n\n그리고 이걸 읽는 너.\n글씨를 잘 봐.\n이건 네 글씨야.",
}

const PHONE_LINES := [
	"(지지직...)",
	"「...거기, 누구 있어요?」",
	"「여긴 계속 똑같은 방이에요. 몇 날 며칠을 걸었는지 모르겠어요.」",
	"「숫자... 숫자를 알려 줄게요. 다섯. 다섯이에요.」",
	"「그리고 빨간 문은 절대-」",
	"(뚝. 신호음조차 끊겼다.)",
]

const ENDING := [
	"벽 속으로 걸어 들어가는 순간,\n형광등 소리가 뚝 멎었다.",
	"눈을 뜨자 익숙한 천장이 보였다.\n내 방이다. 새벽 4시.",
	"손에 펜이 쥐어져 있다.\n책상 위에는 방금 쓴 듯한 쪽지 한 장.",
	"「여기는 레벨 0.\n형광등 소리가 갑자기 멈추면\n그게 가까이 있다는 뜻이야.」",
	"...지수.\n그건 내 이름이다.",
]

const CAUGHT_LINES := [
	"형광등 소리가 멈춰 있었다.",
	"당신은 노란 방의 일부가 되었다.",
]

## 진행 단계별 힌트. 앞에서부터 아직 안 끝난 첫 단계의 힌트를 보여 준다.
const HINTS := [
	["note1", "근처 바닥을 잘 살펴보자. 하얀 종이가 보인다."],
	["note2", "더 걸어 보자. 지수는 쪽지를 여러 장 남긴 것 같다."],
	["flashlight", "어둠 속을 보려면 빛이 필요하다. 막다른 방에 누군가 두고 간 배낭이 있을지도."],
	["digit_ceiling", "'위'. 형광등만 보지 말고 천장 전체를 올려다보자. 화면 오른쪽을 위로 끌면 고개를 든다."],
	["digit_pillar", "'뒤'. 기둥은 앞에서만 보면 한 면뿐이다. 돌아서 뒤쪽을 보자."],
	["digit_phone", "'목소리'. 어딘가에서 전화벨이 울린다. 소리를 따라가 보자."],
	["digit_dark", "'어둠'. 불이 꺼진 구역에서 손전등으로 벽을 비춰 보자."],
	["door_open", "숫자 순서는 위, 뒤, 목소리, 어둠. 초록 EXIT 아래 빨간 문에 입력하자."],
	["note6", "빨간 문 안쪽을 살펴보자."],
	["escaped", "쪽지 4에 나온 '무늬가 반 칸 밀린 벽'을 찾아, 그 앞에서 눈을 감은 채 걸어 보자."],
]

var flags := {}
## 마지막으로 쪽지를 읽은 위치. 잡히면 여기서 다시 시작한다.
var checkpoint := Vector3.ZERO
var checkpoint_yaw := 0.0
var save_path := SAVE_PATH
var autoplay := false


func _ready() -> void:
	autoplay = _autoplay_requested()
	if autoplay:
		save_path = AUTOPLAY_SAVE_PATH


static func _autoplay_requested() -> bool:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.search")).contains("autoplay")
	return "--autoplay" in OS.get_cmdline_user_args()


func has(key: String) -> bool:
	return flags.get(key, false)


func set_flag(key: String, value = true) -> void:
	flags[key] = value
	save_game()


func hint() -> String:
	for h in HINTS:
		if not has(h[0]):
			return h[1]
	return "이미 이곳을 벗어났다."


func digits_found() -> String:
	var s := ""
	for pair in [["digit_ceiling", "7"], ["digit_pillar", "3"], ["digit_phone", "5"], ["digit_dark", "9"]]:
		s += pair[1] if has(pair[0]) else "_"
	return s


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"flags": flags,
			"checkpoint": [checkpoint.x, checkpoint.y, checkpoint.z],
			"yaw": checkpoint_yaw,
		}))


func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	flags = data.get("flags", {})
	var c: Array = data.get("checkpoint", [0, 0, 0])
	checkpoint = Vector3(c[0], c[1], c[2])
	checkpoint_yaw = float(data.get("yaw", 0.0))
	return true


func reset() -> void:
	flags = {}
	checkpoint = Vector3.ZERO
	checkpoint_yaw = 0.0
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## 화면에 나오는 모든 문장. 폰트에 없는 글자가 있는지 테스트에서 검사한다.
func all_text() -> Array:
	var out: Array = []
	out.append_array(INTRO)
	out.append_array(NOTES.values())
	out.append_array(PHONE_LINES)
	out.append_array(ENDING)
	out.append_array(CAUGHT_LINES)
	for h in HINTS:
		out.append(h[1])
	return out
