extends SceneTree


func _init() -> void:
	_capture_preview.call_deferred()


func _capture_preview() -> void:
	var state = root.get_node("AppState")
	state.set_process(false)
	state.quiz_mode = "all"
	state.dark_mode = false
	for frame in 8:
		await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 860)
	var page = load("res://scenes/Quiz.tscn").instantiate()
	root.add_child(page)
	page._expand_header()
	await create_timer(0.8).timeout
	page.header_hover_timer.stop()
	var logo = page.university_logo
	print("LOGO: texture=", logo.texture.get_size(), " control=", logo.size,
		" transparent=", logo.texture.get_image().detect_alpha() != Image.ALPHA_NONE,
		" mipmaps=", logo.texture.get_image().has_mipmaps())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/quiz_logo_light.png")
	state.dark_mode = true
	state.color_mode_changed.emit(true)
	await create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/quiz_logo_dark.png")
	page.queue_free()
	await process_frame
	print("LOGO PREVIEW: completed")
	quit()
