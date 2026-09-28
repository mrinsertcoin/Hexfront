shader_type spatial;
render_mode cull_back;

// Ground stores albedo RGB and roughness A. Surface stores OpenGL normal RG,
// height B and ambient occlusion A for each of the five gameplay biome layers.
uniform sampler2DArray ground_maps : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_maps : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_maps : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_normal_maps : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 layer_tints[5];
uniform float layer_scales[5];
uniform float detail_scales[5];
uniform float layer_details[5];
uniform float layer_normals[5];
uniform bool use_normal_maps = true;
uniform float rock_strength = 0.65;
uniform float wet_strength = 0.35;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

vec4 triplanar(sampler2DArray maps, vec3 p, float layer, vec3 axes) {
	vec4 x = texture(maps, vec3(p.yz, layer));
	vec4 y = texture(maps, vec3(p.xz, layer));
	vec4 z = texture(maps, vec3(p.xy, layer));
	return x * axes.x + y * axes.y + z * axes.z;
}

vec3 triplanar_surface(sampler2DArray maps, vec3 p, float layer, vec3 axes, vec3 n, out vec4 surface) {
	vec4 x = texture(maps, vec3(p.yz, layer));
	vec4 y = texture(maps, vec3(p.xz, layer));
	vec4 z = texture(maps, vec3(p.xy, layer));
	surface = x * axes.x + y * axes.y + z * axes.z;
	vec2 nx = x.rg * 2.0 - 1.0;
	vec2 ny = y.rg * 2.0 - 1.0;
	vec2 nz = z.rg * 2.0 - 1.0;
	vec3 delta = vec3(0.0, nx.x, nx.y) * axes.x
		+ vec3(ny.x, 0.0, ny.y) * axes.y
		+ vec3(nz.x, nz.y, 0.0) * axes.z;
	return delta - n * dot(delta, n);
}

void fragment() {
	// Object coordinates retain world-unit scale and avoid longitude/pole seams.
	vec3 n = normalize(local_normal);
	vec3 radial = normalize(local_position);
	vec3 axes = pow(abs(n), vec3(4.0));
	axes /= max(dot(axes, vec3(1.0)), 0.00001);
	float terrain_roughness = clamp(UV.y, 0.0, 1.0);
	float moisture = clamp(UV.x, 0.0, 1.0);
	float wet_potential = clamp(UV2.y, 0.0, 1.0);
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	float rock = clamp(slope * 7.0 * rock_strength + terrain_roughness * 0.12, 0.0, 0.7);
	float weights[5];
	weights[0] = COLOR.r;
	weights[1] = COLOR.g;
	weights[2] = COLOR.b;
	weights[3] = COLOR.a;
	weights[4] = UV2.x;
	float total = 0.0;
	for (int i = 0; i < 5; i++) {
		weights[i] = weights[i] * (1.0 - rock) + (i == 3 ? rock : 0.0);
		total += weights[i];
	}
	float conditions[5];
	conditions[0] = 0.0;
	conditions[1] = smoothstep(0.25, 0.75, moisture);
	conditions[2] = smoothstep(0.35, 0.85, terrain_roughness);
	conditions[3] = clamp(terrain_roughness * 0.6 + slope * 4.0, 0.0, 1.0);
	conditions[4] = clamp(wet_potential * 0.65 + moisture * 0.35, 0.0, 1.0);
	int detail_layer = -1;
	float strongest_detail = 0.005;
	for (int i = 0; i < 5; i++) {
		float score = weights[i] / max(total, 0.00001) * layer_details[i] * conditions[i];
		if (score > strongest_detail) {
			strongest_detail = score;
			detail_layer = i;
		}
	}

	vec3 albedo = vec3(0.0);
	vec3 perturbation = vec3(0.0);
	float roughness = 0.0;
	float ambient_occlusion = 0.0;
	for (int i = 0; i < 5; i++) {
		float w = weights[i] / max(total, 0.00001);
		vec3 primary_p = local_position / max(layer_scales[i], 0.01);
		vec4 ground = triplanar(ground_maps, primary_p, float(i), axes);
		vec4 packed;
		vec3 primary_delta = triplanar_surface(normal_maps, primary_p, float(i), axes, n, packed);

		// Secondary detail responds to the existing continuous terrain fields.
		float detail_mix = clamp(layer_details[i] * conditions[i], 0.0, 0.48);
		// At most one condition-appropriate secondary layer is sampled per
		// fragment. Primary biome weights remain fully continuous.
		if (i == detail_layer) {
			vec3 detail_p = local_position / max(detail_scales[i], 0.01);
			vec4 detail_ground = triplanar(detail_maps, detail_p, float(i), axes);
			vec4 detail_packed;
			vec3 detail_delta = triplanar_surface(detail_normal_maps, detail_p, float(i), axes, n, detail_packed);
			// Height biases this micro blend and never displaces geometry.
			float blend = clamp(detail_mix + (detail_packed.b - packed.b) * 0.12, 0.0, 0.55);
			ground = mix(ground, detail_ground, blend);
			packed = mix(packed, detail_packed, blend);
			if (use_normal_maps) {
				perturbation += detail_delta * layer_normals[i] * w * blend;
			}
		}
		albedo += ground.rgb * layer_tints[i].rgb * w;
		roughness += ground.a * w;
		ambient_occlusion += packed.a * w;
		if (use_normal_maps) {
			perturbation += primary_delta * layer_normals[i] * w * (1.0 - detail_mix * 0.35);
		}
	}

	float macro = 0.965 + 0.035 * sin(dot(local_position, vec3(0.71, 0.32, 0.57)));
	float wet = clamp((moisture * 0.35 + wet_potential * 0.65) * wet_strength, 0.0, 0.42);
	ALBEDO = albedo * macro * (1.0 - wet * 0.32);
	ROUGHNESS = clamp(roughness - wet * 0.18, 0.55, 1.0);
	AO = clamp(mix(1.0, ambient_occlusion, 0.52), 0.55, 1.0);
	AO_LIGHT_AFFECT = 0.32;
	SPECULAR = 0.25;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(normalize(n + perturbation), 0.0)).xyz);
}
