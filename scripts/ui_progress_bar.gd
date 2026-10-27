extends ProgressBar
## Animate only the painted fill, never the real progress value or its label.
const Reveal = preload("res://scripts/ui_data_reveal.gd")
var reveal: Node
var fill_style: StyleBox

func _ready() -> void:
	fill_style = get_theme_stylebox("fill").duplicate()
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	reveal = Reveal.new()
	reveal.name = "DataReveal"
	reveal.animate_on_ready = value > min_value
	add_child(reveal)
	value_changed.connect(_value_changed)

func _value_changed(_value: float) -> void:
	reveal.restart(value > min_value)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(reveal) or fill_style == null:
		return
	var width := size.x * get_as_ratio() * float(reveal.amount)
	if width > 0.0:
		draw_style_box(fill_style, Rect2(0, 0, width, size.y))
