extends Node
## Keep embedded menus and input dialogs sharp at fractional UI scales.
var popup: Window

func _ready() -> void:
	popup = get_parent() as Window
	popup.visibility_changed.connect(_visibility_changed)
	_visibility_changed()

func _visibility_changed() -> void:
	var active := popup.visible and popup.is_embedded()
	if active and not RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.connect(_sync)
	elif not active and RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)

func _sync() -> void:
	if not popup.visible or not popup.is_embedded(): return
	# Godot 4.6 resets an embedded popup's raster scale to the root stretch
	# factor, omitting the owner's canvas scale. At 0.5 root stretch a DPI
	# radio icon becomes a 9px texture subsequently enlarged to ~16px.
	# Match CardTransferUi's render density without changing Window.size,
	# content_scale_factor, menu placement or the native input coordinates.
	var density := maxf(1.0, get_tree().root.get_stretch_transform().get_scale().x)
	popup.oversampling_override = maxf(1.0, popup.content_scale_factor * density)
	var pixels := Vector2i((Vector2(popup.size) * density).ceil())
	RenderingServer.viewport_set_size(popup.get_viewport_rid(), pixels.x, pixels.y)
	RenderingServer.viewport_set_global_canvas_transform(popup.get_viewport_rid(),
		(popup.get_stretch_transform() * popup.global_canvas_transform).scaled(Vector2.ONE * density))

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)
