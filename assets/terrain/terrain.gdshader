shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform vec4 biome_colors[5];
uniform float macro_scale = 0.32;
uniform float macro_strength = 0.055;
uniform float rock_strength = 0.65;
uniform float wet_strength = 0.35;
uniform bool textured = false;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_position;
varying vec3 local_normal;
void vertex() { local_position=VERTEX; local_normal=NORMAL; }
vec3 triplanar(sampler2D image, vec3 p, vec3 blend) {
    return texture(image,p.yz).rgb*blend.x+texture(image,p.xz).rgb*blend.y+texture(image,p.xy).rgb*blend.z;
}
void fragment() {
    vec3 n=normalize(local_normal);
    float moisture=clamp(UV.x,0.0,1.0);
    float wetland=clamp(UV2.y,0.0,1.0);
    float slope=1.0-clamp(dot(n,normalize(local_position)),0.0,1.0);
    float weights[5]; weights[0]=COLOR.r; weights[1]=COLOR.g; weights[2]=COLOR.b; weights[3]=COLOR.a; weights[4]=UV2.x;
    float rock=smoothstep(0.05,0.32,slope*rock_strength+UV.y*0.10);
    float total=0.0;
    for (int i=0;i<5;i++) { weights[i]=mix(weights[i],i==3?1.0:0.0,rock*0.72); total+=weights[i]; }
    vec3 color=vec3(0.0);
    for (int i=0;i<5;i++) { weights[i]/=max(total,0.00001); color+=biome_colors[i].rgb*weights[i]; }
    if (textured) {
        vec3 blend=pow(abs(n),vec3(4.0)); blend/=max(dot(blend,vec3(1.0)),0.00001);
        vec3 p=local_position*0.65;
        vec3 detail=triplanar(grass_texture,p,blend)*weights[0]+triplanar(forest_texture,p,blend)*weights[1]+triplanar(sand_texture,p,blend)*weights[2]+triplanar(rock_texture,p,blend)*weights[3]+triplanar(mud_texture,p,blend)*weights[4];
        color=mix(color,detail*0.78,0.68);
    }
    float macro=sin(dot(local_position,vec3(0.73,0.31,0.57))*macro_scale)*0.62+sin(dot(local_position,vec3(-0.23,0.91,0.38))*macro_scale*0.63+1.7)*0.38;
    float damp=clamp((moisture*0.28+wetland*0.72)*wet_strength,0.0,0.38);
    ALBEDO=color*(1.0+macro*macro_strength)*(1.0-damp*0.24);
    ROUGHNESS=0.9; SPECULAR=0.20;
}
