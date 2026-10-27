extends "res://tools/check_minimal_design.gd"
const StatsScript = preload("res://scripts/study_stats.gd")
const T = preload("res://scripts/ui_tokens.gd")
var motion: Node

func _popup_check(choice: Button, name: String) -> void:
	await _click(choice)
	var popup: PopupMenu = choice.get_popup()
	_expect(popup.visible, name + ": native button opens its menu")
	_expect(popup.get_theme_font("font") == choice.get_theme_font("font"), name + ": menu shares the page font")
	_expect(popup.get_theme_font("font").oversampling >= 4.0, name + ": menu font keeps high resolution sampling")
	_expect(popup.get_theme_font_size("font_size") == choice.get_theme_font_size("font_size"), name + ": menu and button use the same type size")
	var expected := Color("#141C2A") if app.dark_mode else Color.WHITE
	_expect(popup.get_theme_stylebox("panel").bg_color == expected, name + ": menu follows the page palette")
	_expect(choice.get_theme_stylebox("normal").content_margin_left == 16, name + ": consistent button padding")
	print(name, " popup scale=", popup.content_scale_factor, " button screen scale=", choice.get_screen_transform().get_scale(), " size=", popup.size)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		popup.get_texture().get_image().save_png(OUT + "choice-" + name + ".png")
	popup.hide()
	await process_frame

func _select(choice: OptionButton, index: int) -> void:
	# This is the same native menu signal used by mouse/keyboard selection.
	choice.get_popup().index_pressed.emit(index)
	_expect(choice.selected == index, "Native menu selection updates the closed choice")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	motion = root.get_node("UiMotion")
	root.content_scale_size = Vector2i(1600, 984)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	motion.system_reduced = 0
	motion.suspended = false
	motion.set_enabled(true)
	var dates: Array = stats.recent_days()
	stats.history[dates[4].date] = {"questions": {"python:1": true}, "attempts": 4, "correct": 1}
	stats.history[dates[5].date] = {"questions": {"marxism:1": true, "xi:1": true}, "attempts": 5, "correct": 2}
	stats.record_answer("marxism", stats.banks.marxism[0], false)
	stats.record_answer("marxism", stats.banks.marxism[0], false)
	stats.record_answer("marxism", stats.banks.marxism[0], true)
	stats.record_answer("xi", stats.banks.xi[0], false)
	stats.record_answer("python", stats.banks.python[0], true)
	stats.record_review("matlab", stats.banks.matlab[0])
	_expect(stats.recent_wrong_days("marxism")[-1].count == 2, "Repeated wrong attempts are counted in their course")
	_expect(stats.recent_wrong_days("xi")[-1].count == 1, "Courses do not share wrong counts")
	_expect(stats.recent_wrong_days("matlab")[-1].count == 0, "Reviewing reference code is not a wrong answer")
	_expect(stats.recent_wrong_days("python")[4].count == 3, "Unambiguous single-course legacy history is preserved")
	_expect(stats.recent_wrong_days("marxism")[5].count == 0 and stats.recent_wrong_days("xi")[5].count == 0, "Mixed legacy totals are not guessed")
	_expect(stats.recent_wrong_days()[5].count == 3 and stats.has_unattributed_wrongs(), "Unattributed old totals remain in all courses")
	stats._save()
	var reloaded := StatsScript.new()
	root.add_child(reloaded)
	_expect(reloaded.recent_wrong_days("marxism")[-1].count == 2 and reloaded.recent_wrong_days("xi")[-1].count == 1, "Per-course counts survive save and reload")
	_expect(int(reloaded.history[dates[5].date].attempts) == 5 and int(reloaded.history[dates[5].date].correct) == 2, "Legacy aggregate totals survive migration")
	reloaded.queue_free()
	for subject in ["marxism", "xi", "python"]:
		var file := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		file.store_string(JSON.stringify([stats.banks[subject][0].id, stats.banks[subject][1].id]))
	app.quiz_mode = "wrong"
	var page: Node = await _open("SubjectSelect")
	var choice: OptionButton = page.body.get_node("SubjectFilter")
	await _popup_check(choice, "subjects-light")
	var chart: Node = page.wrong_chart.get_node("Chart")
	_select(choice, 1)
	_expect(page.wrong_subject == "marxism" and chart.days[-1].count == 2 and chart.reveal.amount == 0, "Selecting a course updates its data and restarts reveal immediately")
	await create_timer(T.DATA * 0.2).timeout
	_expect(chart.reveal.amount > 0 and chart.reveal.amount < 1, "Course switching restarts the trend animation")
	_select(choice, 3)
	_expect(chart.days[-1].count == 1 and chart.reveal.amount == 0, "Switching again uses the latest course")
	_select(choice, 4)
	await _settle()
	_select(choice, 6)
	_expect(chart.days == stats.recent_wrong_days("cpp") and chart.reveal.amount == 0, "Different courses with identical series still replay")
	_select(choice, 0)
	_expect(chart.days[-1].count == 3 and page.wrong_chart.get_node("Chart") == chart, "All courses restores aggregate data using the same chart")
	await _settle()
	await _capture("wrong-trends-all")
	_select(choice, 1)
	await _settle()
	await _capture("wrong-trends-marxism")
	motion.set_enabled(false)
	_select(choice, 3)
	_expect(chart.reveal.amount == 1 and chart.days[-1].count == 1, "Reduced motion selects the right course instantly")
	motion.set_enabled(true)
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	await _popup_check(page.body.get_node("SubjectFilter"), "subjects-dark")
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	await _settle()
	await _popup_check(page.body.get_node("SubjectFilter"), "subjects-scaled")
	app._set_font_scale(1.4)
	await _settle()
	await _popup_check(page.body.get_node("SubjectFilter"), "subjects-large-text")
	app._set_font_scale(1.0)
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	app.quiz_mode = "all"
	page = await _open("SubjectSelect")
	await _popup_check(page.filter_button, "progress-light")
	page.filter_button.get_popup().id_pressed.emit(2)
	_expect(page.progress_filter == 2 and page.cards.size() > 0, "Progress menu keeps native filtering behavior")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	await _popup_check(page.filter_button, "progress-dark")
	page = await _open("MyCollection")
	await _settle()
	_expect(motion.tracks.is_empty(), "Leaving selector pages cleans up their motion")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
