extends RefCounted
## Local primitives for gift and exchange windows; no inventory or network ownership.
const Styles = preload("res://scripts/ui_styles.gd")
const Ui = preload("res://scripts/account_dialog_ui.gd")
const Artwork = preload("res://scripts/card_artwork.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")

static func colors(dark: bool) -> Dictionary:
	var result := Styles.palette(dark)
	result.summary = Color("#1D293B") if dark else Color("#F4F6FA")
	result.selection = Color("#20365B") if dark else Color("#EBF2FC")
	return result

static func label(parent: Node, caption: String, size: int, palette: Dictionary, muted := false, strong := false) -> Label:
	var node := Ui.label(parent, caption, size, palette.muted if muted else palette.text, strong)
	node.set_meta("transfer_muted", muted)
	return node

static func button(parent: Node, caption: String, callback: Callable, palette: Dictionary, primary := false, outlined := false) -> Button:
	var node := Ui.button(parent, caption, callback, palette, primary, outlined)
	node.set_meta("transfer_primary", primary)
	node.set_meta("transfer_outlined", outlined)
	node.custom_minimum_size.y = 48
	return node

static func shell(window: Window, title: String, dismiss: Callable, palette: Dictionary) -> Dictionary:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	var panel := PanelContainer.new()
	window.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(window, panel, palette.surface, 14))
	var margin := Ui.margin(panel, 32)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var heading_label := label(heading, title, 24, palette, false, true)
	heading_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := button(heading, "关闭", dismiss, palette)
	close.set_meta("transfer_link",true)
	Ui.style_button(close,palette,false,false,true)
	close.custom_minimum_size = Vector2(56, 32)
	close.add_theme_font_size_override("font_size", 16)
	close.accessibility_name = "关闭" + title
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	return {"panel":panel,"column":column,"body":body,"scroll":scroll,"footer":footer,"heading":heading_label,"close":close}

static func summary(parent: Node, card: Dictionary, season: Dictionary, detail: String, palette: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.set_meta("transfer_summary", true)
	var frame := Styles.box(palette.summary, 10)
	frame.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", frame)
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)
	var art := Artwork.create(row, card)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.custom_minimum_size = Vector2(80, 80 * Artwork.ratio(art))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metadata := VBoxContainer.new()
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	metadata.add_theme_constant_override("separation", 6)
	row.add_child(metadata)
	var name := label(metadata, str(card.get("name", "卡牌")), 20, palette, false, true)
	var season_label := label(metadata, Artwork.season_title(season), 16, palette, true)
	var amount := label(metadata, detail, 16, palette, true)
	return {"panel":panel,"art":art,"metadata":metadata,"name":name,"season":season_label,"amount":amount}

static func glyph(name: String, color: Color) -> Texture2D:
	var source := FileAccess.get_file_as_string("res://assets/minimal/source/" + name + ".svg")
	return DPITexture.create_from_string(source.replace("currentColor", "#" + color.to_html(false)))

