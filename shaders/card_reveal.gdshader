shader_type canvas_item;
render_mode unshaded;

uniform sampler2D front_image : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D back_image : source_color, filter_linear_mipmap, repeat_disable;
uniform float turn = 0.0;
uniform float perspective = 5.0;
uniform float expansion = 1.16;
uniform vec2 card_size = vec2(240.0, 360.0);
uniform float shine_position = -2.0;
uniform float shine_strength = 0.0;
uniform float rim = 0.0;
uniform bool grayscale = false;
varying vec4 tint;

void vertex() {
	tint = COLOR;
	VERTEX = (VERTEX - card_size * 0.5) * expansion + card_size * 0.5;
}

void fragment() {
	// Inverse projection of a single paper plane around its vertical centre.
	// Front UV is reversed with the physical face, so printed text is never mirrored.
	vec2 screen = (UV - 0.5) * vec2(expansion, expansion * 1.5);
	float c = cos(turn);
	float s = sin(turn);
	float denominator = perspective * c - screen.x * s;
	vec4 ink = vec4(0.0);
	if (abs(c) > 0.0001 && abs(denominator) > 0.0001) {
		float x = screen.x * perspective / denominator;
		float y = screen.y * (perspective + x * s) / perspective;
		bool front = c < 0.0;
		vec2 uv = vec2((front ? -x : x) + 0.5, y / 1.5 + 0.5);
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			ink = front ? texture(front_image, uv) : texture(back_image, uv);
			if (front && grayscale) {
				ink.rgb = vec3(dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722)));
			}
			float edge_distance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
			float edge = (1.0 - smoothstep(0.0, 0.025, edge_distance)) * rim;
			float sweep = (1.0 - smoothstep(0.0, 0.20, abs(uv.x + uv.y * 0.45 - shine_position))) * shine_strength;
			ink.rgb = mix(ink.rgb, vec3(1.0, 0.988, 0.937), clamp(edge + sweep, 0.0, 0.45));
		}
	}
	// Source alpha also masks the reflection, including the transparent corners.
	COLOR = ink * tint;
}
