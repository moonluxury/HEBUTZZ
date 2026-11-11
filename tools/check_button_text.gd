extends SceneTree
const Styles = preload("res://scripts/ui_styles.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const T = preload("res://scripts/ui_tokens.gd")
var failures: Array[String] = []
var assertions := 0
var motion: Node
var canvas: Control
var output := "res://outputs/button-text-validation"

func _init() -> void: _run.call_deferred()
func frames(count := 4) -> void:
	for i in count: await process_frame
func check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok: failures.append(description); push_error(description)

func active_white(button: Button) -> bool:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		if not button.get_theme_color(state).is_equal_approx(Color.WHITE): return false
	return true

func make_button(caption: String, row: int, color: Color, primary: bool, dark: bool, disabled := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.disabled = disabled
	canvas.add_child(button)
	button.position = Vector2(80, 65 + row * 76)
	button.size = Vector2(580, 54)
	Styles.button(button, color, primary, dark, 22)
	motion.bind_button(button, primary)
	return button

func assert_rendered_white(button: Button, description: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var bounds := Rect2i(button.get_global_rect().grow(-6)).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	var bright := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var color := frame.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) > 0.90: bright += 1
	check(bright > 40, description + " renders white glyph pixels without a hover")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1100, 900); root.content_scale_size = root.size
	if DisplayServer.get_name() != "headless": root.unfocusable = true; root.position = Vector2i(-10000, -10000)
	motion = root.get_node("UiMotion"); motion.set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	for dark in [false, true]:
		root.get_node("AppState").dark_mode = dark
		canvas = Control.new(); canvas.theme = root.get_node("UiResources").page_theme
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(canvas)
		var background := ColorRect.new(); background.color = Styles.palette(dark).surface; background.size = Vector2(1100,900); background.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(background)
		var primary := make_button("主要操作：默认白字", 0, T.PRIMARY, true, dark)
		var custom := make_button("深蓝按钮：默认白字", 1, Color("#164AB9"), false, dark)
		var blue := make_button("蓝色按钮：默认白字", 2, Color("#416CD7"), false, dark)
		var disabled := make_button("禁用中：保留灰字区分", 3, T.PRIMARY, true, dark, true)
		var restored := make_button("恢复可用：不必悬停即为白字", 4, T.PRIMARY, true, dark, true)
		check(active_white(disabled) and not disabled.get_theme_color("font_disabled_color").is_equal_approx(Color.WHITE), "Disabled button keeps separate enabled-white and disabled-muted palettes")
		await frames()
		restored.disabled = false
		check(active_white(restored), "Enabling a button cannot expose disabled gray as its normal color")
		await frames()
		for button in [primary, custom, blue, restored]:
			check(active_white(button), "Every enabled dark solid button uses white text in all interactive states")
			await assert_rendered_white(button, button.text)
		# Rebind repeatedly while disabled, as async dialogs and page refreshes do.
		for i in 3:
			restored.disabled = true
			UI.style_button(restored, Styles.palette(dark), true)
			await frames(2)
			restored.disabled = false
			motion.bind_button(restored, true)
			check(active_white(restored), "Restyling a disabled action does not cache muted text as its enabled color")
		await frames()
		await assert_rendered_white(restored, "Repeatedly rebound primary action")
		# Simulate the page factory's transparent binding followed by primary styling.
		var deferred := make_button("延迟绑定：保持白字", 5, Color.TRANSPARENT, false, dark, true)
		motion.bind_button.call_deferred(deferred, false)
		Styles.button(deferred, T.PRIMARY, true, dark)
		motion.bind_button.call_deferred(deferred, true)
		await frames(); deferred.disabled = false; await frames()
		check(active_white(deferred), "Deferred bindings preserve white text on the final dark fill")
		await assert_rendered_white(deferred, "Deferred primary action")
		var light := make_button("白底按钮：保留深色可读文字", 6, Color.WHITE, false, false)
		var link := make_button("透明文字按钮：保留强调色", 7, Color.TRANSPARENT, false, dark)
		link.add_theme_stylebox_override("normal", Styles.box(Color.TRANSPARENT,8))
		link.add_theme_color_override("font_color", T.DARK_ACCENT if dark else T.PRIMARY)
		motion.bind_button(link)
		check(not light.get_theme_color("font_color").is_equal_approx(Color.WHITE), "Light fills retain readable dark text")
		check(link.get_theme_color("font_color").is_equal_approx(T.DARK_ACCENT if dark else T.PRIMARY), "Transparent links retain their accent color")
		var semantic := Button.new(); semantic.text = "答案状态：保留语义颜色"; canvas.add_child(semantic)
		semantic.position = Vector2(80,673); semantic.size = Vector2(580,54)
		for state in ["normal","hover","pressed","disabled"]: semantic.add_theme_stylebox_override(state,Styles.box(Color("#173827"),8))
		semantic.add_theme_color_override("font_color",Color("#63D68A")); semantic.add_theme_color_override("font_disabled_color",Color("#A2ADBE"))
		motion.bind_button(semantic,false,true)
		check(semantic.get_theme_color("font_color").is_equal_approx(Color("#63D68A")), "Answer/status semantics are not replaced by the action-button policy")
		primary.mouse_entered.emit(); primary.button_down.emit(); await frames()
		check(active_white(primary), "Hover and press retain white action text")
		primary.button_up.emit(); primary.mouse_exited.emit(); await frames()
		check(active_white(primary), "Returning to idle retains white text")
		var hits := {"count": 0}
		disabled.pressed.connect(func(): hits.count += 1)
		for down in [true,false]:
			var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down; event.position=disabled.get_global_rect().get_center(); event.global_position=event.position; root.push_input(event,true)
		check(disabled.disabled and hits.count == 0, "Disabled buttons stay non-interactive")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("dark.png" if dark else "light.png"))
		canvas.queue_free(); await frames()
	print("BUTTON TEXT ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
