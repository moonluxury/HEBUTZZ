extends SceneTree
const Fixture = preload("res://tools/fixtures/social_provider.gd")
var failures: Array[String] = []
var assertions := 0
var api: Node
var page: Node
var collection: Node
var social: Node
var output := "res://.godot_appdata/transfer-dialog-validation"
var checked := 0

class MeasuredFixture extends Fixture:
	var friends_requests := 0
	func social_request(action: String, payload: Dictionary) -> Dictionary:
		if action == "friends": friends_requests += 1
		return await super.social_request(action,payload)

func _init() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); push_error(label)

func frames(count := 12) -> void:
	for i in count: await process_frame

func visit(scene: String) -> void:
	root.get_node("PageRouter").go("res://scenes/"+scene+".tscn")
	await scene_changed
	await frames()
	page = current_scene

func capture(name: String, window: Window) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var screen := root.get_texture().get_image()
	screen.save_png(output.path_join(name+"-page.png"))
	var scale := Vector2(screen.get_size()) / root.get_visible_rect().size
	var bounds := Rect2i(Vector2(window.position)*scale,Vector2(window.size)*scale)
	screen.get_region(bounds.intersection(Rect2i(Vector2i.ZERO,screen.get_size()))).save_png(output.path_join(name+"-dialog.png"))

func check_choice(window: Window, choice: OptionButton, name: String) -> void:
	var selected := choice.selected
	var point := Vector2(window.position) + window.get_stretch_transform() * choice.get_global_rect().get_center()
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		root.push_input(click,true)
		await process_frame
	await frames()
	var popup := choice.get_popup()
	check(popup.visible,name+": the actual selector opens its native menu")
	check(popup.get_theme_stylebox("panel").bg_color == window.colors.surface and popup.get_theme_color("font_color") == window.colors.text,name+": expanded menu follows the dialog palette")
	check(popup.get_theme_font("font") == choice.get_theme_font("font") and popup.get_theme_font("font").oversampling >= 4.0,name+": expanded labels use the shared high-resolution font")
	check(popup.get_theme_icon("radio_checked") is DPITexture and choice.get_theme_icon("arrow") is DPITexture,name+": selection markers and arrow use scalable vectors")
	await capture(name,window)
	if DisplayServer.get_name() != "headless":
		popup.get_texture().get_image().save_png(output.path_join(name+"-menu.png"))
		print("CHOICE: ",name," position=",popup.position," size=",popup.size," logical=",popup.get_visible_rect().size," image=",popup.get_texture().get_image().get_size()," scale=",popup.content_scale_factor)
	popup.set_focused_item(selected)
	for code in [KEY_DOWN,KEY_ENTER]:
		for pressed in [true,false]:
			var key := InputEventKey.new()
			key.keycode = code
			key.pressed = pressed
			root.push_input(key)
			await process_frame
	await frames()
	check(not popup.visible and choice.selected == (selected+1)%choice.item_count,name+": keyboard selection updates the card and closes the menu")
	popup.hide()