static func stepper(parent: Node, palette: Dictionary, caption: String, maximum: int) -> SpinBox:
	var panel := PanelContainer.new()
	panel.set_meta("transfer_stepper", true)
	panel.add_theme_stylebox_override("panel", Styles.box(palette.surface, 8, palette.border))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	panel.add_child(row)
	var decrease := button(row, "−", func(): pass, palette)
	decrease.custom_minimum_size = Vector2(38, 40)
	decrease.accessibility_name = "减少" + caption
	var number := SpinBox.new()
	number.min_value = 1
	number.max_value = maxi(1, maximum)
	number.step = 1
	number.rounded = true
	number.value = 1
	number.suffix = "张"
	number.custom_minimum_size = Vector2(76, 40)
	# Keep native integer editing and validation, with separate horizontal buttons.
	number.add_theme_constant_override("buttons_width", 0)
	number.add_theme_constant_override("set_min_buttons_width_from_icons", 0)
	number.add_theme_constant_override("field_and_buttons_separation", 0)
	var empty := ImageTexture.create_from_image(Image.create_empty(1,1,false,Image.FORMAT_RGBA8))
	for icon in ["updown","up","up_hover","up_pressed","up_disabled","down","down_hover","down_pressed","down_disabled"]:
		number.add_theme_icon_override(icon, empty)
	row.add_child(number)
	var input := number.get_line_edit()
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.accessibility_name = caption + "，正整数"
	input.text_changed.connect(func(_value): number.set_meta("manual_edit",true))
	input.add_theme_font_size_override("font_size", 18)
	input.add_theme_color_override("font_color", palette.text)
	input.add_theme_color_override("font_uneditable_color",palette.muted)
	input.add_theme_color_override("font_readonly_color",palette.muted)
	for state in ["normal", "read_only"]: input.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	Styles.apply_focus(input)
	var increase := button(row, "+", func(): pass, palette)
	increase.custom_minimum_size = Vector2(38, 40)
	increase.accessibility_name = "增加" + caption
	decrease.pressed.connect(func(): commit_quantity(number); number.value -= 1)
	increase.pressed.connect(func(): commit_quantity(number); number.value += 1)
	number.set_meta("decrease", decrease)
	number.set_meta("increase", increase)
	number.value_changed.connect(func(_value):
		number.set_meta("manual_edit",false)
		sync_stepper(number, number.editable, int(number.max_value))
	)
	sync_stepper(number, true, maximum)
	return number

static func commit_quantity(number: SpinBox) -> void:
	# A queued native text redraw must not overwrite a fresh +/- value.
	if number.get_meta("manual_edit",false): number.apply()
	number.set_meta("manual_edit",false)

static func sync_stepper(number: SpinBox, editable: bool, maximum: int) -> void:
	if number.editable != editable: number.editable = editable
	var input := number.get_line_edit()
	var extent := input.get_theme_font("font").get_string_size("%d 张" % int(number.value),HORIZONTAL_ALIGNMENT_LEFT,-1,18).x + 16
	number.custom_minimum_size.x = maxf(76,extent)
	for pair in [["decrease", number.value <= number.min_value], ["increase", number.value >= maximum]]:
		var control: Button = number.get_meta(pair[0])
		control.disabled = not editable or pair[1]
		var feedback := control.get_node_or_null("UIFeedback")
		if feedback != null: feedback._check_disabled()
		control.queue_redraw()

static func person(parent: Node, person: Dictionary, palette: Dictionary, radio := false) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var avatar := Avatar.new()
	avatar.custom_minimum_size = Vector2(44,44)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	avatar.show_profile(person)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	row.add_child(details)
	var name := label(details, str(person.get("name", person.get("display_name", "好友"))), 16, palette, false, true)
	var identifier := label(details, "ID: " + str(person.get("public_id", person.get("id", ""))), 14, palette, true)
	for text in [name,identifier]:
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var choice: TextureRect
	if radio:
		choice = TextureRect.new()
		choice.texture = glyph("circle", palette.muted)
		choice.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		choice.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		choice.custom_minimum_size = Vector2(20,20)
		choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(choice)
	for child in [row] + row.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return {"row":row,"avatar":avatar,"name":name,"id":identifier,"radio":choice}

static func fit(window: Window, desired: Vector2, host: Control, panel: PanelContainer, opening := false) -> void:
	panel.scale = Vector2.ONE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ui.fit(window,desired,host,opening)
	var density := maxf(1.0,window.get_tree().root.get_stretch_transform().get_scale().x) if window.is_embedded() else 1.0
	# Only supersample the embedded render target. Logical control coordinates and
	# native input mapping remain unchanged, so the larger parent never upscales ink.
	window.oversampling_override = maxf(1.0,window.content_scale_factor * density)
	render_density(window)

static func render_density(window: Window) -> void:
	if not window.visible or not window.is_embedded(): return
	var density := maxf(1.0,window.get_tree().root.get_stretch_transform().get_scale().x)
	if density > 1.001:
		var pixels := Vector2i((Vector2(window.size) * density).ceil())
		RenderingServer.viewport_set_size(window.get_viewport_rid(),pixels.x,pixels.y)
		RenderingServer.viewport_set_global_canvas_transform(window.get_viewport_rid(),(window.get_stretch_transform() * window.global_canvas_transform).scaled(Vector2.ONE * density))
