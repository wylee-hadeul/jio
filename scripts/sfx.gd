extends Node
## 코드로 합성한 효과음. 오토로드 "Sfx". 시작 화면에서 build()를 한 번 호출한다.

const RATE := 16000
const LOOPS := ["hum", "drone", "heartbeat", "ring"]

var streams := {}
var loops := {}
var _pool: Array[AudioStreamPlayer] = []
var ready_built := false


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


## 프레임을 나눠 가며 합성해 웹에서도 멈춘 것처럼 보이지 않게 한다.
func build() -> void:
	if ready_built:
		return
	var gens := {
		"hum": _hum, "drone": _drone, "heartbeat": _heartbeat, "ring": _ring,
		"step": _step, "sting": _sting, "static": _static, "beep": _beep, "buzz": _buzz,
		"unlock": _unlock, "paper": _paper, "click": _click, "whoosh": _whoosh,
	}
	for key in gens:
		var data: PackedFloat32Array = gens[key].call()
		streams[key] = _to_wav(data, key in LOOPS)
		await get_tree().process_frame
	for key in LOOPS:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		p.volume_db = -80.0
		add_child(p)
		loops[key] = p
	ready_built = true


func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(key):
		return
	for p in _pool:
		if not p.playing:
			p.stream = streams[key]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## 반복 소리의 크기(0~1). 0이면 멈춘다.
func set_loop(key: String, amount: float) -> void:
	if not loops.has(key):
		return
	var p: AudioStreamPlayer = loops[key]
	if amount <= 0.001:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(amount)
	if not p.playing:
		p.play()


func stop_all() -> void:
	for key in loops:
		loops[key].stop()
	for p in _pool:
		p.stop()


# --- 합성 ---

func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a


## 형광등: 120Hz 버즈와 배음, 약간의 잡음. 2초 반복.
func _hum() -> PackedFloat32Array:
	var a := _buf(2.0)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var saw := fmod(t * 120.0, 1.0) * 2.0 - 1.0
		lp += (saw - lp) * 0.08
		var v := lp * 0.5 + sin(TAU * 240.0 * t) * 0.12 + sin(TAU * 360.0 * t) * 0.06 + (randf() - 0.5) * 0.04
		a[i] = v * 0.55
	return a


## 그것이 가까울 때: 맥놀이하는 저음. 4초 반복.
func _drone() -> PackedFloat32Array:
	var a := _buf(4.0)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / RATE
		lp += ((randf() - 0.5) - lp) * 0.02
		a[i] = (sin(TAU * 41.0 * t) * 0.5 + sin(TAU * 43.5 * t) * 0.4 + sin(TAU * 82.25 * t) * 0.15 + lp * 1.5) * 0.7
	return a


func _heartbeat() -> PackedFloat32Array:
	var a := _buf(1.0)
	for i in a.size():
		var t := float(i) / RATE
		var v := 0.0
		for start in [0.0, 0.22]:
			var dt: float = t - start
			if dt >= 0.0:
				v += sin(TAU * 55.0 * dt) * exp(-dt * 18.0)
		a[i] = v * 0.9
	return a


## 옛날 전화벨: 0.4초 울림 2번 + 쉼. 3초 반복.
func _ring() -> PackedFloat32Array:
	var a := _buf(3.0)
	for i in a.size():
		var t := float(i) / RATE
		var on := (t < 0.4) or (t > 0.6 and t < 1.0)
		var trem: float = 0.5 + 0.5 * signf(sin(TAU * 20.0 * t))
		a[i] = (sin(TAU * 440.0 * t) + sin(TAU * 480.0 * t)) * 0.25 * trem if on else 0.0
	return a


## 젖은 카펫 발소리.
func _step() -> PackedFloat32Array:
	var a := _buf(0.16)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / RATE
		lp += ((randf() - 0.5) - lp) * 0.12
		a[i] = (lp * 2.2 + sin(TAU * 70.0 * t) * 0.3) * exp(-t * 28.0)
	return a


## 깜짝 놀라는 소리: 불협 고음 + 잡음 폭발.
func _sting() -> PackedFloat32Array:
	var a := _buf(1.6)
	for i in a.size():
		var t := float(i) / RATE
		var env: float = minf(t * 60.0, 1.0) * exp(-t * 2.2)
		var v := 0.0
		for f in [622.0, 659.0, 932.0, 988.0, 1244.0]:
			v += sin(TAU * f * t + sin(TAU * 7.0 * t) * 2.0)
		v = v * 0.16 + (randf() - 0.5) * 0.6 * exp(-t * 6.0)
		a[i] = clampf(v * env * 1.3, -1.0, 1.0)
	return a


func _static() -> PackedFloat32Array:
	var a := _buf(1.2)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = (randf() - 0.5) * 0.5 * (0.6 + 0.4 * sin(TAU * 3.0 * t))
	return a


func _beep() -> PackedFloat32Array:
	var a := _buf(0.08)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = signf(sin(TAU * 1200.0 * t)) * 0.25 * (1.0 - t / 0.08)
	return a


func _buzz() -> PackedFloat32Array:
	var a := _buf(0.45)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = signf(sin(TAU * 140.0 * t)) * 0.35
	return a


func _unlock() -> PackedFloat32Array:
	var a := _buf(0.7)
	for i in a.size():
		var t := float(i) / RATE
		var v := (randf() - 0.5) * exp(-t * 80.0)
		if t > 0.15:
			var d := t - 0.15
			v += (sin(TAU * 880.0 * d) + sin(TAU * 1320.0 * d) * 0.5) * 0.3 * exp(-d * 6.0)
		a[i] = v
	return a


func _paper() -> PackedFloat32Array:
	var a := _buf(0.35)
	var hp := 0.0
	var prev := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var n := randf() - 0.5
		hp = 0.7 * (hp + n - prev)
		prev = n
		a[i] = hp * 0.7 * sin(PI * t / 0.35) * (0.5 + 0.5 * randf())
	return a


func _click() -> PackedFloat32Array:
	var a := _buf(0.05)
	for i in a.size():
		a[i] = (randf() - 0.5) * exp(-float(i) / RATE * 200.0) * 1.2
	return a


func _whoosh() -> PackedFloat32Array:
	var a := _buf(2.5)
	var lp := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var k := 0.01 + 0.2 * (t / 2.5)
		lp += ((randf() - 0.5) - lp) * k
		a[i] = lp * 2.5 * sin(PI * t / 2.5)
	return a


func _to_wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w
