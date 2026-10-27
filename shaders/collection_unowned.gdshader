shader_type canvas_item;

// Presentation only: preserve the source texture, alpha and inherited fades.
void fragment() {
	float gray = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR.rgb = vec3(gray);
}
