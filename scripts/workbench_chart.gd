extends Control
const Tokens = preload("res://scripts/ui_tokens.gd")
const Reveal = preload("res://scripts/ui_data_reveal.gd")
## Data visualization only; the containing Button owns mouse and keyboard input.

var kind := "trend"
var empty_message := "完成第一题，点亮学习曲线"
var days: Array = []:
	set(value):
		if days == value:
			return
		days = value
		queue_redraw()
		if is_instance_valid(reveal):
			reveal.restart()
var counts: Dictionary = {}
var dark := false
var reveal: Node
const COLORS := [Color("#0089FF"), Color("#8159FF"), Color("#FFBE38"), Color("#41BAF8"), Color("#15C8CA"), Color("#FFA76B")]
const TYPES := ["single", "multiple", "judge", "fill", "output", "program"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if kind == "trend":
		reveal = Reveal.new()
		reveal.name = "DataReveal"
		add_child(reveal)


func _draw() -> void:
	if kind == "trend":
		_draw_trend()
	else:
		_draw_distribution()


func _draw_trend() -> void:
	var font := get_theme_default_font()
	var ink := Color("#A4B5D6") if dark else Color("#657080")
	var grid := Color("#2A3C58") if dark else Color("#E5E8EE")
	var plot := Rect2(48, 18, size.x - 72, size.y - 60)
	var highest := 0
	for day in days:
		highest = maxi(highest, int(day.count))
	var ceiling := maxi(4, int(ceil(float(highest) / 4.0)) * 4)
	for row in 5:
		var y := plot.end.y - plot.size.y * row / 4.0
		draw_dashed_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0, 5.0, true)
		draw_string(font, Vector2(0, y + 7), str(ceiling * row / 4), HORIZONTAL_ALIGNMENT_RIGHT, 35, 19, ink)
	var points := PackedVector2Array()
	for index in days.size():
		var x := plot.position.x + plot.size.x * index / maxf(1, days.size() - 1)
		var y := plot.end.y - plot.size.y * int(days[index].count) / float(ceiling)
		points.append(Vector2(x, y))
		var date := str(days[index].date)
		draw_string(font, Vector2(x - 35, plot.end.y + 32), "%d.%d" % [int(date.substr(5, 2)), int(date.substr(8, 2))], HORIZONTAL_ALIGNMENT_CENTER, 70, 19, ink)
	if points.size() < 2:
		return
	var amount: float = reveal.amount if is_instance_valid(reveal) else 1.0
	if amount > 0.0:
		var edge := lerpf(plot.position.x, plot.end.x, amount)
		var visible_points := PackedVector2Array([points[0]])
		for index in range(1, points.size()):
			if points[index].x <= edge:
				visible_points.append(points[index])
			else:
				var weight := inverse_lerp(points[index - 1].x, points[index].x, edge)
				visible_points.append(points[index - 1].lerp(points[index], weight))
				break
		var accent := Tokens.DARK_ACCENT if dark else Tokens.PRIMARY
		if visible_points.size() >= 2:
			draw_polyline(visible_points, accent, 3.0, true)
		for point in points:
			if point.x <= edge:
				draw_circle(point, 5, accent, true, -1, true)
				draw_circle(point, 2.5, Color.WHITE, true, -1, true)
	if highest == 0:
		draw_string(font, Vector2(plot.position.x, plot.position.y + plot.size.y * 0.5), empty_message, HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 22, ink)


func _draw_distribution() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 22
	var center := size * 0.5
	var total := 0
	for value in counts.values():
		total += int(value)
	var angle := -PI * 0.5
	for index in TYPES.size():
		var sweep := TAU * int(counts.get(TYPES[index], 0)) / maxi(1, total)
		if sweep > 0:
			draw_arc(center, radius, angle + 0.006, angle + sweep - 0.006, maxi(4, int(sweep * 50)), COLORS[index], 39, true)
		angle += sweep
