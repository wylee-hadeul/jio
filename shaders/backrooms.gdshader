// 백룸 공용 셰이더. 조명 노드 없이 셰이더 안에서 형광등/어둠 구역/손전등/안개를 계산한다.
// kind: 0 벽, 1 바닥, 2 천장, 3 단색 물체. 벽/바닥/천장 모양은 레벨 테마(wall_style 등)로 고른다.
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
// 손전등 최대 4개(나 + 동료들)
uniform vec3 fl_pos[4];
uniform vec3 fl_dir[4];
uniform float fl_on[4];
uniform float flicker = 1.0;
uniform float global_light = 1.0;
uniform vec3 entity_pos[3];

// 테마
uniform int wall_style = 0;
uniform vec3 wall_a : source_color = vec3(0.80, 0.72, 0.42);
uniform int floor_style = 0;
uniform vec3 floor_a : source_color = vec3(0.52, 0.45, 0.27);
uniform int ceil_style = 0;
uniform vec3 ceil_a : source_color = vec3(0.78, 0.76, 0.66);
uniform vec3 light_color : source_color = vec3(1.0, 0.97, 0.82);
uniform vec3 fog_color : source_color = vec3(0.30, 0.26, 0.12);
uniform float fog_far = 27.0;

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

float grid_line(vec2 uv, vec2 period, float width) {
	vec2 t = fract(uv / period);
	vec2 d = min(t, 1.0 - t) * period;
	return 1.0 - smoothstep(0.0, width, min(d.x, d.y));
}

vec3 wall_color(vec2 uv) {
	vec3 c = wall_a;
	float n = noise(uv * 1.3) * 0.6 + noise(uv * 5.0) * 0.4;
	if (wall_style == 0) {
		// 벽지: 세로 줄무늬와 마름모 무늬
		c *= 0.93 + 0.07 * step(0.5, fract(uv.x * 4.0));
		vec2 g = fract(uv * 4.0) - 0.5;
		c *= 1.0 - 0.10 * smoothstep(0.22, 0.16, abs(g.x) + abs(g.y));
		c *= 0.82 + 0.18 * n;
	} else if (wall_style == 1) {
		// 콘크리트 블록
		vec2 b = uv * vec2(2.5, 5.0);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		c *= 1.0 - 0.25 * grid_line(b, vec2(1.0), 0.04);
		c *= 0.7 + 0.3 * n;
	} else if (wall_style == 2) {
		// 타일
		vec2 t = floor(uv / 0.2);
		c *= 0.92 + 0.08 * hash(t);
		c = mix(c, c * 0.55, grid_line(uv, vec2(0.2), 0.012));
	} else if (wall_style == 3) {
		// 녹슨 배관: 가로 배관 띠
		float band = fract(uv.y * 1.6);
		float pipe = smoothstep(0.1, 0.2, band) * smoothstep(0.6, 0.5, band);
		float shade = 0.55 + 0.45 * sin(band * 3.14159 / 0.6);
		c = mix(c * 0.45, c * shade * 1.3, pipe);
		c = mix(c, vec3(0.35, 0.18, 0.08), smoothstep(0.55, 0.8, noise(uv * 3.0)) * 0.6);
	} else if (wall_style == 4) {
		// 아래는 나무 판자, 위는 무늬 벽지
		if (uv.y < 1.1) {
			c = vec3(0.32, 0.18, 0.1) * (0.8 + 0.2 * noise(vec2(uv.x * 30.0, uv.y * 2.0)));
			c *= 1.0 - 0.4 * grid_line(vec2(uv.x, 0.0), vec2(0.3, 1.0), 0.01);
		} else {
			vec2 g = fract(uv * vec2(3.0, 2.0)) - 0.5;
			c *= 0.8 + 0.2 * smoothstep(0.3, 0.2, length(g));
		}
		c *= 0.85 + 0.15 * n;
	} else {
		// 페인트 벽 + 허리 몰딩
		c *= 0.9 + 0.1 * n;
		c = mix(c, c * 0.6, 1.0 - smoothstep(0.0, 0.03, abs(uv.y - 0.95)));
	}
	// 습기 얼룩
	float damp = smoothstep(0.62, 0.9, noise(uv * 0.6 + 3.1)) * smoothstep(1.6, 0.0, uv.y);
	return mix(c, c * vec3(0.55, 0.5, 0.35), damp * 0.6);
}

