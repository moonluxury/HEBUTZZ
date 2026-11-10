shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	// Fixed ~12px mip blur; animate this independent layer's opacity only.
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, 3.5).rgb;
	COLOR = vec4(blurred * 0.74, tint.a);
}
