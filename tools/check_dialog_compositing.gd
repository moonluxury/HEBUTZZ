extends SceneTree
## Run with run_workbench_checks.py --script check_dialog_compositing.gd --visual.
## Verify final page composition, not only a transparent child viewport.
const ProfileFixture = preload("res://tools/fixtures/profile_provider.gd")
const LoginFixture = preload("res://tools/fixtures/remembered_login_provider.gd")
const LoginDialog = preload("res://scripts/backend_login_dialog.gd")
var failures: Array[String] = []
var checked := 0
var output := "res://.godot_appdata/dialog-compositing"

func _init() -> void:
	_run.call_deferred()

func frames(count := 8) -> void:
	for index in count: await process_frame

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func visit(scene: String) -> Node:
	root.get_node("PageRouter").go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await frames()
	return current_scene

func inspect(window: Window, name: String, surface: Color) -> void:
	window.hide()
	await frames()
	await RenderingServer.frame_post_draw
	var background := root.get_texture().get_image()
	window.show()
	await frames()
	await RenderingServer.frame_post_draw
	var composed := root.get_texture().get_image()
	var source := window.get_texture().get_image()
	var scale := Vector2(composed.get_size()) / root.get_visible_rect().size
	var bounds := Rect2(Vector2(window.position) * scale, Vector2(window.size) * scale)
	var outer := Rect2i(bounds.grow(4)).intersection(Rect2i(Vector2i.ZERO, composed.get_size()))
	var inner := Rect2i(bounds.grow(-18))
	var strips: Array[Rect2i] = [Rect2i(outer.position, Vector2i(outer.size.x, inner.position.y - outer.position.y)), Rect2i(Vector2i(outer.position.x, inner.end.y), Vector2i(outer.size.x, outer.end.y - inner.end.y)), Rect2i(Vector2i(outer.position.x, inner.position.y), Vector2i(inner.position.x - outer.position.x, inner.size.y)), Rect2i(Vector2i(inner.end.x, inner.position.y), Vector2i(outer.end.x - inner.end.x, inner.size.y))]
	var invalid := 0
	for strip in strips:
		for y in range(strip.position.y, strip.end.y):
			for x in range(strip.position.x, strip.end.x):
				var sample := (Vector2(x + 0.5, y + 0.5) - bounds.position) / bounds.size * Vector2(source.get_size()) - Vector2(0.5, 0.5)
				if bounds.has_point(Vector2(x + 0.5, y + 0.5)):
					var opaque := true
					for dy in [0, 1]:
						for dx in [0, 1]:
							if source.get_pixel(clampi(int(floorf(sample.x)) + dx, 0, source.get_width() - 1), clampi(int(floorf(sample.y)) + dy, 0, source.get_height() - 1)).a < 0.999: opaque = false
					# Opaque form content may legitimately meet a scroll viewport edge.
					if opaque: continue
				var beneath := background.get_pixel(x, y)
				var actual := composed.get_pixel(x, y)
				var margin := 3.0 / 255.0
				if actual.r < minf(beneath.r, surface.r) - margin or actual.g < minf(beneath.g, surface.g) - margin or actual.b < minf(beneath.b, surface.b) - margin or actual.r > maxf(beneath.r, surface.r) + margin or actual.g > maxf(beneath.g, surface.g) + margin or actual.b > maxf(beneath.b, surface.b) + margin:
					invalid += 1
	check(invalid == 0, name + " has no foreign outline in the final composed image: " + str(invalid))
	if name in ["fractional-light-avatar", "fractional-light-edit", "fractional-light-login"]:
		composed.save_png(output.path_join(name + "-page.png"))
	print(name, ": ", invalid, " edge anomalies")
	checked += 1

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Final compositing requires --visual.")
		quit(2)
		return
	output = output.path_join(RenderingServer.get_current_rendering_method())
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(2560, 1500)
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	root.gui_embed_subwindows = true
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	var profile := ProfileFixture.new()
	root.add_child(profile)
	root.get_node("ProfileStore").use_provider(profile, {"state": "authenticated", "account_id": "test-account-a"})
	var login := LoginFixture.new()
	login.base_url = "https://dialog-surface.test"
	root.add_child(login)
	await frames()
	for configuration in [["fractional", Vector2i(2560, 1680), Vector2i(2560, 1500)], ["125-percent", Vector2i(1600, 1000), Vector2i(2000, 1250)]]:
		root.content_scale_size = configuration[1]
		root.size = configuration[2]
		root.position = Vector2i(-10000, -10000)
		await frames(16)
		for dark in [false, true]:
			root.get_node("AppState").dark_mode = dark
			root.get_node("AppState").color_mode_changed.emit(dark)
			await frames()
			var prefix: String = str(configuration[0]) + ("-dark-" if dark else "-light-")
			var page := await visit("PersonalCenter")
			for mode in ["edit", "account", "avatar"]:
				page.show_panel(mode)
				await inspect(page.dialog, prefix + mode, page.surface)
				page.dialog.dismiss()
				await frames()
			for password_mode in [false, true]:
				var dialog := LoginDialog.new()
				dialog.provider = login
				dialog.password_mode = password_mode
				page.add_child(dialog)
				dialog.present()
				await inspect(dialog, prefix + ("password" if password_mode else "login"), page.surface)
				if not password_mode:

					dialog._mode_changed(1)
					await inspect(dialog, prefix + "register", page.surface)
				check(dialog.submit.get_global_rect().end.y <= dialog.get_visible_rect().size.y, "Account actions remain inside the borderless window")
				var shade := dialog.shade
				dialog.close_button.pressed.emit()
				await frames()
				check(not is_instance_valid(dialog) and not is_instance_valid(shade), "In-panel close removes the account window and shade")
			page = await visit("MyCollection")
			await page.store.refresh()
			page._open_gift("0001")
			await inspect(page.gift_dialog, prefix + "gift", page.surface)
			page.gift_dialog.dismiss()
			await frames()
			page = await visit("MyFriends")
			page.show_panel("add")
			await inspect(page.dialog, prefix + "friend", page.surface)
			page.dialog.dismiss()
			await frames()
			page = await visit("Recharge")
			page.show_panel("rules")
			await inspect(page.dialog, prefix + "recharge", page.surface)
			page.dialog.dismiss()
			await frames()
	print("DIALOG COMPOSITING: %d rendered windows; all translucent edges compared against their actual background" % checked)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