vec3 floor_color(vec2 p) {
	vec3 c = floor_a;
	if (floor_style == 0) {
		c *= 0.78 + 0.22 * noise(p * 9.0);
		c *= 0.85 + 0.15 * noise(p * 0.9);
		float wet = smoothstep(0.6, 0.85, noise(p * 0.35 + 7.0));
		c = mix(c, c * 0.5, wet * 0.8);
	} else if (floor_style == 1) {
		c *= 0.75 + 0.25 * noise(p * 2.0);
		float puddle = smoothstep(0.62, 0.7, noise(p * 0.4 + 2.0));
		c = mix(c, c * 0.45 + vec3(0.05), puddle);
	} else if (floor_style == 2) {
		vec2 t = floor(p / 0.4);
		c *= 0.88 + 0.12 * hash(t);
		c = mix(c, c * 0.5, grid_line(p, vec2(0.4), 0.015));
	} else if (floor_style == 3) {
		// 물 아래 타일 + 일렁이는 빛
		c = mix(c, c * 0.6, grid_line(p, vec2(0.3), 0.012));
		float caustic = noise(p * 2.5 + vec2(TIME * 0.4, TIME * 0.3)) * noise(p * 3.1 - vec2(TIME * 0.3, 0.0));
		c += vec3(0.25, 0.35, 0.4) * smoothstep(0.25, 0.55, caustic);
	} else {
		// 철망
		float holes = grid_line(p, vec2(0.12), 0.025);
		c = mix(vec3(0.02), c, holes);
	}
	return c;
}

vec3 ceil_color(vec2 p, float amb, out float glow) {
	vec3 c = ceil_a;
	vec2 lc = fract(p / cell) - 0.5;
	glow = 0.0;
	if (ceil_style == 0) {
		c *= 0.9 + 0.1 * noise(p * 3.0);
		c *= 1.0 - 0.35 * grid_line(p, vec2(0.6), 0.02);
		float panel = step(abs(lc.x), 0.22) * step(abs(lc.y), 0.11);
		c = mix(c, vec3(0.5, 0.5, 0.46), panel);
		glow = panel * amb;
	} else if (ceil_style == 1) {
		c *= 0.75 + 0.25 * noise(p * 1.5);
		float bulb = 1.0 - smoothstep(0.03, 0.05, length(lc));
		glow = bulb * amb * 1.5;
	} else {
		float band = fract(p.x * 1.2);
		c *= 0.6 + 0.4 * smoothstep(0.3, 0.5, band) * smoothstep(0.9, 0.7, band);
		float strip = step(abs(lc.x), 0.03) * step(abs(lc.y), 0.3);
		glow = strip * amb * 0.8;
	}
	return c;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 벽면은 자기가 바라보는 칸의 밝기를 쓰도록 법선 방향으로 조금 나가서 읽는다
	vec2 muv = (wpos.xz + wnorm.xz * 0.6) / cell / map_size;
	float lit = smoothstep(0.3, 0.8, texture(light_map, muv).r) * global_light;
	// 그것 주변 형광등은 죽어 간다
	float ent = 1.0;
	for (int i = 0; i < 3; i++) {
		ent = min(ent, smoothstep(1.5, 7.0, distance(wpos.xz, entity_pos[i].xz)));
	}
	float amb = lit * flicker * mix(0.15, 1.0, ent);

	vec3 col;
	float glow = 0.0;
	if (kind == 0) {
		vec2 uv = abs(wnorm.x) > 0.5 ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		uv.x += anomaly * 0.125;
		col = wall_color(uv);
		col = mix(col, col * 0.55, step(wpos.y, 0.12));
		if (anomaly > 0.5) {
			float seam = 1.0 - smoothstep(0.0, 0.02, abs(fract(uv.x * 0.5) - 0.5));
			col *= 1.0 - seam * 0.5;
		}
	} else if (kind == 1) {
		col = floor_color(wpos.xz);
	} else if (kind == 2) {
		col = ceil_color(wpos.xz, amb, glow);
	} else {
		col = base_color;
	}

	float dist = distance(wpos, cam_pos);
	float fl = 0.0;
	for (int i = 0; i < 4; i++) {
		vec3 d = wpos - fl_pos[i];
		float di = length(d);
		float cone = smoothstep(0.86, 0.97, dot(d / max(di, 0.001), fl_dir[i]));
		fl = max(fl, fl_on[i] * cone * clamp(1.0 - di / 16.0, 0.0, 1.0) * 1.15);
	}
	vec3 lightc = mix(vec3(1.0), light_color, 0.6);
	vec3 lighting = lightc * amb * 0.95 + vec3(1.0, 0.98, 0.92) * fl;
	lighting = max(lighting, vec3(0.025));

	float fog = smoothstep(3.0, fog_far, dist);
	col = mix(col * lighting, fog_color * amb, fog);
	col += light_color * glow * (1.0 - fog * 0.6);
	col += base_color * emissive;
	ALBEDO = col;
}
