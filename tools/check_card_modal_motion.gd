extends SceneTree
## Shared PC/mobile animation contract. No wallet provider or account requests.
const Reveal = preload("res://scripts/card_reveal.gd")
const Modal = preload("res://scripts/card_modal_motion.gd")
var failures: Array[String] = []
var checks := 0
var motion: Node
var resources: Node
var card: Dictionary
var back_path: String
var host: Control
var group: Control
var shade: ColorRect
var modal: Node
var preview: Control

func _init() -> void: run.call_deferred()
func pause(seconds: float) -> void: await create_timer(seconds).timeout
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func loaded() -> void:
	for i in 400:
		if preview.state != "loading": return
		await process_frame
	check(false, "Textures finish decoding")

func setup(reduced := false) -> void:
	motion.suspended = false
	motion.system_reduced = 0
	motion.set_enabled(not reduced)
	host = Control.new()
	host.size = Vector2(760, 900)
	root.add_child(host)
	shade = ColorRect.new()
	shade.size = host.size
	shade.color = Color(0, 0, 0, 0.26)
	host.add_child(shade)
	group = Control.new()
	group.size = host.size
	host.add_child(group)
	preview = Reveal.new()
	preview.size = Vector2(360, 420)
	group.add_child(preview)
	modal = Modal.new()
	host.add_child(modal)
	modal.configure(shade, group)
	modal.layout(Vector2.ZERO)
	modal.entered.connect(preview.allow_reveal)
	var session := Reveal.new_session(card, back_path, checks)
	session.external_entry = true
	preview.present(session)
	await loaded()

