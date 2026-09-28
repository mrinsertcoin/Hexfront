shader_type spatial;
render_mode cull_back;
uniform sampler2DArray ground_maps : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_maps : filter_linear_mipmap, repeat_enable;
uniform vec4 layer_tints[5];
uniform float layer_scales[5];
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

void fragment() {
    // Object coordinates have world-unit scale; no longitude UV or pole seam.
    vec3 n = normalize(local_normal);
    vec3 radial = normalize(local_position);
    vec3 axes = pow(abs(n), vec3(4.0));
    axes /= max(dot(axes, vec3(1.0)), 0.00001);
    float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
    float rock = clamp(slope * 7.0 * rock_strength + UV.y * 0.12, 0.0, 0.7);
    float weights[5];
    weights[0] = COLOR.r; weights[1] = COLOR.g; weights[2] = COLOR.b;
    weights[3] = COLOR.a; weights[4] = UV2.x;
    float total = 0.0;
    for (int i = 0; i < 5; i++) {
        weights[i] = weights[i] * (1.0 - rock) + (i == 3 ? rock : 0.0);
        total += weights[i];
    }
    vec3 albedo = vec3(0.0);
    vec3 perturbation = vec3(0.0);
    float rough = 0.0;
    for (int i = 0; i < 5; i++) {
        float w = weights[i] / max(total, 0.00001);
        vec3 p = local_position / max(layer_scales[i], 0.01);
        vec4 x = texture(ground_maps, vec3(p.yz, float(i)));
        vec4 y = texture(ground_maps, vec3(p.xz, float(i)));
        vec4 z = texture(ground_maps, vec3(p.xy, float(i)));
        vec4 surface = x * axes.x + y * axes.y + z * axes.z;
        albedo += surface.rgb * layer_tints[i].rgb * w;
        rough += surface.a * w;
        if (use_normal_maps) {
            // Project tangent perturbations into the three local planes, then
            // remove their normal component. Flat normal maps preserve n exactly.
            vec2 nx = texture(normal_maps, vec3(p.yz, float(i))).rg * 2.0 - 1.0;
            vec2 ny = texture(normal_maps, vec3(p.xz, float(i))).rg * 2.0 - 1.0;
            vec2 nz = texture(normal_maps, vec3(p.xy, float(i))).rg * 2.0 - 1.0;
            vec3 delta = vec3(0.0,nx.x,nx.y)*axes.x + vec3(ny.x,0.0,ny.y)*axes.y + vec3(nz.x,nz.y,0.0)*axes.z;
            perturbation += (delta - n * dot(delta,n)) * layer_normals[i] * w;
        }
    }
    // Restrained macro color and damp soil, never a glossy wet hemisphere.
    float macro = 0.96 + 0.04 * sin(dot(local_position, vec3(0.71,0.32,0.57)));
    float wet = clamp((UV.x * 0.35 + UV2.y * 0.65) * wet_strength, 0.0, 0.45);
    ALBEDO = albedo * macro * (1.0 - wet * 0.45);
    ROUGHNESS = clamp(rough - wet * 0.25, 0.52, 1.0);
    SPECULAR = 0.25;
    NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(normalize(n + perturbation),0.0)).xyz);
}
