shader_type canvas_item;
render_mode unshaded;
uniform vec2 card_size = vec2(192.0, 288.0);
uniform float yaw = 0.0;
uniform float depth_blur = 0.0;
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
	}
	COLOR = ink * tint;
}