func teardown() -> void:
	host.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("Motion checks timed out"); quit(1))
	OS.set_environment("HEGONG_BACKEND_DISABLED", "1")
	await process_frame
	root.unfocusable = true
	if DisplayServer.get_name() != "headless": root.position = Vector2i(-10000, -10000)
	motion = root.get_node("UiMotion")
	resources = root.get_node("UiResources")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/collection_catalog.json"))
	card = catalog.cards[0]
	back_path = catalog.seasons[0].back_image
	await setup()
	check(preview.state == "ready" and preview._tween == null, "Decoded result waits for modal entry completion")
	preview.size.x += 10
	preview._layout()
	check(preview.state == "ready" and preview.flip_material.get_shader_parameter("turn") == 0.0, "Resize cannot bypass the entry gate")
	var times: Dictionary = {}
	var start := Time.get_ticks_msec()
	modal.entered.connect(func(): times.entry = Time.get_ticks_msec() - start)
	preview.completed.connect(func(_id, _serial): times.result = Time.get_ticks_msec() - start)
	modal.present()
	check(group.modulate.a == 0 and is_equal_approx(modal.zoom, 0.96) and modal.offset.y == 16, "Entry begins at 0.96 scale and 16px with immediate feedback")
	await pause(0.20)
	check(preview.state == "ready" and preview.detail_alpha == 0, "No flip or result before entry completes")
	check(group.modulate.a > 0.99 and shade.modulate.a > 0.99, "Opacity completes before spatial entry")
	var bounds: Rect2 = preview.card_rect
	await pause(Modal.ENTER + Reveal.REVEAL + Reveal.INFO - 0.20 + 0.12)
	check(preview.state == "revealed" and preview.interactive, "Natural playback finishes without a second confirmation")
	check(times.has("entry") and absf(times.entry - 320) < 85, "Entry settles near 320ms")
	var expected_ms := (Modal.ENTER + Reveal.REVEAL + Reveal.INFO) * 1000
	check(times.has("result") and absf(times.result - expected_ms) < 100, "Prepared result completes on the configured timeline")
	print("MODAL TIMING ms: ", times)
	check(preview.card_rect == bounds and preview.entry.scale == Vector2.ONE and preview.entry.rotation == 0, "Stable geometry and settled card after reveal")
	check(preview.detail_alpha == 1 and preview.detail_offset == 0, "Text and actions settle together")
	await teardown()
	# Close at entry, flip and info phases: never reset the currently visible face.
	for time in [0.08, Modal.ENTER + Reveal.REVEAL * 0.35, Modal.ENTER + Reveal.REVEAL + Reveal.INFO * 0.35]:
		await setup()
		modal.present()
		await pause(time)
		var transform: Transform2D = preview.entry.get_transform()
		var angle: float = preview.flip_material.get_shader_parameter("turn")
		var alpha := group.modulate.a
		preview.freeze()
		modal.dismiss()
		check(preview.entry.get_transform() == transform and group.modulate.a == alpha, "Close starts from current pose at " + str(time))
		await pause(0.09)
		check(preview.entry.get_transform() == transform and preview.flip_material.get_shader_parameter("turn") == angle, "Frozen projected face stays continuous during exit")
		check(group.modulate.a < alpha and modal.state == "exiting", "Exit fades while retaining its lifetime")
		await pause(0.15)
		check(modal.state == "closed" and group.modulate.a == 0 and shade.modulate.a == 0 and preview._tween == null, "Exit ends without old callbacks")
		await teardown()
	await setup(true)
	modal.present()
	await pause(0.19)
	check(preview.session.reduced and preview.flip_material.get_shader_parameter("crossfade"), "Reduced motion uses a true two-image crossfade")
	check(preview.entry.scale == Vector2.ONE and preview.entry.rotation == 0 and preview.sparkle_progress == 0 and modal.offset == Vector2.ZERO, "Reduced mode has no shake, scale, shift or particles")
	await pause(0.32)
	check(preview.state == "revealed" and preview.interactive, "Reduced motion retains result and actions")
	preview.freeze(); modal.dismiss()
	await pause(0.18)
	check(modal.state == "closed", "Reduced exit completes near 140ms")
	await teardown()
	# Inject a different aspect only in the resource cache; production assets are untouched.
	var original_back := back_path
	back_path = "user://test-971x1620.png"
	var synthetic := Image.create(971, 1620, false, Image.FORMAT_RGBA8)
	synthetic.fill(Color.TRANSPARENT)
	synthetic.fill_rect(Rect2i(16, 16, 939, 1588), Color.WHITE)
	resources.textures[back_path] = ImageTexture.create_from_image(synthetic)
	await setup()
	check(is_equal_approx(preview.card_rect.size.x / preview.card_rect.size.y, 971.0 / 1620.0), "971:1620 back determines a stable native-aspect container")
	check(preview.back_texture.get_image().get_pixel(0, 0).a == 0, "Transparent source corners remain untouched")
	check(is_equal_approx(preview.flip_material.get_shader_parameter("front_aspect"), 2.0 / 3.0), "Front retains its own aspect inside the same plane")
	var saved_rect: Rect2 = preview.card_rect
	preview.allow_reveal(); preview._kill_tween()
	for t in [0.0, Reveal.REVEAL * 0.22, Reveal.REVEAL * 0.5, Reveal.REVEAL, Reveal.REVEAL + Reveal.INFO]:
		preview._set_elapsed(t)
		check(preview.card_rect == saved_rect, "Flip does not resize the display container")
	preview.skip()
	check(preview.face.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and preview.face.texture.resource_path == card.image, "Skip shows the same complete real front without stretching")
	await teardown()
	resources.textures.erase(back_path)
	back_path = original_back
	await setup()
	modal.present(); await pause(0.40)
	motion.set_enabled(false)
	check(preview.state == "revealed" and preview.face.texture.resource_path == card.image and preview.sparkle_progress == 0, "Changing reduced-motion preference mid-flip settles the same result")
	await teardown()
	check(get_processed_tweens().is_empty(), "Destroying all presentations leaves no animation tasks")
	print("MODAL MOTION ASSERTIONS: ", checks)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
