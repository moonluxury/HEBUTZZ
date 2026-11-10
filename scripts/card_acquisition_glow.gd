extends Control
func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var center := Vector2(380, 448)
	draw_set_transform(center, 0, Vector2(1, 1.3))
	for i in range(22, 0, -1):
		draw_circle(Vector2.ZERO, 110 + i * 6, Color(0.40, 0.58, 1.0, 0.008))
	draw_set_transform(Vector2(380, 637), 0, Vector2(1, 0.15))
	for i in range(20, 0, -1):
		draw_circle(Vector2.ZERO, 60 + i * 10, Color(0.45, 0.64, 1.0, 0.012))
	draw_arc(Vector2.ZERO, 270, 0, TAU, 96, Color(0.62, 0.76, 1.0, 0.12), 1, true)
	draw_set_transform(Vector2.ZERO)
	var orbit := PackedVector2Array()
	for i in 97: orbit.append(center + Vector2(cos(TAU * i / 96.0) * 270, sin(TAU * i / 96.0) * 70).rotated(-0.2))
	draw_polyline(orbit, Color(0.55, 0.70, 1, 0.20), 1, true)
	for x in [305, 455]:
		var p := Vector2(x, 192)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(2, -2), p + Vector2(6, 0), p + Vector2(2, 2), p + Vector2(0, 6), p + Vector2(-2, 2), p + Vector2(-6, 0), p + Vector2(-2, -2)]), Color("#D9E6FF"))
	draw_line(Vector2(150, 192), Vector2(292, 192), Color(0.65, 0.77, 1, 0.65), 1, true)
	draw_line(Vector2(468, 192), Vector2(610, 192), Color(0.65, 0.77, 1, 0.65), 1, true)
