extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/collection_catalog.json"))
	check(catalog is Dictionary and catalog.cards.size() == 7, "Pack contains approved catalogue")
	var back := load(str(catalog.seasons[0].back_image)) as Texture2D
	check(back != null and back.get_size() == Vector2(1024, 1536), "Pack contains the original common card back")
	for card in catalog.cards:
		var texture := load(str(card.image)) as Texture2D
		check(texture != null and texture.get_size() == Vector2(1024,1536), "Pack contains full original card: " + str(card.id))
		var artwork := load(str(card.artwork)) as Texture2D
		check(artwork != null and artwork.get_size() == Vector2(1145,1374), "Pack contains standalone illustration: " + str(card.id))
	check(not FileAccess.file_exists("res://tools/fixtures/collection_provider.gd"), "Fixture is excluded by existing tools/.gdignore")
	root.get_node("PageRouter").go("res://scenes/MyCollection.tscn")
	await scene_changed
	await process_frame
	var page := current_scene
	page._set_filter("all")
	check(page.tiles.size() == 7, "Packed collection renders all seven cards")
	page._select_card("0001")
	check(page.detail_panel.get_node("Name").text == "火箭", "Packed detail uses actual metadata")
	for index in 300:
		if page.reveal.state != "loading":
			break
		await create_timer(0.01).timeout
	check(page.reveal.state in ["ready", "revealing", "revealed"], "Packed reveal loads its shader and both faces")
	if DisplayServer.get_name() != "headless":
		page.reveal._kill_tween()
		page.reveal._set_elapsed(0.36 + 0.91)
		await RenderingServer.frame_post_draw
	page.reveal.skip()
	check(page.reveal.state == "revealed" and page.reveal.face.texture.resource_path == catalog.cards[0].image, "Packed reveal reaches the exact final card")
	page._return_overview()
	await create_timer(0.2).timeout
	print("COLLECTION PACK CHECK: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
