extends Node

const ICON_TEXTURE: Texture2D = preload("res://assets/branding/hegong_zhigu_icon.png")


func _ready() -> void:
	if OS.has_feature("windows") and DisplayServer.get_name() != "headless":
		_apply_window_icon.call_deferred()


func _apply_window_icon() -> void:
	# Godot 4.6's ICO loader selects the largest frame and lets Win32 resample it
	# without a quality filter. Resize first so Win32 receives its native size.
	# Godot uses system DPI awareness, so the primary screen determines this size.
	var dpi := 96
	if ProjectSettings.get_setting("display/window/dpi/allow_hidpi", true):
		dpi = maxi(96, DisplayServer.screen_get_dpi(DisplayServer.SCREEN_PRIMARY))
	var icon_size := maxi(32, roundi(32.0 * dpi / 96.0))
	var icon := ICON_TEXTURE.get_image()
	icon.resize(icon_size, icon_size, Image.INTERPOLATE_LANCZOS)
	DisplayServer.set_icon(icon)
