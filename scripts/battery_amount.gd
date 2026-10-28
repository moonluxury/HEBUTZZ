extends HBoxContainer
## One static currency asset; quantity never changes its two cells.
const ICON_PATH := "res://assets/recharge/battery-two.svg"
const MAX_INTEGER := 9007199254740991
var picture: TextureRect
var number: Label
var unit: Label

func setup(page: Control, value: String, icon_width := 48.0, font_size := 46, unit_size := 18) -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture = TextureRect.new()
	picture.texture = page._texture(ICON_PATH)
	# A neutral mask keeps the same two-cell geometry in blue and inactive gray.
	picture.self_modulate = page._accent()
	picture.custom_minimum_size = Vector2(icon_width, icon_width * 32.0 / 56.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	number = page._label(self, value, font_size, page.text_color, Rect2(), true)
	number.clip_text = false
	number.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	unit = page._label(self, "电池", unit_size, page.muted_color)
	unit.clip_text = false
	unit.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	accessibility_name = value + " 电池"

func set_value(value: String) -> void:
	number.text = value
	accessibility_name = value + " 电池"

static func integer(value: Variant, minimum := 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= MAX_INTEGER

static func grouped(value: int) -> String:
	var raw := str(absi(value))
	var result := ""
	for index in raw.length():
		if index > 0 and (raw.length() - index) % 3 == 0: result += ","
		result += raw[index]
	return ("-" if value < 0 else "") + result

static func money(cents: int) -> String:
	@warning_ignore("integer_division")
	return "¥%s.%02d" % [grouped(cents / 100), cents % 100]
