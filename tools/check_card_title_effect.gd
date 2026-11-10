extends SceneTree
## GPU checks use the same native title/font factories as each application.
const Effect = preload("res://scripts/card_title_effect.gd")
var failures: Array[String] = []
var checks := 0
var motion: Node
var view: SubViewport
var label: Label
var effect: Node
var folder := "res://outputs/card-title-validation"
var pc := false

func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func pause(time: float) -> void: await create_timer(time).timeout
func frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func fixture(reduced := false, dark := false) -> void:
	motion.system_reduced = 0
	motion.suspended = false
	motion.set_enabled(not reduced)
	view = SubViewport.new()
	view.size = Vector2i(340, 96)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var holder := Control.new()
	holder.size = Vector2(view.size)
	view.add_child(holder)
	if pc:
		holder.theme = root.get_node("UiResources").page_theme
		label = load("res://scripts/account_dialog_ui.gd").label(holder, "获取卡牌", 30, Color.WHITE, true)
		label.size = Vector2(136, 46)
	else:
		var ui = load("res://core/ui/styles.gd")
		holder.theme = ui.make_theme()
		label = ui.label("获取卡牌", 24, Color.WHITE)
		holder.add_child(label)
		label.size = Vector2(240, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(24, 18)
	await frame()
	# Match the real parent Container's second layout after autowrap is shaped.
	label.size.y = 46 if pc else 44
	await frame()
	var original := snapshot()
	var native := view.get_texture().get_image()
	check(native.get_used_rect().has_area(), "Native font is actually rendered inside the capture viewport")
	effect = Effect.bind(label, dark)
	await frame()
	check(snapshot() == original, "Binding preserves font identity, type size, layout and wrapping")
	check(Effect.bind(label, dark) == effect and label.get_child_count() == 1, "Only one non-layout effect attaches to the original Label")
	if not reduced and not dark and effect.material != null:
		var gradient := view.get_texture().get_image()
		native.save_png(folder.path_join("native.png"))
		gradient.save_png(folder.path_join("gradient.png"))
		check(same_alpha(native, gradient), "Static gradient preserves exact native glyph alpha and antialiasing")

func snapshot() -> Dictionary:
	var result := {"font": label.get_theme_font("font").get_instance_id(), "size": label.get_theme_font_size("font_size"), "rect": label.get_rect(), "minimum": label.get_combined_minimum_size()}
	for property in ["horizontal_alignment", "vertical_alignment", "autowrap_mode", "text_direction", "language", "lines_skipped", "max_lines_visible", "visible_characters", "clip_text", "uppercase", "scale", "rotation", "pivot_offset", "size_flags_horizontal", "size_flags_vertical", "label_settings"]:
		result[property] = label.get(property)
	for constant in ["line_spacing", "paragraph_spacing", "outline_size", "shadow_outline_size", "shadow_offset_x", "shadow_offset_y"]: result[constant] = label.get_theme_constant(constant)
	for index in label.text.length(): result[str(index)] = label.get_character_bounds(index)
	return result

func same_alpha(a: Image, b: Image) -> bool:
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a: return false
	return true

func teardown() -> void:
	view.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("Title checks timed out"); quit(1))
	await process_frame
	pc = root.has_node("AppState")
	if not pc: folder = "res://../preview/card-title-validation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	motion = root.get_node("UiMotion")
	await fixture()
	var stable := view.get_texture().get_image()
	var prior_center := -1.0
	for progress in [0.125, 0.375, 0.625, 0.875]:
		effect._set_position(progress)
		effect._set_strength(Effect.STRENGTH)
		await frame()
		var swept := view.get_texture().get_image()
		swept.save_png(folder.path_join("sweep-%d.png" % int(progress * 1000)))
		check(same_alpha(stable, swept), "Sweep never changes glyph shape or adds a rectangle")
		var sum := 0.0
		var pixels := 0
		var lo := 10000
		var hi := -1
		var brightest := 0.0
		for y in stable.get_height():
			for x in stable.get_width():
				var before := stable.get_pixel(x, y)
				var after := swept.get_pixel(x, y)
				if before.a > 0.95 and after.r - before.r > 0.015:
					sum += x
					pixels += 1
					lo = mini(lo, x)
					hi = maxi(hi, x)
					brightest = maxf(brightest, after.r)
		var center := sum / maxi(pixels, 1)
		check(pixels > 0 and center > prior_center + effect._bounds.size.x * 0.12, "One continuous sweep moves across successive characters")
		check(hi - lo < effect._bounds.size.x * 0.23 and brightest < 0.8, "Soft highlight stays narrow and does not turn letters white")
		prior_center = center
	effect._set_strength(0.0)
	effect.set_waiting(true)
	effect.present()
	var fade = effect._fade
	effect.present()
	check(effect._fade == fade and effect.material.get_shader_parameter("title_alpha") == 0.0, "Repeated present does not duplicate the 200ms fade")
	await pause(0.12)
	check(effect.material.get_shader_parameter("title_alpha") > 0.0 and effect.material.get_shader_parameter("title_alpha") < 1.0 and effect.material.get_shader_parameter("sweep_strength") == 0.0, "Fade precedes the first sweep")
	await pause(0.14)
	check(effect.material.get_shader_parameter("title_alpha") == 1.0 and effect.material.get_shader_parameter("sweep_strength") > 0, "First 500ms sweep starts after the 200ms fade")
	await pause(0.52)
	check(effect._sweep == null and not effect._idle.is_stopped() and effect.material.get_shader_parameter("sweep_strength") == 0.0, "Title remains completely static between sweeps")
	await pause(6.28)
	check(effect._sweep == null, "No early idle sweeps before seven seconds")
	await pause(0.23)
	check(effect._sweep != null and effect.material.get_shader_parameter("sweep_strength") > 0, "Idle sweep recurs at approximately seven seconds")
	var position: float = effect.material.get_shader_parameter("sweep_position")
	effect.begin_opening()
	label.text = "正在开卡"
	await pause(0.04)
	check(effect.material.get_shader_parameter("sweep_strength") < Effect.STRENGTH and effect.material.get_shader_parameter("sweep_position") == position, "Starting a draw freezes the sweep path and smoothly removes its intensity")
	await pause(0.08)
	check(effect._sweep == null and effect._idle.is_stopped() and effect.material.get_shader_parameter("sweep_strength") == 0, "Opening cancels the highlight within 80ms without a pending timer")
	label.text = "获得卡牌"
	effect.set_waiting(true)
	check(not effect.waiting and effect._idle.is_stopped(), "Results stay static even if a late waiting update arrives")
	await teardown()
	await fixture()
	effect.set_waiting(true); effect.present()
	await pause(0.05)
	effect.close()
	var alpha: float = effect.material.get_shader_parameter("title_alpha")
	await pause(0.75)
	check(effect._fade == null and effect._sweep == null and effect._idle.is_stopped() and effect.material.get_shader_parameter("title_alpha") == alpha, "Closing during fade cancels all old work")
	await teardown()
	await fixture()
	effect.set_waiting(true); effect.present()
	await pause(0.32)
	label.hide()
	check(effect._fade == null and effect._sweep == null and effect._idle.is_stopped(), "Hiding the title cancels both animation and idle scheduling")
	label.show()
	motion.set_enabled(false)
	check(effect.material.get_shader_parameter("title_alpha") == 1 and effect.material.get_shader_parameter("sweep_strength") == 0 and effect._idle.is_stopped(), "Enabling reduced motion removes all title motion immediately")
	await teardown()
	await fixture(true)
	effect.set_waiting(true); effect.present()
	check(effect._fade == null and effect._sweep == null and effect._idle.is_stopped() and effect.material.get_shader_parameter("title_alpha") == 1.0, "Reduced motion opens as a static readable gradient")
	await teardown()
	await fixture(false, true)
	await frame()
	view.get_texture().get_image().save_png(folder.path_join("dark-gradient.png"))
	check(effect.material.get_shader_parameter("campus_blue") == Color("#81A8F3"), "Dark background receives a readable blue palette without backdrop changes")
	await teardown()
	ProjectSettings.set_setting("rendering/card_title/use_shader", false)
	await fixture()
	effect.set_waiting(true); effect.present()
	check(label.material == null and label.get_theme_color("font_color") == Color("#164AB9") and effect._fade == null, "Fallback retains native readable campus-blue text")
	await teardown()
	ProjectSettings.set_setting("rendering/card_title/use_shader", null)
	check(get_processed_tweens().is_empty(), "Unmounted titles leave no running animation tasks")
	print("TITLE EFFECT ASSERTIONS: ", checks)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
