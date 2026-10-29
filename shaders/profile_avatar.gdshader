shader_type canvas_item;
uniform float grayscale : hint_range(0.0, 1.0) = 0.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec2 dimensions = vec2(textureSize(TEXTURE, 0));
	vec2 crop = vec2(min(dimensions.x, dimensions.y)) / dimensions;
	vec4 source = texture(TEXTURE, (UV - 0.5) * crop + 0.5);
	source.rgb = mix(source.rgb, vec3(dot(source.rgb, vec3(0.299, 0.587, 0.114))), grayscale);
	float distance = length(UV - 0.5);
	// Keep the soft edge about one output pixel wide at every display scale.
	float antialias = max(fwidth(distance), 0.0001);
	float edge = 1.0 - smoothstep(0.5 - antialias, 0.5, distance);
	COLOR = vec4(source.rgb, source.a * edge) * tint;
}
