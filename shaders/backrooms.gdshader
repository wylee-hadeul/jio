// 백룸 공용 셰이더. 조명 노드 없이 셰이더 안에서 형광등/어둠 구역/손전등/안개를 계산한다.
// kind: 0 벽지, 1 카펫, 2 천장, 3 단색 물체
shader_type spatial;
render_mode unshaded, cull_back;

uniform int kind = 0;
uniform vec3 base_color : source_color = vec3(1.0);
uniform float anomaly = 0.0;
uniform float emissive = 0.0;
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(17.0, 17.0);
uniform float cell = 3.0;
uniform vec3 cam_pos;
uniform vec3 cam_dir = vec3(0.0, 0.0, -1.0);
uniform float flash_on = 0.0;
uniform float flicker = 1.0;
uniform vec3 entity_pos = vec3(9999.0);

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 wallpaper(vec2 uv) {
	vec3 c = vec3(0.80, 0.72, 0.42);
	// 세로 줄무늬와 마름모 무늬
	c *= 0.93 + 0.07 * step(0.5, fract(uv.x * 4.0));
	vec2 g = fract(uv * 4.0) - 0.5;
	c *= 1.0 - 0.10 * smoothstep(0.22, 0.16, abs(g.x) + abs(g.y));
	// 얼룩과 습기
	float n = noise(uv * 1.3) * 0.6 + noise(uv * 5.0) * 0.4;
	c *= 0.82 + 0.18 * n;
	float damp = smoothstep(0.62, 0.9, noise(uv * 0.6 + 3.1)) * smoothstep(1.6, 0.0, uv.y);
	c = mix(c, c * vec3(0.55, 0.5, 0.3), damp * 0.7);
	return c;
}

vec3 carpet(vec2 p) {
	vec3 c = vec3(0.52, 0.45, 0.27);
	c *= 0.78 + 0.22 * noise(p * 9.0);
	c *= 0.85 + 0.15 * noise(p * 0.9);
	float wet = smoothstep(0.6, 0.85, noise(p * 0.35 + 7.0));
	return mix(c, c * vec3(0.5, 0.45, 0.3), wet * 0.8);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 벽면은 자기가 바라보는 칸의 밝기를 쓰도록 법선 방향으로 조금 나가서 읽는다
	vec2 muv = (wpos.xz + wnorm.xz * 0.6) / cell / map_size;
	float lit = smoothstep(0.3, 0.8, texture(light_map, muv).r);
	// 그것 주변 형광등은 죽어 간다
	float ent = smoothstep(1.5, 7.0, distance(wpos.xz, entity_pos.xz));
	float amb = lit * flicker * mix(0.15, 1.0, ent);

	vec3 col;
	float glow = 0.0;
	if (kind == 0) {
		vec2 uv = abs(wnorm.x) > 0.5 ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		uv.x += anomaly * 0.125;
		col = wallpaper(uv);
		col = mix(col, vec3(0.42, 0.35, 0.2), step(wpos.y, 0.12));
		// 어긋난 벽: 이음매 한 줄
		if (anomaly > 0.5) {
			float seam = 1.0 - smoothstep(0.0, 0.02, abs(fract(uv.x * 0.5) - 0.5));
			col *= 1.0 - seam * 0.5;
		}
	} else if (kind == 1) {
		col = carpet(wpos.xz);
	} else if (kind == 2) {
		vec2 t = fract(wpos.xz / 0.6);
		col = vec3(0.78, 0.76, 0.66) * (0.9 + 0.1 * noise(wpos.xz * 3.0));
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.04, min(min(t.x, 1.0 - t.x), min(t.y, 1.0 - t.y))));
		vec2 lc = fract(wpos.xz / cell) - 0.5;
		float panel = step(abs(lc.x), 0.22) * step(abs(lc.y), 0.11);
		col = mix(col, vec3(0.5, 0.5, 0.46), panel);
		glow = panel * amb;
	} else {
		col = base_color;
	}

	float dist = distance(wpos, cam_pos);
	vec3 to = (wpos - cam_pos) / max(dist, 0.001);
	float cone = smoothstep(0.86, 0.97, dot(to, cam_dir));
	float fl = flash_on * cone * clamp(1.0 - dist / 16.0, 0.0, 1.0) * 1.15;
	float b = max(amb * 0.95, fl) + 0.025;

	float fog = smoothstep(3.0, 27.0, dist);
	vec3 fog_col = vec3(0.30, 0.26, 0.12) * amb;
	col = mix(col * b, fog_col, fog);
	col += vec3(1.0, 0.97, 0.82) * glow * (1.0 - fog * 0.6);
	col += base_color * emissive;
	ALBEDO = col;
}
