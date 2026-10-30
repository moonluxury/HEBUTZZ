shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform vec4 surface_color = vec4(1.0);

void fragment() {
	// Invisible RGB bleed prevents filtering transparent black into rounded edges.
	// Alpha stays zero: the underlying page and its shade remain fully visible.
	COLOR = vec4(surface_color.rgb, 0.0);
}
