extends SceneTree
## Real Escape input across nested layers; all persistence uses isolated saves.
const ProfileFixture = preload("res://tools/fixtures/profile_provider.gd")
var failures: Array[String] = []
var assertions := 0
var app: Node
var router: Node

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count := 5) -> void:
	for frame in count:
		await process_frame

func visit(scene: String, mode := "all") -> Node:
	app.quiz_mode = mode
	router.go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await frames()
	return current_scene

func escape(window: Window = null, repeat := false) -> void:
	if window == null:
		window = root
	var target := root if window.is_embedded() else window
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		event.echo = repeat and pressed
		if is_instance_valid(target):
			target.push_input(event, true)
		await process_frame
	await frames()

func at(scene: String) -> bool:
	return current_scene.scene_file_path == "res://scenes/" + scene + ".tscn"

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		push_error("Use tools/run_workbench_checks.py to isolate saves.")
		quit(2)
		return
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	root.content_scale_size = Vector2i(1600, 984)
	root.gui_embed_subwindows = true
	root.get_node("UiMotion").set_enabled(false)
	app = root.get_node("AppState")
	router = root.get_node("PageRouter")
	var home: Node = await visit("Workbench")
	await escape()
	check(current_scene == home, "Escape on the root page stays on the root page")
	home._show_history()
	await frames()
	await escape(null, true)
	check(is_instance_valid(home.detail_overlay), "Key repeat cannot close another layer")
	await escape()
	check(current_scene == home and home.detail_overlay == null, "History closes without leaving the workbench")

	var bank: Node = await visit("SubjectSelect")
	bank.search_edit.text = "python"
	bank.search_edit.text_changed.emit("python")
	bank.filter_button.get_popup().popup(Rect2i(800, 240, 260, 220))
	await frames()
	await escape(bank.filter_button.get_popup())
	check(current_scene == bank and not bank.filter_button.get_popup().visible, "Escape closes the filter menu before navigating")
	check(bank.query == "python", "Closing a menu preserves the current search")
	bank.cards_root.get_node("python/CourseAction").pressed.emit()
	await scene_changed
	await frames()
	var quiz: Node = current_scene
	quiz._toggle_wrong_current()
	quiz.jump_input.grab_focus()
	await escape(null, true)
	check(current_scene == quiz, "Holding Escape does not navigate through multiple pages")
	await escape()
	check(current_scene == bank and bank.page_mode == "all" and bank.query == "python", "Quiz returns to the cached total bank with its search intact")
	bank.cards_root.get_node("python/CourseAction").pressed.emit()
	await scene_changed
	await frames()
	quiz = current_scene
	for index in quiz.questions.size():
		if quiz.questions[index].type == "program":
			quiz._jump_to(index)
			break
	quiz.program_editor.editor.text = "print('Escape keeps the draft')"
	quiz.program_editor.editor.text_changed.emit()
	quiz.program_editor.editor.grab_focus()
	quiz.program_editor.editor.get_menu().popup(Rect2i(700, 300, 260, 260))
	await frames()
	await escape(quiz.program_editor.editor.get_menu())
	check(current_scene == quiz and not quiz.program_editor.editor.get_menu().visible, "The code editor context menu closes before returning from the quiz")
	await escape()
	check(current_scene == bank, "Escape from the focused code editor returns one page")
	check(app.program_drafts.values().has("print('Escape keeps the draft')"), "Returning preserves the code draft")
	bank.search_edit.grab_focus()
	await escape()
	check(at("Workbench"), "Escape works with the bank search field focused")
	var wrong: Node = await visit("SubjectSelect", "wrong")
	wrong.cards_root.get_node("python/CourseAction").pressed.emit()
	await scene_changed
	await frames()
	await escape()
	check(current_scene == wrong and wrong.page_mode == "wrong", "Wrong practice returns to the wrong bank, not the total bank")
	wrong.cards_root.get_node("python/CourseAction").pressed.emit()
	await scene_changed
	await frames()
	current_scene.home_button.pressed.emit()
	await scene_changed
	await frames()
	check(current_scene == wrong, "The quiz Return button follows the same parent as Escape")
	await escape()
	check(at("Workbench"), "The wrong bank returns to the workbench")

	quiz = await visit("Quiz")
	root.size = Vector2i(1100, 820)
	root.content_scale_size = Vector2i(1100, 820)
	await frames()
	quiz.minimal_view._toggle_rail()
	check(quiz.minimal_view.compact_rail_open, "The compact question drawer is open")
	await escape()
	check(current_scene == quiz and not quiz.minimal_view.compact_rail_open, "Escape closes an overlaid question drawer first")
	await escape()
	check(at("SubjectSelect"), "The next Escape leaves the quiz for its bank")
	root.size = Vector2i(1600, 984)
	root.content_scale_size = Vector2i(1600, 984)

	var resources: Node = await visit("HegongKaiwu")
	for entry in resources.entries:
		if entry.get("demo", false):
			resources._open_entry(entry)
			break
	check(resources.list_root.find_child("Preview", true, false) != null, "An inline resource preview is open")
	await escape()
	check(current_scene == resources and resources.active_preview.is_empty(), "Escape closes the resource preview first")
	resources.search_edit.text = "热泵"
	resources.search_edit.text_changed.emit("热泵")
	resources.tools_root.get_node("Announcement0").pressed.emit()
	await scene_changed
	await frames()
	await escape()
	check(current_scene == resources and resources.query == "热泵", "An article returns to its resource list with the filter intact")
	await escape()
	check(at("Workbench"), "The resource list returns to the workbench")

	var provider := ProfileFixture.new()
	root.add_child(provider)
	var collection: Node = await visit("MyCollection")
	collection.store.use_provider(provider, "isolated-back-account")
	await collection.store.refresh()
	collection._set_filter("all")
	collection._select_card("0001")
	await frames()
	collection._open_gift("0001")
	await frames()
	await escape(collection.gift_dialog)
	check(current_scene == collection and collection.gift_dialog == null and collection.in_detail, "Escape closes gift dialog and keeps the card detail")
	check(provider.transfers == 0, "Closing a gift dialog does not submit a gift")
	await escape()
	check(current_scene == collection and not collection.in_detail and collection.filter == "all", "The next Escape restores the collection overview")
	await escape()
	check(at("Workbench"), "The collection overview returns to the workbench")

	router.open_identity()
	await scene_changed
	await frames()
	var profile: Node = current_scene
	check(is_instance_valid(profile.dialog), "The anonymous login dialog is open")
	await escape(profile.dialog)
	check(current_scene == profile and profile.dialog == null, "Closing login leaves the personal center open")
	var profile_store: Node = root.get_node("ProfileStore")
	profile_store.use_provider(provider, {"state": "authenticated", "account_id": "test-account-a"})
	await frames()
	profile.show_panel("edit", profile.edit_button)
	await frames()
	var editor: Node = profile.dialog
	editor.fields.display_name.text = "未提交的编辑草稿"
	check(editor.find_children("*", "FileDialog", true, false).is_empty(), "Profile editing no longer offers an upload picker")
	await escape(editor)
	check(current_scene == profile and profile.dialog == null and provider.saves == 0, "Escape cancels the editor without saving")
	profile.show_panel("avatar", profile.avatar_button)
	await frames()
	await escape(profile.dialog)
	check(current_scene == profile and profile.dialog == null and provider.saves == 0, "Escape closes card-avatar settings without changing the avatar")
	await escape()
	check(at("Workbench"), "The personal center returns to the workbench")
	print("BACK NAVIGATION ASSERTIONS: %d" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
