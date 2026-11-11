shader_type canvas_item;
render_mode unshaded;
uniform vec2 card_size = vec2(192.0, 288.0);
uniform float yaw = 0.0;
uniform float depth_blur = 0.0;
uniform float selection_light = 0.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
	VERTEX = (VERTEX - card_size * 0.5) * 1.16 + card_size * 0.5;
}
void fragment() {
	float ratio = card_size.y / max(card_size.x, 1.0);
	vec2 screen = (UV - 0.5) * vec2(1.16, 1.16 * ratio);
	float c = cos(yaw), s = sin(yaw);
	float x = screen.x * 5.0 / (5.0 * c - screen.x * s);
	float y = screen.y * (5.0 + x * s) / 5.0;
	vec2 uv = vec2(x + 0.5, y / ratio + 0.5);
	vec4 ink = vec4(0.0);
	if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
		// Bias the automatically chosen mip level; a fixed LOD aliases fine print.
		ink = texture(TEXTURE, uv, depth_blur);
		// A steady cool surface light, not a white overlay: keep dark logo/text
		// strokes and the source PNG alpha intact while lifting the paper/clouds.
		float luminance = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
		float paper = smoothstep(0.18, 0.55, luminance);
		vec2 light_position = (uv - vec2(0.50, 0.42)) * vec2(1.45, 0.85);
		float soft_light = 0.72 + 0.28 * exp(-3.0 * dot(light_position, light_position));
		float amount = clamp(selection_light, 0.0, 1.0) * paper * soft_light;
		ink.rgb += (vec3(1.0) - ink.rgb) * vec3(0.839, 0.918, 1.0) * amount;
	}
	COLOR = ink * tint;
}
