extends "res://scripts/battery_amount.gd"
## Read-only shared balance, independent of a page's scroll or order polling.
var wallet: Node

func configure(page: Control) -> void:
	setup(page, "—", 28.0, 18, 16)
	unit.hide()
	add_theme_constant_override("separation", 8)
	wallet = get_node("/root/AppServices").wallet_store()
	wallet.changed.connect(refresh)
	refresh()

func _enter_tree() -> void:
	if is_instance_valid(wallet) and is_instance_valid(number): refresh()

func refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(number): return
	var value := grouped(int(wallet.balance)) if wallet.balance != null else "—"
	set_value(value)
	number.add_theme_font_size_override("font_size", 18 if value.length() < 14 else 16)
	if wallet.balance != null:
		accessibility_name = "电池余额，" + value + " 电池"
	elif wallet.balance_loading:
		accessibility_name = "正在获取电池余额"
	elif not wallet.balance_error.is_empty():
		accessibility_name = "电池余额获取失败，可在我要充值页面重试"
	else:
		accessibility_name = wallet.unavailable()
