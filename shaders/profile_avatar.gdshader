shader_type canvas_item;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec2 dimensions = vec2(textureSize(TEXTURE, 0));
	vec2 crop = vec2(min(dimensions.x, dimensions.y)) / dimensions;
	vec4 source = texture(TEXTURE, (UV - 0.5) * crop + 0.5);
	float edge = 1.0 - smoothstep(0.488, 0.5, length(UV - 0.5));
	COLOR = vec4(source.rgb, source.a * edge) * tint;
}
