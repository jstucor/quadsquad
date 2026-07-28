// PLANET GROUND — the one terrain material every generated world uses, tinted
// and re-weighted per planet. Procedural throughout: no textures, so it costs
// bandwidth nowhere and scales to a 300 m map for free.
//
// Five things are layered here, and each one is doing a specific job that the
// flat three-tone blend it replaces could not:
//
//   1. FBM at four octaves, so the ground has structure at every distance you
//      look at it — metres, tens of metres, and the whole map. A single octave
//      reads as noise; four reads as terrain.
//   2. SLOPE blending. Flat ground takes the surface material (sand, moss,
//      snow, ash), steep ground takes rock. This is what stops a heightfield
//      looking like a painted bedsheet — and the steepness is exact, handed in
//      as vertex colour by the generator that knows the analytic gradient.
//   3. HEIGHT banding: a low material in the hollows and a high one on the
//      tops, so elevation reads as a change in the ground and not just as a
//      change in shading.
//   4. MACRO variation at ~60 m, which is what keeps a big map from looking
//      tiled. Without it you can see the noise repeat from a rooftop.
//   5. A detail NORMAL perturbation, so the surface catches the light
//      unevenly. This is the cheapest thing here and it does more for
//      "material" than any of the colour work.
//
// Emissive veins (`vein_col`, `vein_amount`) are for Mustafar's lava and
// Coruscant's lit seams: they follow the same ridged noise the terrain does, so
// molten rock runs along the low channels rather than being sprayed over it.
shader_type spatial;
// Double-sided for the same reason the jungle terrain is: a heightfield is a
// one-sided skin, and anywhere the camera gets under it the whole world would
// otherwise vanish. See the FRONT_FACING branch at the bottom.
render_mode cull_disabled;

uniform vec3 low_col : source_color = vec3(0.22, 0.17, 0.12);
uniform vec3 mid_col : source_color = vec3(0.36, 0.27, 0.17);
uniform vec3 high_col : source_color = vec3(0.52, 0.42, 0.30);
uniform vec3 rock_col : source_color = vec3(0.30, 0.27, 0.24);
uniform vec3 under_col : source_color = vec3(0.10, 0.09, 0.09);
uniform vec3 vein_col : source_color = vec3(1.0, 0.35, 0.05);

uniform float world_scale = 0.045;   // noise cycles per metre
uniform float macro_scale = 0.016;   // the big drift that hides repetition
uniform float height_lo = 0.0;       // metres: where low_col gives way to mid
uniform float height_hi = 14.0;      // ...and mid to high
uniform float rock_bias = 0.0;       // push rock in earlier (rocky worlds)
uniform float vein_amount = 0.0;     // 0 = none; Mustafar runs ~0.55
uniform float vein_sharp = 22.0;     // how tight the molten channels are
uniform float detail_bump = 0.35;
uniform float rough_flat = 0.92;
uniform float rough_rock = 0.68;
uniform float sparkle = 0.0;         // Hoth: glints on the snow

varying float steep;
varying float world_y;
varying vec3 world_pos;

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

// Four octaves, each half the amplitude and twice the frequency of the last.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;      // not exactly 2, or the octaves line up and band
		a *= 0.5;
	}
	return v;
}

// Ridged noise: |n - 0.5| inverted, which gives sharp creases instead of blobs.
// Erosion channels and lava runs both want creases.
float ridge(vec2 p) {
	return 1.0 - abs(vnoise(p) - 0.5) * 2.0;
}

void vertex() {
	// The generator writes the exact analytic slope into vertex colour — it
	// knows the gradient of its own height function, which is far better than
	// anything reconstructable from the interpolated normal.
	steep = COLOR.r;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_y = world_pos.y;
}

void fragment() {
	vec2 p = world_pos.xz * world_scale;
	float n = fbm(p);
	float macro = fbm(world_pos.xz * macro_scale);

	// Height bands, softened by the noise so the boundary is a coastline rather
	// than a contour line.
	float h = (world_y - height_lo) / max(height_hi - height_lo, 0.001);
	h = clamp(h + (n - 0.5) * 0.45, 0.0, 1.0);
	vec3 col = mix(low_col, mid_col, smoothstep(0.0, 0.55, h));
	col = mix(col, high_col, smoothstep(0.45, 1.0, h));

	// Macro drift: two ground types at map scale, so a 300 m plain is not one
	// colour with noise on it.
	col *= 0.86 + macro * 0.34;

	// Rock on the steep faces. The noise is folded into the threshold so the
	// transition breaks up instead of reading as a band.
	float rock = smoothstep(0.26, 0.72, steep + rock_bias + (n - 0.5) * 0.34);
	col = mix(col, rock_col * (0.78 + n * 0.44), rock);

	// Molten / lit channels, following the ridged low ground.
	float vein = 0.0;
	if (vein_amount > 0.001) {
		float r = ridge(p * 0.55);
		vein = pow(clamp(r, 0.0, 1.0), vein_sharp) * vein_amount;
		vein *= 1.0 - rock;                       // channels run in the hollows
		vein *= smoothstep(0.55, 0.15, h);        // ...and low down
		col = mix(col, vein_col, clamp(vein * 1.6, 0.0, 1.0));
	}

	// NO DETAIL NORMAL. Two ways of perturbing it were tried and both rendered
	// the whole terrain very nearly BLACK under a perfectly good sun, while every
	// box standing on that terrain lit correctly: NORMAL_MAP needs a tangent
	// basis this generated heightfield does not reliably have, and the
	// world-space round trip through INV_VIEW_MATRIX did not survive the
	// Compatibility renderer either. Deleting it made the ground bright
	// immediately — the palette and the sun angle were never the problem, and
	// both got "fixed" once each while chasing this.
	//
	// The surface interest it was there for comes from the FBM in the albedo and
	// from the roughness split below, which cost nothing and cannot go wrong.
	float grain = fbm(p * 4.0);
	col *= 0.90 + grain * 0.20;

	// Seen from BENEATH — inside a cave mouth, or a camera clipping the skin —
	// it is bare rock, and the normal has to be flipped or the underside lights
	// as though it still faced the sky. Godot forbids an early return in
	// fragment(), so this is a branchless select.
	float under = FRONT_FACING ? 0.0 : 1.0;
	NORMAL = mix(NORMAL, -NORMAL, under);
	col = mix(col, under_col * (0.7 + n * 0.6), under);

	// A little glint for snow and glass grit.
	if (sparkle > 0.001) {
		float g = pow(vnoise(world_pos.xz * 5.5), 18.0) * sparkle;
		col += vec3(g) * (1.0 - rock);
	}

	ALBEDO = col;
	METALLIC = 0.0;
	// Roughness varies with the same grain, so the light breaks up across the
	// surface even though the geometry does not.
	ROUGHNESS = mix(mix(rough_flat, rough_rock, rock), 0.95, under)
		* (0.88 + grain * 0.24);
	SPECULAR = 0.2;
	// Veins light themselves; everything else is lit by the sun and the sky.
	EMISSION = vein_col * vein * 2.4;
}
