shader_type spatial;
render_mode cull_disabled;
uniform vec4 water_color : source_color = vec4(0.08,0.30,0.35,1.0);
uniform float calmness = 0.7;
void fragment() {
    // Opaque, restrained water avoids sorting/depth leaks on the far hemisphere.
    float edge = smoothstep(0.0, 0.24, min(UV.x, 1.0-UV.x));
    ALBEDO = mix(water_color.rgb * 1.22, water_color.rgb, edge);
    ROUGHNESS = mix(0.38,0.26,calmness);
    SPECULAR = 0.35;
}
