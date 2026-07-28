// PLANET SKY — one sky for every generated world, re-tinted per planet.
//
// It matters more than a backdrop usually does here, for two reasons the rest
// of the project already records: the arena grade sources part of its AMBIENT
// from the sky (Grade.SKY_AMBIENT), so whatever is painted here is what lights
// the shadow side of everything on the map; and aerial perspective tints the
// fog by the sky, so the sky's horizon colour is also the colour distance goes.
// Get the sky wrong and the whole world is wrong, not just the top of it.
//
// Four layers, cheapest first:
//   ZENITH -> HORIZON gradient, the base.
//   SUN, as a disc plus a wide halo. The halo is what actually reads at a
//     glance — a hard disc alone looks like a hole punched in the sky.
//   CLOUD/ASH band, two octaves of noise stretched along the horizon and
//     faded out overhead, so it reads as a layer with depth rather than as
//     wallpaper. Mustafar runs it thick and dark, Hoth thick and pale,
//     Coruscant thin and lit from below.
//   GROUND GLOW, a lift near and below the horizon. On Mustafar that is lava
//     light on the underside of the ash; on Coruscant it is the city.
shader_type sky;

uniform vec3 zenith_col : source_color = vec3(0.10, 0.16, 0.34);
uniform vec3 horizon_col : source_color = vec3(0.55, 0.62, 0.74);
uniform vec3 sun_col : source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 cloud_col : source_color = vec3(0.72, 0.74, 0.80);
uniform vec3 glow_col : source_color = vec3(0.0, 0.0, 0.0);

uniform vec3 sun_dir = vec3(0.42, 0.55, 0.72);
uniform float sun_size = 0.014;     // angular radius of the disc
uniform float sun_halo = 7.0;       // tighter = smaller bloom around it
uniform float horizon_falloff = 2.6;
uniform float cloud_amount = 0.35;  // 0 = clear sky
uniform float cloud_height = 0.55;  // how far up the band reaches
uniform float glow_amount = 0.0;    // light coming from BELOW the horizon
uniform float stars = 0.0;          // night worlds only

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.7) * 0.27 + vnoise(p * 6.1) * 0.13;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);

	// Base gradient. pow() on the horizon term keeps the band tight to the
	// skyline instead of washing halfway up the dome.
	float t = pow(clamp(1.0 - abs(up), 0.0, 1.0), horizon_falloff);
	vec3 col = mix(zenith_col, horizon_col, t);

	// Light from below: lava, or a city. Strongest AT the horizon and carrying
	// a little way up into whatever is hanging there.
	if (glow_amount > 0.001) {
		float g = pow(clamp(1.0 - abs(up + 0.06), 0.0, 1.0), 5.0);
		col += glow_col * g * glow_amount;
	}

	// Cloud / ash / blizzard band. Projected by dividing xz by y, which
	// stretches the noise toward the horizon the way a real cloud layer
	// foreshortens — the single thing that makes a procedural sky read as
	// having distance in it.
	if (cloud_amount > 0.001) {
		float shell = 1.0 / max(abs(up) + 0.14, 0.14);
		vec2 cp = d.xz * shell * 0.55;
		float c = fbm(cp);
		// Fade out overhead and below the skyline.
		float band = smoothstep(-0.05, 0.28, up) * smoothstep(1.0, cloud_height, up);
		float cover = smoothstep(0.42, 0.78, c) * band * cloud_amount;
		// Lit from the sun side, so the layer has a form rather than being flat.
		float lit = clamp(dot(normalize(d), normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
		col = mix(col, cloud_col * (0.66 + lit * 0.55), cover);
	}

	if (stars > 0.001) {
		vec3 cell = floor(d * 160.0);
		float h = hash(cell.xy + cell.z * 37.0);
		float s = step(0.9975, h) * stars;
		// Fade them out near the horizon, where the atmosphere is thickest.
		col += vec3(s) * smoothstep(0.02, 0.35, abs(up));
	}

	// The sun last, so nothing washes over it.
	vec3 sd = normalize(sun_dir);
	float cosang = dot(normalize(d), sd);
	float halo = pow(clamp(cosang, 0.0, 1.0), sun_halo);
	col += sun_col * halo * 0.55;
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.35, cosang);
	col += sun_col * disc * 6.0;

	COLOR = col;
}
