// Jungle floor: mottled moss over bare dirt, with darker undergrowth patches.
// Procedural value noise — one material, no textures, Pi-friendly.
shader_type spatial;

uniform vec3 moss_col : source_color = vec3(0.13, 0.24, 0.10);
uniform vec3 dirt_col : source_color = vec3(0.22, 0.17, 0.11);
uniform vec3 deep_col : source_color = vec3(0.06, 0.12, 0.06);
// Per-axis, so a rectangular arena doesn't stretch the noise along its long side.
uniform vec2 tiles = vec2(34.0, 34.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);  // smoothstep the cell interpolation
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// AN OCTAVE FADES TO ITS OWN MEAN ONCE ITS CELLS ARE SMALLER THAN A PIXEL.
//
// Procedural noise has no mip chain: every fragment evaluates the exact
// function, so where the ground runs away from the camera two adjacent pixels
// land far apart in the noise and the result is the concentric shimmer that made
// the foreground of every ground shot look like a rendering fault. A texture
// would be mipped and this is the analytic equivalent — `fwidth` says how much
// uv one pixel covers, and an octave finer than that carries no information any
// more, only noise. Fading it toward 0.5 (the mean of `vnoise`) leaves the
// colour it was averaging to, which is exactly what a mip level would give.
float octave(vec2 uv, float freq, float footprint) {
	float fade = 1.0 - smoothstep(0.35, 1.1, footprint * freq);
	return mix(0.5, vnoise(uv * freq), fade);
}

void fragment() {
	vec2 uv = UV * tiles;
	float fp = max(fwidth(uv.x), fwidth(uv.y));
	// Two octaves: broad moss/dirt drift plus fine leaf-litter break-up.
	float n = octave(uv, 1.0, fp) * 0.65 + octave(uv, 3.3, fp) * 0.35;
	vec3 col = mix(dirt_col, moss_col, smoothstep(0.34, 0.70, n));
	// Sparse dark undergrowth so the clearing doesn't read as a flat lawn.
	col = mix(col, deep_col, smoothstep(0.78, 0.95, octave(uv, 0.7, fp)));
	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
