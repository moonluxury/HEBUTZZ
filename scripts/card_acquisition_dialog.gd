extends CanvasLayer
## Full-viewport presentation. The persistent store owns the paid operation.
const Reveal = preload("res://scripts/card_reveal.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const Styles = preload("res://scripts/ui_styles.gd")
signal closed
var page: Control
var store: Node
var shield: Control
var stage: Control
var back: TextureRect
var preview: Control
var hit: Button
var close_button: Button
var return_button: Button
var title_label: Label
var hint: Label
var details: VBoxContainer
var name_label: Label
var metadata: Label
var description: Label
var state := "ready"
var closing := false
var _epoch := -1
var _shown_id := ""
var _space_down := false
var _skip_requested := false

class Glow extends Control:
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

func _ready() -> void:
	layer = 95
	_epoch = store.epoch
	shield = Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.10, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(shade)
	stage = Control.new()
	stage.size = Vector2(760, 900)
	stage.theme = page.theme
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(stage)
	stage.add_child(Glow.new())
	title_label = _label("获取卡牌", 30, Color.WHITE, true)
	title_label.position = Vector2(312, 168)
	title_label.size = Vector2(136, 46)
	hint = _label("点击卡牌开启", 17, Color("#CAD1DF"))
	hint.position = Vector2(100, 224)
	hint.size = Vector2(560, 52)
	back = TextureRect.new()
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = Vector2(260, 268)
	back.size = Vector2(240, 360)
	stage.add_child(back)
	var season: Dictionary = page.store.season("season-001")
	back.texture = page._texture(str(season.get("back_image", "")))
	preview = Reveal.new()
	preview.position = Vector2(200, 220)
	preview.size = Vector2(360, 420)
	stage.add_child(preview)
	preview.status_label.add_theme_color_override("font_color", Color("#DCE5F4"))
	preview.presentation_changed.connect(_reveal_changed)
	preview.hide()
	hit = _button(stage, "", _card_clicked, false)
	hit.position = back.position
	hit.size = back.size
	hit.accessibility_name = "获取卡牌，200 电池一次"
	for value in ["normal", "hover", "pressed", "disabled", "focus"]: hit.add_theme_stylebox_override(value, StyleBoxEmpty.new())
	details = VBoxContainer.new()
	details.position = Vector2(110, 654)
	details.size = Vector2(540, 160)
	details.add_theme_constant_override("separation", 6)
	stage.add_child(details)
	name_label = _detail_label(22, Color.WHITE, true)
	metadata = _detail_label(14, Color("#C4CDDF"))
	description = _detail_label(16, Color("#DDE3EE"))
	description.max_lines_visible = 3
	return_button = _button(details, "返回我的收藏", dismiss, true)
	details.hide()
	close_button = _button(shield, "", dismiss, false)
	close_button.theme = page.theme
	close_button.icon = UI.glyph("close", Color("#DCE5F4"))
	close_button.add_theme_constant_override("icon_max_width", 20)
	close_button.custom_minimum_size = Vector2(36, 36)
	close_button.size = Vector2(36, 36)
	close_button.accessibility_name = "返回我的收藏"
	store.changed.connect(_sync)
	get_viewport().size_changed.connect(_layout)
	page.resized.connect(_layout)
	get_node("/root/AppState").font_scale_changed.connect(_layout.unbind(1))
	_layout()
	_sync()

func present() -> void:
	page._motion().enter(shield, 0.18)
	hit.grab_focus()
	store.open()

func _label(text: String, font_size: int, color: Color, strong := false) -> Label:
	var label := UI.label(stage, text, font_size, color, strong)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _detail_label(font_size: int, color: Color, strong := false) -> Label:
	var label := UI.label(details, "", font_size, color, strong)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Node, text: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 17)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(key, Color.WHITE)
	for key in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(key, Styles.box(Color("#092C87") if primary else Color.TRANSPARENT, 7))
	button.add_theme_stylebox_override("focus", Styles.box(Color.TRANSPARENT, 7, Color("#ADCAFF")))
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _layout() -> void:
	if not is_instance_valid(stage): return
	var bounds := get_viewport().get_visible_rect().size
	var factor: float = minf(page.canvas.scale.x, minf(bounds.y / 950, bounds.x / 800))
	stage.scale = Vector2.ONE * factor
	stage.position = (bounds - stage.size * factor) * 0.5
	close_button.scale = Vector2.ONE * factor
	close_button.position = Vector2(bounds.x - 60 * factor, 24 * factor)

func _sync() -> void:
	if closing: return
	if store.epoch != _epoch:
		dismiss()
		return
	if store.ready_result():
		if _shown_id == str(store.operation.id): return
		_shown_id = str(store.operation.id)
		var card: Dictionary = page.store.card(str(store.operation.receipt.card_id))
		name_label.text = str(card.name)
		metadata.text = str(page.store.season(str(card.season_id)).get("name", "")) + " · 编号 " + str(card.get("number", ""))
		description.text = str(card.get("description", ""))
		state = "revealing"
		title_label.text = "正在开卡"
		hint.text = "请稍候"
		back.hide()
		preview.show()
		hit.disabled = true
		var season: Dictionary = page.store.season(str(card.season_id))
		preview.present(Reveal.new_session(card, str(card.get("back_image", season.get("back_image", ""))), get_instance_id(), true))
		return
	state = "requesting" if store.busy else "ready"
	title_label.text = "正在开卡" if store.busy else "获取卡牌"
	hint.text = "请稍候" if store.busy else store.error if not store.error.is_empty() else "正在准备…" if store.loading else "点击卡牌开启"
	hit.disabled = store.busy or store.loading or store._corrupt

func _reveal_changed() -> void:
	if closing: return
	if _skip_requested and preview.state in ["ready", "revealing"]:
		_skip_requested = false
		preview.skip()
		return
	details.visible = preview.detail_alpha > 0
	details.modulate.a = preview.detail_alpha
	details.position.y = 654 + preview.detail_offset
	return_button.disabled = not preview.interactive
	return_button.focus_mode = Control.FOCUS_ALL if preview.interactive else Control.FOCUS_NONE
	if preview.interactive:
		state = "result"
		title_label.text = "获得卡牌"
		hint.text = store.error
		hit.disabled = false
		hit.accessibility_name = "返回我的收藏"

func _card_clicked() -> void:
	if closing: return
	if state == "result": dismiss()
	elif state == "ready": store.acquire()

func _input(event: InputEvent) -> void:
	if closing or not event is InputEventKey: return
	if event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if not event.pressed: _space_down = false; return
		if event.echo or _space_down: return
		_space_down = true
		if state == "revealing":
			if preview.state == "loading": _skip_requested = true
			else: preview.skip()
	elif event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
	elif event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		var controls: Array = [hit, return_button, close_button] if state == "result" else [hit, close_button]
		controls = controls.filter(func(c): return not c.disabled and c.is_visible_in_tree())
		var index := controls.find(get_viewport().gui_get_focus_owner())
		controls[posmod(index + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()

func dismiss() -> void:
	if closing: return
	closing = true
	if state == "result" and _epoch == store.epoch: store.acknowledge()
	if is_instance_valid(preview): preview.cancel()
	hide()
	closed.emit()
	queue_free()
