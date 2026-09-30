shader_type spatial;
render_mode cull_back, diffuse_burley;

// Continuous stylized palette: Grassland, Forest, Dryland, Rocky, Wetland.
uniform vec4 biome_colors[5];
uniform float macro_scale = 0.32;
uniform float macro_strength = 0.055;
uniform float rock_strength = 0.68;
uniform float wet_strength = 0.32;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec3 radial = normalize(local_position);
	float terrain_roughness = clamp(UV.y, 0.0, 1.0);
	float moisture = clamp(UV.x, 0.0, 1.0);
	float wetland = clamp(UV2.y, 0.0, 1.0);
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	float weights[5];
	weights[0] = COLOR.r;
	weights[1] = COLOR.g;
	weights[2] = COLOR.b;
	weights[3] = COLOR.a;
	weights[4] = UV2.x;
	float rock = smoothstep(0.05, 0.32, slope * rock_strength + terrain_roughness * 0.10);
	float total = 0.0;
	for (int i = 0; i < 5; i++) {
		weights[i] = mix(weights[i], i == 3 ? 1.0 : 0.0, rock * 0.72);
		total += weights[i];
	}
	vec3 color = vec3(0.0);
	for (int i = 0; i < 5; i++) color += biome_colors[i].rgb * weights[i] / max(total, 0.00001);

	// Broad object-space variation avoids UV seams and preserves readable forms.
	float macro_a = sin(dot(local_position, vec3(0.73, 0.31, 0.57)) * macro_scale);
	float macro_b = sin(dot(local_position, vec3(-0.23, 0.91, 0.38)) * macro_scale * 0.63 + 1.7);
	float macro = macro_a * 0.62 + macro_b * 0.38;
	float damp = clamp((moisture * 0.28 + wetland * 0.72) * wet_strength, 0.0, 0.38);
	ALBEDO = color * (1.0 + macro * macro_strength) * (1.0 - damp * 0.24);
	ROUGHNESS = clamp(0.88 - damp * 0.12 - rock * 0.04, 0.68, 0.94);
	SPECULAR = 0.20;
}
