extends "res://tools/check_minimal_design.gd"
const T = preload("res://scripts/ui_tokens.gd")
var motion: Node

func _mount(scene: String) -> Node:
	change_scene_to_file("res://scenes/" + scene + ".tscn")
	await process_frame
	await process_frame
	return current_scene

func _frame(name: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(OUT + name + ".png")
	return frame

func _blue_extent(frame: Image, control: Control) -> Vector2:
	var rect := control.get_global_rect()
	var left := -1
	var right := -1
	for x in range(maxi(0, int(rect.position.x)), mini(frame.get_width(), ceili(rect.end.x))):
		for y in range(maxi(0, int(rect.position.y)), mini(frame.get_height(), ceili(rect.end.y))):
			var color := frame.get_pixel(x, y)
			if color.b > 0.35 and color.r < 0.2 and color.g < 0.3:
				left = x if left < 0 else left
				right = x
				break
	return Vector2(left, right)

func _finish() -> void:
	await create_timer(T.DATA + 0.1).timeout

func _run() -> void:
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	motion = root.get_node("UiMotion")
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	root.content_scale_size = Vector2i(1600, 984)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	motion.system_reduced = 0
	motion.suspended = false
	motion.set_enabled(true)
	# Fixture data lives only in the runner's isolated save directory.
	var days: Array = stats.recent_days()
	var counts := [0, 2, 1, 4, 2, 3, 7]
	for index in days.size():
		var questions := {}
		for number in counts[index]:
			questions["python:%d" % number] = true
		stats.history[days[index].date] = {"questions": questions, "attempts": counts[index] + index, "correct": counts[index]}
	for subject in app.SUBJECTS:
		var ids := []
		for index in 4:
			ids.append(stats.banks[subject][index].id)
			if index < 2:
				stats.learned["%s:%s" % [subject, stats.banks[subject][index].id]] = true
		var file := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(ids))
	var page: Node = await _mount("Workbench")
	var chart: Node = page.trend_chart
	var bar: ProgressBar = page.distribution.get_node("single/Bar")
	var true_value := bar.value
	var caption: String = page.distribution.get_node("single/Percent").text
	await create_timer(T.DATA * 0.28).timeout
	_expect(chart.reveal.amount > 0 and chart.reveal.amount < 1, "Trend reveals over time")
	_expect(bar.reveal.amount > 0 and bar.reveal.amount < 1, "Progress fill reveals over time")
	_expect(bar.value == true_value and page.distribution.get_node("single/Percent").text == caption, "Progress values and labels stay truthful during reveal")
	_expect(chart.days == stats.recent_days(), "Trend animation retains actual data")
	var middle: Image = await _frame("data-home-expanding")
	if middle != null:
		var ink := _blue_extent(middle, chart)
		_expect(ink.x >= chart.global_position.x and ink.y < chart.get_global_rect().end.x - 26, "Rendered trend has ink on the left and no final line/dot yet")
		var fill := _blue_extent(middle, bar)
		var final_edge := bar.get_global_rect().position.x + bar.get_global_rect().size.x * bar.get_as_ratio()
		_expect(fill.x >= bar.global_position.x and fill.y < final_edge - 2, "Rendered progress fill is only partially revealed")
	await _finish()
	_expect(chart.reveal.amount == 1 and bar.reveal.amount == 1, "All visible visuals reach the final state")
	var complete: Image = await _frame("data-home-complete")
	if complete != null:
		var ink := _blue_extent(complete, chart)
		_expect(ink.y > chart.get_global_rect().end.x - 24, "Final trend dot appears at the right end")
	var old_chart: Node = chart
	stats.record_answer("python", stats.banks.python[20], false)
	stats.record_answer("python", stats.banks.python[21], true)
	_expect(page.trend_chart == old_chart and chart.days == stats.recent_days(), "Rapid data changes keep the chart and latest data")
	_expect(is_equal_approx(page.stat_cards[1].get_node("Progress").value, stats.summary().percent), "Updated progress value is immediately current")
	await _finish()
	_expect(chart.reveal.amount == 1, "Rapid data updates finish cleanly")
	app.quiz_mode = "wrong"
	page = await _mount("SubjectSelect")
	var offscreen: ProgressBar = page.cards[3].get_node("Progress")
	await _finish()
	_expect(offscreen.reveal.waiting and offscreen.reveal.amount == 0, "Offscreen course progress waits for scrolling")
	_expect(page.wrong_chart.get_node("Chart").reveal.amount == 1, "Wrong trend uses the same reveal")
	page.scroll.scroll_vertical = 10000
	await create_timer(T.DATA * 0.2).timeout
	_expect(not offscreen.reveal.waiting and offscreen.reveal.amount > 0 and offscreen.reveal.amount < 1, "Scrolling a course into view starts its progress reveal")
	_expect(is_equal_approx(offscreen.value, 50.0), "Wrong course progress remains the actual reviewed ratio")
	await _frame("data-wrong-scrolled-expanding")
	motion.set_enabled(false)
	_expect(offscreen.reveal.amount == 1 and motion.tracks.is_empty(), "Reduced motion completes active and waiting visuals")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await process_frame
	_expect(page.cards[3].get_node("Progress").reveal.amount == 1, "Reduced motion also applies to rebuilt/offscreen controls")
	page.scroll.scroll_vertical = 10000
	await _frame("data-wrong-dark-complete")
	motion.set_enabled(true)
	app.quiz_mode = "all"
	page = await _mount("SubjectSelect")
	var course_bar: ProgressBar = page.cards[0].get_node("Progress")
	await create_timer(T.DATA * 0.2).timeout
	_expect(course_bar.reveal.amount > 0 and course_bar.reveal.amount < 1, "Total bank course cards use the shared reveal")
	page = await _mount("MyCollection")
	await _finish()
	_expect(motion.tracks.is_empty() and get_processed_tweens().is_empty(), "Leaving animated content cleans up all tracks")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