func inspect(window: Window, name: String, surface: Color) -> void:
	if DisplayServer.get_name() == "headless": return
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
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1672,941)
	root.size = Vector2i(1672,941)
	if DisplayServer.get_name() != "headless": root.position = Vector2i(-10000,-10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	api = MeasuredFixture.new(); root.add_child(api)
	api.users[Fixture.A].name = "隔离测试用户"
	api.stocks[Fixture.A] = {"0001":7,"0002":7,"0003":7,"0004":7,"0005":7,"0006":7,"0007":7}
	for item in [[Fixture.B,"测试好友一","0004"],[Fixture.C,"测试好友二","0001"],[Fixture.D,"测试好友三","0006"],["test-account-e","测试好友四","0007"]]:
		api.users[item[0]] = {"id":item[0],"public_id":"QA-"+str(item[0]).right(1),"name":item[1],"avatar_card_id":item[2]}
		api.relationships[api.pair(Fixture.A,item[0])] = true
	root.get_node("ProfileStore").use_provider(api,{"state":"authenticated","account_id":Fixture.A})
	collection = root.get_node("AppServices").collection_store()
	social = root.get_node("AppServices").social_store()
	await collection.refresh(); social.refresh(); await frames()
	await visit("MyCollection")
	page._select_card("0003")
	page._open_gift("0003")
	await frames()
	var gift: Window = page.gift_dialog
	check(gift.friend_rows.size()==4,"The gift window renders the actual four fixture friends")
	gift.friend_rows[0].grab_focus()
	gift.friend_rows[0].pressed.emit()
	check(not gift.confirm.disabled and gift.quantity.max_value==6,"One copy is retained and a selected eligible friend enables confirmation")
	check(gift.card_art.texture.get_width()>=1000 and gift.card_art.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"Gift art uses the original high-resolution mipmapped image")
	check(gift.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"Gift content is rendered at UI scale rather than shrinking a small window")
	await capture("01-gift-selected",gift)
	await inspect(gift,"gift-light",page.surface)
	print("GIFT SIZE: ",gift.size," logical=",gift.get_visible_rect().size," scale=",gift.content_scale_factor," footer=",gift.confirm.get_global_rect())
	gift.quantity.get_meta("increase").pressed.emit()
	check(int(gift.quantity.value)==2 and gift.confirm.text.contains("2 张") and gift.remaining.text.contains("5 张"),"The horizontal stepper immediately updates quantity and remaining stock")
	gift.quantity.value=6
	check(gift.quantity.get_meta("increase").disabled,"The plus button cannot exceed the true transferable quantity")
	gift._search_friends("不存在的好友")
	await frames()
	check(gift.friend_rows.is_empty() and gift.friend_status.visible and gift.confirm.disabled,"An unmatched search renders an empty state and disables confirmation")
	await capture("02-gift-empty",gift)
	var query_count: int = api.friends_requests
	for query in ["测","测试","测试好友"]:
		gift.search.text = query
		gift.search.text_changed.emit(query)
	await create_timer(0.12).timeout
	check(api.friends_requests==query_count,"Typing multiple characters waits for the search debounce")
	await create_timer(0.22).timeout
	await frames()
	check(api.friends_requests==query_count+1 and gift.friend_rows.size()==4,"The final query produces one friend request")
	gift.dismiss(); await frames()
	check(not is_instance_valid(page.gift_dialog),"Closing a gift leaves no active window")
	await visit("MyFriends")
	var peer: Dictionary = social.friends[Fixture.B] if social.friends is Dictionary else api.users[Fixture.B]
	var original_stock: Dictionary = api.stocks[Fixture.A].duplicate(true)
	page._select(api.pair(Fixture.A, Fixture.B))
	await frames()
	page.more_button.grab_focus()
	page._peer_panel("peer_menu")
	await frames()
	page.dialog.rows.gift.pressed.emit()
	await create_timer(0.25).timeout
	await frames()
	gift = page.gift_dialog
	check(is_instance_valid(gift) and not is_instance_valid(page.dialog), "Friends gift opens the shared window directly, without a separate picker popup")
	check(gift.choose_card and gift.card_choice.item_count == 7, "The shared window offers actual eligible cards")
	check(gift.selected_friend.get("id") == Fixture.B and not gift.confirm.disabled, "The current friend is preselected only after the eligible-friend lookup")
	check(api.stocks[Fixture.A] == original_stock, "Opening the gift window does not transfer inventory")
	for index in gift.card_choice.item_count:
		if gift.card_choice.get_item_metadata(index) == "0003":
			gift.card_choice.select(index); gift.card_choice.item_selected.emit(index); break
	check(gift.card_id == "0003" and gift.card_art.texture.get_width() >= 1000, "Selecting a card updates the real high-resolution preview")
	await capture("friends-gift-selected", gift)
	await inspect(gift, "friends-gift-light", page.surface)
	gift.quantity.value = 4
	for index in gift.card_choice.item_count:
		if gift.card_choice.get_item_metadata(index) == "0002":
			gift.card_choice.select(index); gift.card_choice.item_selected.emit(index); break
	check(gift.card_id == "0002" and int(gift.quantity.value) == 1 and gift.selected_friend.id == Fixture.B, "Changing cards resets quantity and preserves the chosen friend")
	api.stocks[Fixture.A]["0002"] = 1
	await collection.refresh(); await frames()
	check(gift.card_id == "0002" and gift.confirm.disabled, "Stock loss disables the reviewed card without silently switching the gift")
	gift.dismiss(); await frames()
	check(not is_instance_valid(page.gift_dialog) and root.gui_get_focus_owner() == page.more_button, "Closing restores the conversation actions trigger")
	for id in api.stocks[Fixture.A]: api.stocks[Fixture.A][id] = 1
	await collection.refresh()
	page.show_panel("gift", {"peer":peer}); await frames()
	gift = page.gift_dialog
	check(gift.card_choice.disabled and gift.confirm.disabled and gift.card_id.is_empty(), "No eligible stock stays an honest empty state")
	await capture("friends-gift-empty", gift)
	gift.dismiss(); await frames()
	api.stocks[Fixture.A] = original_stock
	await collection.refresh()
	page.show_panel("gift", {"peer":peer}); await frames()
	gift = page.gift_dialog
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await frames(20)
	await capture("friends-gift-dark", gift)
	root.content_scale_size = Vector2i(600,680); root.size = Vector2i(600,680)
	await frames(20)
	check(gift.confirm.get_global_rect().end.y <= gift.get_visible_rect().size.y, "The friend gift picker keeps its confirmation footer inside a small window")
	await capture("friends-gift-small", gift)
	gift.dismiss(); await frames()
	root.content_scale_size = Vector2i(1672,941); root.size = Vector2i(1672,941)
	root.get_node("AppState").dark_mode = false
	root.get_node("AppState").color_mode_changed.emit(false)
	await frames()
	page.show_panel("exchange",{"peer":peer,"give_card_id":"0003","receive_card_id":"0002"})
	await frames()
	var trade: Window = page.dialog
	check(is_instance_valid(trade.give_amount) and not trade.confirmation.disabled,"Exchange shows selectable cards and quantities")
	check(trade.give_preview.art.texture.get_width()>=1000,"Exchange uses original high-resolution artwork")
	await capture("03-exchange-select",trade)
	await inspect(trade,"exchange-light",page.surface)
	await check_choice(trade,trade.give,"exchange-give-dropdown-light")
	await check_choice(trade,trade.receive,"exchange-receive-dropdown-light")
	trade.give_amount.value=2
	trade.receive_amount.value=3
	trade._review_create()
	await frames()
	check(trade.context.terms.give[0].quantity==2 and trade.context.terms.receive[0].quantity==3,"Review keeps both agreed quantities")
	await capture("04-exchange-review",trade)
	print("TRANSFER: return to editable terms")
	trade._edit_terms(); await frames()
	check(trade.give_amount.value==2 and trade.receive_amount.value==3,"Returning from review preserves the original draft")
	root.get_node("AppState").dark_mode=true
	root.get_node("AppState").color_mode_changed.emit(true)
	print("TRANSFER: dark theme")
	await frames(20)
	await capture("05-exchange-dark",trade)
	await inspect(trade,"exchange-dark",page.surface)
	await check_choice(trade,trade.give,"exchange-dropdown-dark")
	root.content_scale_size=Vector2i(600,680);root.size=Vector2i(600,680)
	await frames(20)
	check(trade.size.x<=600 and trade.size.y<=680 and trade.confirmation.get_global_rect().end.y<=trade.get_visible_rect().size.y,"A smaller window keeps exchange confirmation inside the fixed footer")
	await capture("06-exchange-small",trade)
	trade.scroll_box.scroll_vertical = 0
	await frames()
	await check_choice(trade,trade.give,"exchange-dropdown-small")
	root.content_scale_size=Vector2i(1600,1000);root.size=Vector2i(2000,1250)
	root.get_node("AppState").dark_mode=false;root.get_node("AppState").color_mode_changed.emit(false)
	await frames(20)
	await check_choice(trade,trade.give,"exchange-dropdown-dpi")
	trade.dismiss();await frames()
	root.content_scale_size=Vector2i(1672,941);root.size=Vector2i(1672,941)
	root.get_node("AppState").dark_mode=false;root.get_node("AppState").color_mode_changed.emit(false)
	await visit("MyCollection")
	page._open_gift("0003");await frames()
	gift=page.gift_dialog
	gift.friend_rows[0].pressed.emit()
	root.content_scale_size=Vector2i(600,680);root.size=Vector2i(600,680)
	await frames(20)
	check(gift.size.x<=600 and gift.size.y<=680 and gift.confirm.get_global_rect().end.y<=gift.get_visible_rect().size.y,"A smaller window keeps gift confirmation inside the fixed footer")
	await capture("07-gift-small",gift)
	gift.dismiss();await frames()
	for configuration in [[Vector2i(2560,1680),Vector2i(2560,1500)],[Vector2i(1600,1000),Vector2i(2000,1250)]]:
		root.content_scale_size=configuration[0];root.size=configuration[1]
		await frames(20)
		page._open_gift("0003");await frames(20)
		gift=page.gift_dialog
		gift.friend_rows[0].grab_focus();gift.friend_rows[0].pressed.emit()
		print("TRANSFER DPI: root=",root.size," window=",gift.size," image=",gift.get_texture().get_image().get_size()," logical=",gift.get_visible_rect().size)
		var pixel_scale := root.get_stretch_transform().get_scale().x
		if DisplayServer.get_name() != "headless": check(gift.get_texture().get_image().get_width() >= int(gift.size.x*pixel_scale),"The popup render target covers every physical display pixel")
		var point: Vector2 = Vector2(gift.position) + gift.get_stretch_transform() * gift.friend_rows[1].get_global_rect().get_center()
		for pressed in [true,false]:
			var event := InputEventMouseButton.new()
			event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
			root.push_input(event,true)
		await frames()
		check(gift.selected_friend.get("id")==gift.friend_rows[1].get_meta("friend_id"),"Physical mouse input matches the supersampled friend row")
		await capture("08-gift-dpi-"+str(root.size.x),gift)
		print("TRANSFER DPI AFTER INPUT: image=",gift.get_texture().get_image().get_size())
		if DisplayServer.get_name() != "headless": check(gift.get_texture().get_image().get_width() >= int(gift.size.x*pixel_scale),"Pointer interaction retains physical-pixel rendering")
		await inspect(gift,"gift-dpi-"+str(root.size.x),page.surface)
		gift.dismiss();await frames()
	root.content_scale_size=Vector2i(1672,941);root.size=Vector2i(1672,941)
	await frames(20)
	var motion := root.get_node("UiMotion")
	motion.set_enabled(true)
	motion.suspended=false
	motion.system_reduced=0
	var motion_frames: Array = []
	page._open_gift("0003")
	gift=page.gift_dialog
	for index in 14:
		await create_timer(0.016).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			motion_frames.append({"name":"motion-open-%02d.png"%index,"image":root.get_texture().get_image()})
	gift.dismiss()
	var partial_fade := false
	for index in 10:
		await create_timer(0.016).timeout
		for node in page.get_children():
			if node.get_meta("transfer_retiring",false) and node is Window and node.panel.modulate.a>0 and node.panel.modulate.a<1: partial_fade=true
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			motion_frames.append({"name":"motion-close-%02d.png"%index,"image":root.get_texture().get_image()})
	for frame in motion_frames: frame.image.save_png(output.path_join(frame.name))
	check(partial_fade,"The live exit controls visibly interpolate before being removed")
	check(not is_instance_valid(page.gift_dialog) and page.get_children().filter(func(n): return n.get_meta("transfer_retiring",false)).is_empty(),"Closing completes its fade and removes the modal and shade")
	page._open_gift("0003");page.gift_dialog.dismiss();page._open_gift("0003")
	await create_timer(0.25).timeout
	check(page.get_children().filter(func(n): return n is Window and n.visible).size()==1 and page.get_children().filter(func(n): return n.get_meta("transfer_retiring",false)).is_empty(),"Rapid reopen shows exactly one current modal and no old fading surface")
	page.gift_dialog.friend_rows[0].pressed.emit()
	var retiring: Window = page.gift_dialog
	var prior_transfers: int = api.transfers
	retiring.dismiss();retiring._submit()
	await create_timer(0.2).timeout
	check(api.transfers==prior_transfers,"A late callback cannot submit after the gift window has closed")
	check(page.detail_panel.get_node("Gift").has_focus(),"Closing returns focus to the actual gift trigger")
	print("TRANSFER DIALOG ASSERTIONS: ",assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL",failures.size()])
	quit(0 if failures.is_empty() else 1)
