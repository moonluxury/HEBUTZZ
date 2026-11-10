extends "res://scripts/ui_texture_cache.gd"
const Styles = preload("res://scripts/ui_styles.gd")
const PopupDensity = preload("res://scripts/ui_popup_density.gd")
## Keep font glyph atlases and immutable UI resources alive across page changes.
var regular: SystemFont
var bold: SystemFont
var page_theme: Theme

func _ready() -> void:
	set_process(false)
	regular = SystemFont.new()
	regular.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	regular.oversampling = 4.0
	regular.generate_mipmaps = true
	regular.disable_embedded_bitmaps = true
	bold = regular.duplicate()
	bold.font_weight = 700
	page_theme = Theme.new()
	page_theme.default_font = regular
	page_theme.default_font_size = 22
	# Inputs and their menus use the same glyph atlas as surrounding labels.
	for kind in ["LineEdit", "TextEdit", "OptionButton", "MenuButton", "PopupMenu"]:
		page_theme.set_font("font", kind, regular)
	Styles.install_theme(page_theme)
	# Include internal bars created later by editors, menus and dialog windows.
	get_tree().node_added.connect(_configure_control)

func _configure_control(node: Node) -> void:
	if node is PopupMenu:
		_bind_popup_density.call_deferred(weakref(node))
	elif node is LineEdit or node is TextEdit or node is OptionButton or node is MenuButton:
		_bind_input_window.call_deferred(weakref(node))
	if node is ScrollBar:
		# Keep native visibility/ranges: editors use them to enable wheel scrolling.
		node.self_modulate.a = 0.0
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE

func _bind_popup_density(reference: WeakRef) -> void:
	var popup = reference.get_ref()
	if not is_instance_valid(popup) or not popup.is_inside_tree() or popup.is_queued_for_deletion(): return
	if popup == get_tree().root: return
	if popup.has_node("UiPopupDensity"): return
	var density := PopupDensity.new()
	density.name = "UiPopupDensity"
	popup.add_child(density)

func _bind_input_window(reference: WeakRef) -> void:
	var control = reference.get_ref()
	if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion():
		_bind_popup_density(weakref(control.get_window()))
