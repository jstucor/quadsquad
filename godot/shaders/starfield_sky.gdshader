// Deep-space starfield for the hangar skybox.
// Pure math, no textures — cheap enough for the Pi 5 GL Compatibility target.
shader_type sky;

// The night gradient. Constants rather than uniforms: every map that uses this
// sky wants the same night, and the ones that want a different sky already
// override _build_environment with a shader of their own.
const vec3 ZENITH = vec3(0.006, 0.009, 0.020);
const vec3 HORIZON = vec3(0.030, 0.043, 0.078);
const vec3 BAND = vec3(0.018, 0.030, 0.062);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 d = EYEDIR;
	// A GRADED night sky, not a black one. Two reasons, and the second is the
	// load-bearing one:
	//
	//   Looks:  a real night sky is never flat black. It has airglow near the
	//           horizon and goes deepest overhead, and that gradient is most of
	//           what reads as "sky" rather than "the inside of a box".
	//   Light:  the arena grade sources part of its AMBIENT from this sky (see
	//           Arena._grade_environment), so whatever is painted here is what
	//           lights the shadow side of every object on a night map. A black
	//           sky contributes black, which is exactly the documented gotcha
	//           about metals rendering pitch dark — this is that bug's source.
	//
	// Still dark enough for the stars to carry the image; the gradient is worth
	// a couple of percent of albedo, not a moonlit scene.
	float horizon = pow(1.0 - abs(d.y), 3.0);
	vec3 col = mix(ZENITH, HORIZON, horizon);
	// A cold band tight to the skyline, which is where a distant silhouette
	// separates from the sky.
	col += BAND * pow(1.0 - abs(d.y), 10.0);

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
