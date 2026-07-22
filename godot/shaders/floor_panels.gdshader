// Imperial hangar deck: dark metal panels with recessed seams.
// Procedural grid — one material, no textures, Pi-friendly.
shader_type spatial;

uniform vec3 base_col : source_color = vec3(0.17, 0.18, 0.21);
uniform vec3 seam_col : source_color = vec3(0.03, 0.035, 0.05);
uniform float panels = 24.0;

void fragment() {
	vec2 uv = UV * panels;
	vec2 g = abs(fract(uv) - 0.5);
	float seam = smoothstep(0.465, 0.49, max(g.x, g.y));
	// subtle per-panel tonal variation so the deck doesn't read as flat
	vec2 id = floor(uv);
	float tone = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453) * 0.045;
	ALBEDO = mix(base_col + tone, seam_col, seam);
	METALLIC = 0.12;
	ROUGHNESS = mix(0.42, 0.78, seam);
	SPECULAR = 0.5;
}
