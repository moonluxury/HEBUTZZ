extends SceneTree
## Exercise native search fields and embedded selectors at the reported project scale.
const Fixture = preload("res://tools/fixtures/social_provider.gd")
var failures: Array[String] = []
var checks := 0
var page: Node
var output := "res://.godot_appdata/input-clarity/verified"

func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func frames(count := 16) -> void:
	for i in count: await process_frame
func visit(scene: String) -> void:
	root.get_node("PageRouter").go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await frames()
	page = current_scene
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func search_check(field: LineEdit, name: String) -> void:
	var resources := root.get_node("UiResources")
	check(field.get_theme_font("font") == resources.regular, name + ": search uses surrounding text's shared font")
	check(field.get_theme_font("font").oversampling >= 4, name + ": input and placeholder retain high-resolution glyphs")
	check(field.get_theme_color("font_color").a == 1 and field.get_theme_color("font_placeholder_color").a == 1, name + ": no extra translucent text layer")
	field.text = "中文搜索 ABC 123"
	field.grab_focus()
	field.select_all()
	await frames()
	check(field.get_selected_text() == field.text, name + ": native selection remains available")
	await capture(name + "-text")
	field.deselect()
	field.clear()
	field.release_focus()
	await frames()
	await capture(name + "-placeholder")
	if field.get_window() != root and DisplayServer.get_name() != "headless":
		var owner := field.get_window()
		var density := maxf(1.0, root.get_stretch_transform().get_scale().x)
		check(owner.get_texture().get_image().get_size() == Vector2i((Vector2(owner.size) * density).ceil()), name + ": input dialog keeps full render density")
	var menu := field.get_menu()
	menu.popup(Rect2i(600,300,300,200))
	await frames()
	check(menu.has_node("UiPopupDensity"), name + ": input context menu receives density policy")
	menu.hide()
func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event,true)
		await process_frame
func open_choice(window: Window, choice: OptionButton) -> PopupMenu:
	await click(Vector2(window.position) + window.get_stretch_transform() * choice.get_global_rect().get_center())
	await frames()
	return choice.get_popup()
func choice_check(window: Window, choice: OptionButton, name: String) -> void:
	var popup := await open_choice(window,choice)
	check(popup.visible, name + ": native selector opens")
	check(popup.get_theme_font("font") == choice.get_theme_font("font"), name + ": open and closed text share the font")
	var geometry := Rect2i(popup.position,popup.size)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var density := maxf(1.0,root.get_stretch_transform().get_scale().x)
		var required := Vector2i((Vector2(popup.size) * density).ceil())
		check(popup.get_texture().get_image().get_size() == required, name + ": popup raster matches dialog density")
		check(popup.oversampling_override >= maxf(1.0,popup.content_scale_factor * density), name + ": vector markers have enough raster detail")
	await capture(name)
	await frames()
	check(Rect2i(popup.position,popup.size) == geometry, name + ": improving density keeps placement and hit areas fixed")
	# Select row zero by actual pointer input in the root's logical coordinates.
	var panel := popup.get_theme_stylebox("panel")
	var first_row_y := panel.content_margin_top + (popup.get_theme_font("font").get_height(popup.get_theme_font_size("font_size")) + popup.get_theme_constant("v_separation")) * 0.5
	await click(Vector2(popup.position) + Vector2(60,first_row_y) * popup.content_scale_factor)
	await frames()
	check(not popup.visible and choice.selected == 0, name + ": mouse selects the expected row")
	popup = await open_choice(window,choice)
	popup.set_focused_item(0)
	for key in [KEY_DOWN,KEY_ENTER]:
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.keycode = key
			event.pressed = pressed
			root.push_input(event)
			await process_frame
	await frames()
	check(not popup.visible and choice.selected == 1, name + ": keyboard navigation still selects the expected row")
	popup.hide()
func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.unfocusable = true
	if DisplayServer.get_name() != "headless": root.position = Vector2i(-10000,-10000)
	root.content_scale_size = Vector2i(2560,1680)
	root.size = Vector2i(1440,840)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	var api := Fixture.new()
	root.add_child(api)
	api.stocks[Fixture.A] = {"0001":7,"0002":7,"0003":7,"0004":7,"0005":7,"0006":7,"0007":7}
	api.relationships[api.pair(Fixture.A,Fixture.B)] = true
	root.get_node("ProfileStore").use_provider(api,{"state":"authenticated","account_id":Fixture.A})
	var collection: Node = root.get_node("AppServices").collection_store()
	var social: Node = root.get_node("AppServices").social_store()
	await collection.refresh()
	social.refresh()
	await visit("SubjectSelect")
	await search_check(page.search_edit,"01-bank")
	await visit("HegongKaiwu")
	await search_check(page.search_edit,"02-resources")
	await visit("MyFriends")
	await search_check(page.search,"03-friends")
	page.show_panel("add",{})
	await frames(24)
	await search_check(page.dialog.query,"03-add-friend")
	page.dialog.dismiss()
	await frames()
	page.show_panel("gift",{"peer":api.users[Fixture.B]})
	await frames(30)
	await search_check(page.gift_dialog.search,"04-gift")
	page.gift_dialog.dismiss()
	await frames()
	page.show_panel("exchange",{"peer":api.users[Fixture.B],"give_card_id":"0004","receive_card_id":"0002"})
	await frames(30)
	var trade: Window = page.dialog
	await choice_check(trade,trade.give,"05-exchange-reported-scale")
	for config in [[Vector2i(1600,1000),Vector2i(2000,1250),false,"06-exchange-125"], [Vector2i(1600,1000),Vector2i(2400,1500),true,"07-exchange-dark-150"]]:
		root.content_scale_size = config[0]
		root.size = config[1]
		root.get_node("AppState").dark_mode = config[2]
		root.get_node("AppState").color_mode_changed.emit(config[2])
		await frames(24)
		await choice_check(trade,trade.receive,config[3])
	trade.dismiss()
	await frames()
	check(not is_instance_valid(trade), "Closing a menu owner cleans up the density observer")
	print("WORKBENCH CHECKS: ","PASS" if failures.is_empty() else "FAIL"," (",checks," checks; ",failures.size()," failures)")
	quit(0 if failures.is_empty() else 1)
