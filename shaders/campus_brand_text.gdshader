shader_type canvas_item;
render_mode unshaded;

uniform vec4 gradient_left : source_color = vec4(0.20, 0.68, 0.48, 1.0);
uniform vec4 gradient_middle : source_color = vec4(0.20, 0.62, 0.76, 1.0);
uniform vec4 gradient_right : source_color = vec4(0.08, 0.32, 0.67, 1.0);
uniform float texture_strength : hint_range(0.0, 0.08) = 0.025;
uniform float embolden_pixels : hint_range(0.0, 2.0) = 0.85;

void fragment() {
	vec4 glyph = texture(TEXTURE, UV);
	vec2 bold_offset = TEXTURE_PIXEL_SIZE * embolden_pixels;
	float glyph_alpha = glyph.a;
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV + vec2(bold_offset.x, 0.0)).a);
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV - vec2(bold_offset.x, 0.0)).a);
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV + vec2(0.0, bold_offset.y)).a);
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV - vec2(0.0, bold_offset.y)).a);
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV + bold_offset).a);
	glyph_alpha = max(glyph_alpha, texture(TEXTURE, UV - bold_offset).a);

	vec2 centered_screen = SCREEN_UV - vec2(0.5);
	centered_screen.x *= 2560.0 / 1680.0;
	vec2 gradient_direction = vec2(0.5, 0.8660254);
	float diagonal_position = dot(centered_screen, gradient_direction);
	float green_to_cyan = smoothstep(-0.125, -0.035, diagonal_position);
	float cyan_to_blue = smoothstep(-0.015, 0.075, diagonal_position);
	vec3 gradient = mix(gradient_left.rgb, gradient_middle.rgb, green_to_cyan);
	gradient = mix(gradient, gradient_right.rgb, cyan_to_blue);

	vec2 fabric_position = SCREEN_UV * vec2(2560.0, 1680.0);
	float horizontal_thread = sin(fabric_position.y * 0.15);
	float vertical_thread = sin(fabric_position.x * 0.11);
	float soft_sheen = sin((fabric_position.x + fabric_position.y) * 0.025);
	float fabric = (horizontal_thread + vertical_thread) * 0.35 + soft_sheen * 0.3;

	vec3 final_color = clamp(gradient + fabric * texture_strength, vec3(0.0), vec3(1.0));
	COLOR = vec4(final_color, glyph_alpha * COLOR.a);
}
