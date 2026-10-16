extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/" + filename)


func _run() -> void:
	var state = root.get_node("AppState")
	state.set_process(false)
	await _settle()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 945)
	await _settle()
	var page = load("res://scenes/HegongKaiwu.tscn").instantiate()
	root.add_child(page)
	await create_timer(0.85).timeout
	var results = page.search_results
	_expect(page.visible_entries.size() == 4, "Default view should show all four course examples")
	_expect(page.categories == ["全部类型", "复习资料", "校园故事", "优秀文章"], "Top menu should show the requested content types in order")
	_expect(results.filter_buttons.size() == 4 and results.filter_buttons[1].text == "复习资料  ·  4", "Sidebar should group all course examples under review materials")
	_expect(page.submission_button.get_theme_font_size("font_size") == 30, "Announcement text size must stay at 30")
	_expect(page.submission_button.get_node("MorphIcon").size == Vector2(28, 28), "Announcement icon must stay 28 by 28")
	print("LAYOUT: panel=", results.size, " list=", results.results_scroll.size, " content=", results.results_column.size)
	await _capture("search_results_light.png")
	page.search_edit.text = "热泵"
	page.search_edit.text_submitted.emit("热泵")
	await _settle()
	_expect(page.visible_entries.size() == 1 and page.visible_entries[0].title == "建筑冷热源", "Keyword search should find the matching course")
	_expect(results.category_counts.get("", 0) == 1 and results.category_counts.get("复习资料", 0) == 1, "Category counts must reflect the current query")
	var row = results.results_column.get_node("Result0").get_child(0)
	var title = row.find_child("Title", true, false)
	var preview = row.get_node("Preview")
	title.pressed.emit()
	await _settle()
	_expect(preview.visible, "Clicking a demo title should expand its preview")
	_expect(state.hegong_kaiwu_article.is_empty(), "Demo preview must not navigate to a real article")
	await _capture("search_results_preview.png")
	title.pressed.emit()
	_expect(not preview.visible, "Preview should collapse on the next click")
	page.search_edit.text = "不存在的课程"
	page.search_button.pressed.emit()
	await _settle()
	_expect(page.visible_entries.is_empty(), "Unmatched query should show an empty result state")
	await _capture("search_results_empty.png")
	results.filters_cleared.emit()
	await _settle()
	_expect(page.visible_entries.size() == 4 and page.search_edit.text.is_empty(), "Clear filters should restore every course")
	results.filter_buttons[2].pressed.emit()
	await _settle()
	_expect(page.visible_entries.is_empty(), "Campus stories should show an empty state until content is added")
	_expect(page.selected_category == "校园故事" and page.category_button.text.begins_with("校园故事"), "Sidebar selection should synchronize the top menu")
	page.category_column.get_child(3).pressed.emit()
	await _settle()
	_expect(page.visible_entries.is_empty() and results.active_category == "优秀文章", "Excellent articles should remain available with no entries")
	_expect(bool(results.filter_buttons[3].get_meta("selected")), "Top menu selection should update the sidebar highlight")
	page.category_column.get_child(1).pressed.emit()
	await _settle()
	_expect(page.visible_entries.size() == 4 and results.active_category == "复习资料", "Review materials should show all four examples from either filter")
	results.filters_cleared.emit()
	results.sort_select.select(1)
	results.sort_select.item_selected.emit(1)
	await _settle()
	_expect(results.results_column.get_node("Result0").find_child("Title", true, false).text == "工程热力学", "Course-name sorting should reorder rows")
	state.dark_mode = true
	state.color_mode_changed.emit(true)
	await _settle()
	_expect(results.is_dark, "Search results should follow dark mode")
	await _capture("search_results_dark.png")
	state._set_font_scale(1.8)
	await _settle()
	_expect(page.submission_button.get_node("MorphIcon").size == Vector2(28, 28), "Font zoom must not change the announcement icon")
	_expect(results.results_column.size.x <= results.results_scroll.size.x, "Result content must not overflow horizontally at maximum text size")
	await _capture("search_results_large.png")
	page.queue_free()
	await process_frame
	print("SEARCH UI: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
