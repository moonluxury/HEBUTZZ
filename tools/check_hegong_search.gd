extends SceneTree
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _settle() -> void:
	for frame in 6:
		await process_frame
	await create_timer(0.32).timeout

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		push_error("Use run_workbench_checks.py --script check_hegong_search.gd for isolated saves.")
		quit(2)
		return
	change_scene_to_file("res://scenes/HegongKaiwu.tscn")
	await _settle()
	var page := current_scene
	_expect(page.visible_entries.size() == 4, "Keep four existing course examples")
	page.search_edit.text = "热泵"
	page.search_edit.text_changed.emit("热泵")
	_expect(page.visible_entries.size() == 1 and page.visible_entries[0].title == "建筑冷热源", "Search resource keywords")
	page._open_entry(page.visible_entries[0])
	_expect(page.list_root.find_child("Preview", true, false) != null, "Expand demo preview without fabricating an article")
	page._open_entry(page.visible_entries[0])
	_expect(page.list_root.find_child("Preview", true, false) == null, "Collapse demo preview instantly")
	page._select_category("校园故事")
	_expect(page.visible_entries.is_empty(), "Empty category")
	page._clear_filters()
	_expect(page.visible_entries.size() == 4 and page.search_edit.text.is_empty(), "Clear filters")
	_expect(not page.list_root.has_node("Sorts"), "Resource sorting controls removed")
	_expect(page.visible_entries == page.entries, "Resources retain their source order after clearing filters")
	page._select_category("优秀文章")
	_expect(page.visible_entries.is_empty(), "Keep excellent articles category")
	page._clear_filters()
	var app := root.get_node("AppState")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	_expect(page.dark and page.list_root.get_theme_stylebox("panel").bg_color.a == 0, "Dark resource layout")
	app._set_font_scale(1.8)
	await _settle()
	_expect(page.list_root.size.x <= page.scroll.size.x, "Resource content fits large text layout")
	_expect(get_processed_tweens().is_empty(), "No page, hover or button animations")
	for control in page.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "No hover descriptions")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
