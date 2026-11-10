shader_type canvas_item;
render_mode unshaded;

uniform vec4 deep_blue : source_color = vec4(0.070588, 0.145098, 0.419608, 1.0);
uniform vec4 campus_blue : source_color = vec4(0.086275, 0.290196, 0.725490, 1.0);
uniform vec4 bright_blue : source_color = vec4(0.254902, 0.423529, 0.843137, 1.0);
uniform vec4 highlight : source_color = vec4(0.839216, 0.917647, 1.0, 1.0);
uniform vec4 text_bounds = vec4(0.0, 0.0, 120.0, 40.0);
uniform float title_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float sweep_position = -0.2;
uniform float sweep_strength : hint_range(0.0, 0.3) = 0.0;
varying vec2 label_position;

void vertex() {
	// Glyph atlas UVs repeat per character. Label-local vertices do not.
	label_position = VERTEX;
}

void fragment() {
	vec2 p = (label_position - text_bounds.xy) / max(text_bounds.zw, vec2(1.0));
	float diagonal = clamp(p.x + (0.5 - p.y) * 0.08, 0.0, 1.0);
	vec3 blue = mix(deep_blue.rgb, campus_blue.rgb, smoothstep(0.0, 0.75, diagonal));
	blue = mix(blue, bright_blue.rgb, smoothstep(0.68, 1.0, diagonal) * 0.65);
	// A single 15%-wide soft band, leaning slightly toward the upper right.
	float distance_to_band = abs(p.x + (p.y - 0.5) * 0.08 - sweep_position);
	float band = 1.0 - smoothstep(0.0, 0.075, distance_to_band);
	COLOR.rgb = mix(blue, highlight.rgb, band * sweep_strength);
	// COLOR already contains Godot's native glyph coverage (including MSDF).
	// Never resample atlas alpha or change the glyph's geometry/antialiasing.
	COLOR.a *= title_alpha;
}
