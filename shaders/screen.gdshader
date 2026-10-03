// 화면 전체 후처리 느낌: 비네트, 필름 그레인, 주사선. danger가 높을수록 가장자리가 붉고 어두워진다.
shader_type canvas_item;

uniform float danger = 0.0;
uniform float blackout = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.35, 0.85, d) * (0.75 + danger * 0.25);
	float grain = hash(uv * 900.0 + fract(TIME * 7.0)) - 0.5;
	float scan = 0.5 + 0.5 * sin(uv.y * 900.0 + TIME * 3.0);
	vec3 tint = mix(vec3(0.0), vec3(0.25, 0.0, 0.0), danger);
	float a = clamp(vig + scan * 0.04 + abs(grain) * 0.06, 0.0, 1.0);
	COLOR = vec4(tint + vec3(grain * 0.08), max(a, blackout));
}
