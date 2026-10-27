extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://06_制作源文件/cards.json"))
	var card_scene := load("res://05_Godot组件/Card.tscn") as PackedScene
	check(card_scene != null, "Reusable card scene loads")
	if card_scene == null:
		quit(1)
		return
	for i in range(7):
		var card := card_scene.instantiate() as Control
		card.set("card_index", i)
		root.add_child(card)
		card.size = Vector2(512, 768)
		await process_frame
		var expected: Dictionary = items[i]
		check(card.get_node("Design/Title").text == expected["name"], "Chinese name: " + str(i))
		check(card.get_node("Design/English").text == expected["english"], "English name: " + str(i))
		check(card.get_node("Design/Number").text == expected["id"], "Number: " + str(i))
		check(card.get_node("Design/Illustration").texture != null, "Illustration loads: " + str(i))
		check(card.get_node("Design/Frame").texture.get_size() == Vector2(1024, 1536), "Common frame size")
		check(card.get_node("Design").scale.is_equal_approx(Vector2(0.5, 0.5)), "Proportional resizing")
		for label_name in ["Brand", "Series", "Number", "Title", "English"]:
			var label := card.get_node("Design/" + label_name) as Label
			var width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			check(width <= label.size.x, "Text fits: " + label_name + " / " + str(i))
		card.set("title_override", "测试名称")
		check(card.get_node("Design/Title").text == "测试名称", "Live title override")
		card.set("use_raster_text", true)
		check(card.get_node("Design/RasterText").visible and not card.get_node("Design/Title").visible, "Raster fallback toggle")
		card.set("show_back", true)
		await process_frame
		check(not card.get_node("Design").visible and card.get_node("Back").visible, "Switch to shared back")
		check(card.get_node("Back/Design").scale.is_equal_approx(Vector2(0.5, 0.5)), "Back resizes with front")
		check(card.get_node("Back/Design/RasterText").visible, "Back inherits raster text setting")
		check(card.get_node("Back/Design/Illustration").texture != null, "Back illustration loads")
		card.set("use_raster_text", false)
		check(card.get_node("Back/Design/Series").visible, "Back restores editable lettering")
		for back_name in ["Brand", "Series"]:
			var back_label := card.get_node("Back/Design/" + back_name) as Label
			var back_width := back_label.get_theme_font("font").get_string_size(back_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, back_label.get_theme_font_size("font_size")).x
			check(back_width <= back_label.size.x, "Back text fits: " + back_name)
		card.set("show_back", false)
		check(card.get_node("Design").visible and not card.get_node("Back").visible, "Return to original face")
		check(card.get_node("Design/Title").text == "测试名称", "Switch preserves front state")
		card.queue_free()
		await process_frame
	var scenes := DirAccess.get_files_at("res://05_Godot组件/cards")
	var inherited_count := 0
	for scene_file in scenes:
		if scene_file.ends_with(".tscn"):
			var inherited := load("res://05_Godot组件/cards/" + scene_file) as PackedScene
			check(inherited != null, "Independent scene loads: " + scene_file)
			inherited_count += 1
	check(inherited_count == 7, "Seven independent scenes")
	var gallery := (load("res://05_Godot组件/Gallery.tscn") as PackedScene).instantiate() as Control
	root.add_child(gallery)
	await process_frame
	check(gallery.get("card_nodes").size() == 8, "Gallery has seven faces and one shared back")
	gallery.queue_free()
	await process_frame
	print(JSON.stringify({"result": "PASS" if failures.is_empty() else "FAIL", "cards": 7, "editable_labels": true, "relative_resources": true, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
