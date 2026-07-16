// Deep-space starfield for the hangar skybox.
// Pure math, no textures — cheap enough for the Pi 5 GL Compatibility target.
shader_type sky;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 d = EYEDIR;
	// Near-black space with a faint cold nebula band at the horizon.
	vec3 col = vec3(0.004, 0.006, 0.012);
	col += vec3(0.012, 0.02, 0.045) * pow(1.0 - abs(d.y), 4.0);

	// Two star layers at different densities.
	for (int i = 0; i < 2; i++) {
		float scale = 90.0 + float(i) * 80.0;
		vec3 cell = floor(d * scale);
		float h = hash13(cell);
		if (h > 0.965) {
			vec3 centre = normalize((cell + 0.5) / scale);
			float dist = length(d - centre);
			float star = smoothstep(0.0045, 0.0, dist) * (0.35 + 0.65 * fract(h * 91.7));
			col += star * mix(vec3(0.8, 0.86, 1.0), vec3(1.0, 0.92, 0.8), fract(h * 57.3));
		}
	}
	COLOR = col;
}
