// Jungle terrain: moss over dirt on the flat, bare rock on anything steep, with
// darker undergrowth in the hollows. Procedural — one material, no textures.
//
// Steepness arrives as vertex colour (red channel) rather than being derived
// from the normal, because the map generates the heightfield and knows the
// exact analytic gradient at every vertex. `slope_mix` turns it off for the
// flat base plane, which has no vertex colours of its own.
shader_type spatial;

uniform vec3 moss_col : source_color = vec3(0.14, 0.27, 0.11);
uniform vec3 dirt_col : source_color = vec3(0.26, 0.20, 0.13);
uniform vec3 rock_col : source_color = vec3(0.34, 0.33, 0.30);
uniform vec3 deep_col : source_color = vec3(0.05, 0.11, 0.06);
uniform vec2 uv_tiles = vec2(1.0, 1.0);
uniform float slope_mix = 1.0;

varying float steep;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	steep = COLOR.r * slope_mix;
}

void fragment() {
	vec2 uv = UV * uv_tiles;
	float n = vnoise(uv) * 0.62 + vnoise(uv * 3.3) * 0.38;
	vec3 col = mix(dirt_col, moss_col, smoothstep(0.32, 0.68, n));
	col = mix(col, deep_col, smoothstep(0.76, 0.94, vnoise(uv * 0.7)));
	// Bare rock takes over on the steep faces. The noise is folded into the
	// threshold so the transition breaks up instead of reading as a contour.
	float rock = smoothstep(0.30, 0.74, steep + (n - 0.5) * 0.28);
	col = mix(col, rock_col * (0.82 + n * 0.36), rock);
	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.95, 0.72, rock);
	SPECULAR = 0.15;
}
