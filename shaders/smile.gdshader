// 그것의 얼굴: 검은 바탕에 빛나는 두 눈과 찢어진 웃음. 어둠 속에서도 보인다.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float intensity = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float head = 1.0 - smoothstep(0.92, 1.0, length(p * vec2(1.0, 0.8)));
	float eyes = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 e = vec2(i == 0 ? -0.33 : 0.33, 0.28);
		eyes += 1.0 - smoothstep(0.07, 0.11, length((p - e) * vec2(1.0, 1.6)));
	}
	// 웃음: 아래로 휜 넓은 호, 이빨 줄무늬
	float curve = 0.05 - 0.55 * p.x * p.x;
	float mouth = step(abs(p.x), 0.72) * step(curve - 0.28, p.y) * step(p.y, curve - 0.12);
	float teeth = mouth * step(0.35, fract(p.x * 9.0));
	vec3 col = vec3(0.0);
	col += vec3(1.0, 0.98, 0.9) * eyes * intensity;
	col += vec3(0.95, 0.93, 0.85) * teeth * intensity;
	ALBEDO = col;
	ALPHA = max(head * 0.0, max(eyes, mouth)) ;
}
