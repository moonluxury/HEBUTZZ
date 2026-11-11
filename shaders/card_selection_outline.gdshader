shader_type canvas_item;
render_mode unshaded;

uniform vec2 card_size = vec2(184.0, 276.0);
uniform float padding = 24.0;
uniform float yaw = 0.0;
uniform float strength = 0.0;
varying vec4 inherited_tint;

void vertex() {
	inherited_tint = COLOR;
}

float coverage(sampler2D source_image, vec2 point) {
	vec2 screen = point / card_size.x;
	float c = cos(yaw), s = sin(yaw);
	float x = screen.x * 5.0 / (5.0 * c - screen.x * s);
	float y = screen.y * (5.0 + x * s) / 5.0;
	vec2 uv = vec2(x + 0.5, y * card_size.x / card_size.y + 0.5);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(source_image, uv).a;
}

void fragment() {
	vec2 point = (UV - 0.5) * (card_size + vec2(padding * 2.0));
	float ink = coverage(TEXTURE, point);
	float near_edge = 0.0;
	float middle = 0.0;
	float outer = 0.0;
	for (int i = 0; i < 12; i++) {
		float angle = float(i) * 6.28318530718 / 12.0;
		vec2 direction = vec2(cos(angle), sin(angle));
		near_edge = max(near_edge, coverage(TEXTURE, point + direction * 2.2));
		middle += coverage(TEXTURE, point + direction * 8.0) / 12.0;
		outer += coverage(TEXTURE, point + direction * 18.0) / 12.0;
	}
	// Only the real PNG silhouette emits light; transparent corners stay open.
	float edge = max(near_edge - ink, 0.0);
	float halo = max(middle - ink, 0.0) * 0.45 + max(outer - ink, 0.0) * 0.20;
	vec3 blue = vec3(0.086, 0.290, 0.725);
	vec3 ice = vec3(0.839, 0.918, 1.0);
	vec3 color = mix(blue, ice, edge * 0.80);
	COLOR = vec4(color, (edge * 0.88 + halo) * strength) * inherited_tint;
}
