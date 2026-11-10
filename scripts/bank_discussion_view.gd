extends Control
const Avatar = preload("res://scripts/profile_avatar.gd")
var host: Control
var store: Node
var bank := ""
var list_scroll: ScrollContainer
var list: VBoxContainer
var composer: TextEdit
var publish: Button
var status: Label
var reply_cancel: Button
var latest: Button
var hot: Button
var underline: ColorRect
var line: ColorRect
var rendering := false
var rendered_sort := ""
var liked_states: Dictionary = {}
var text_pages: Dictionary = {}
const TEXT_PREVIEW := 400
const TEXT_PAGE := 4000

func configure(owner_view: Control, service: Node, bank_id: String) -> void:
	host = owner_view; store = service; bank = bank_id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	host._label(self, "题库讨论", 24, host.text_color, Rect2(32, 24, 230, 42), true)
	var close: Button = host._button(self, "CloseDiscussion", "", host.show_right_pane.bind("numbers"))
	close.icon = host._texture("res://assets/minimal/icons/x.png"); close.accessibility_name = "关闭讨论，返回题号列表"
	host._rect(close, Rect2(302, 28, 36, 36))
	var subtitle: Label = host._label(self, str(host.content._subject().title) + " · 全题库共用", 14, host.muted_color, Rect2(32, 68, 306, 35))
	subtitle.name = "BankTitle"
	host._line(self, Rect2(32, 104, 309, 1))
	latest = _action(self, "最新", func(): store.sort_by(bank, "latest"))
	hot = _action(self, "热门", func(): store.sort_by(bank, "hot"))
	host._rect(latest, Rect2(32, 115, 44, 36)); host._rect(hot, Rect2(92, 115, 44, 36))
	underline = host._line(self, Rect2(32, 151, 42, 3)); underline.color = host._accent()
	list_scroll = ScrollContainer.new(); list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(list_scroll)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18); list_scroll.add_child(list)
	list_scroll.get_v_scroll_bar().value_changed.connect(func(value: float):
		if not rendering: store.state(bank).scroll = int(value))
	line = host._line(self, Rect2())
	status = host._label(self, "", 13, host.muted_color)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	composer = TextEdit.new(); composer.placeholder_text = "输入评论…"; composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	composer.add_theme_font_size_override("font_size", 16)
	composer.add_theme_color_override("font_color", host.text_color)
	composer.add_theme_color_override("font_placeholder_color", host.muted_color)
	var style: StyleBoxFlat = host._style(host.surface, 8, host.border)
	style.content_margin_left = 12; style.content_margin_top = 8; style.content_margin_right = 12; style.content_margin_bottom = 8
	for key in ["normal", "focus", "read_only"]: composer.add_theme_stylebox_override(key, style)
	composer.text_changed.connect(func(): store.state(bank).draft = composer.text; store.state(bank).publish_blocked = false; _status())
	composer.focus_entered.connect(func(): host.right_panes.focus_memory["discussion"] = weakref(composer))
	add_child(composer)
	publish = _action(self, "发布", _publish)
	host._style_button(publish, host.BLUE, true); publish.add_theme_font_size_override("font_size", 16)
	reply_cancel = _action(self, "取消回复", func(): store.reply_to(bank, {}))
	store.changed.connect(_changed)
	resized.connect(_layout)
	_render(); _layout()

func _action(parent: Node, caption: String, action: Callable) -> Button:
	var button: Button = host._button(parent, "CommentAction", caption, action)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", host.muted_color)
	# Shared buttons clip text, so flow containers need an explicit text width.
	button.custom_minimum_size = Vector2(maxf(44, button.get_theme_font("font").get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20), 32)
	return button

func _text(parent: Node, text: String, font_size: int, color: Color, bold := false) -> Label:
	var label: Label = host._label(parent, text, font_size, color, Rect2(), bold)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false; label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _layout() -> void:
	if not is_instance_valid(composer): return
	host._rect(list_scroll, Rect2(32, 175, maxf(1, size.x - 56), maxf(30, size.y - 353)))
	host._rect(line, Rect2(32, size.y - 164, size.x - 56, 1))
	host._rect(status, Rect2(32, size.y - 158, size.x - 56, 36))
	host._rect(composer, Rect2(32, size.y - 115, size.x - 60, 57))
	host._rect(publish, Rect2(size.x - 120, size.y - 48, 92, 40))
	host._rect(reply_cancel, Rect2(32, size.y - 48, 100, 36))

func _changed(target: String, reason: String) -> void:
	if not is_inside_tree(): return
	if target != bank and reason != "account": return
	if reason == "account": liked_states.clear(); text_pages.clear(); rendered_sort = ""
	if reason in ["items", "status", "account"]: _render()
	else: _status()
	if reason == "account" and host.right_mode == "discussion": store.activate(bank)

func _status() -> void:
	var s: Dictionary = store.state(bank)
	var busy: bool = s.busy.get("publish", false)
	composer.editable = not busy
	if composer.text != s.draft: composer.text = s.draft
	publish.text = "发布中…" if busy else "发布" if store.profile.authenticated() else "登录"
	publish.disabled = busy or (store.profile.authenticated() and (str(s.draft).strip_edges().is_empty() or s.publish_blocked))
	reply_cancel.visible = not str(s.reply_id).is_empty()
	status.text = s.error if not str(s.error).is_empty() else s.notice if not str(s.notice).is_empty() else "回复 " + str(s.reply_name) if reply_cancel.visible else "参与这门课程的讨论"
	for pair in [[latest, "latest"], [hot, "hot"]]:
		pair[0].add_theme_color_override("font_color", host._accent() if s.sort == pair[1] else host.muted_color)
		host._motion().bind_button(pair[0])
	host._motion().animate(underline, underline, ^"position:x", 32.0 if s.sort == "latest" else 92.0, 0.15)

func _render() -> void:
	rendering = true
	var s: Dictionary = store.state(bank)
	var position_before: int = s.scroll
	for child in list.get_children(): list.remove_child(child); child.queue_free()
	if s.items.is_empty():
		_text(list, "正在加载讨论…" if s.loading else str(s.error) if not str(s.error).is_empty() else "还没有评论，来聊聊这门课吧", 16, host.muted_color)
	for item in s.items:
		_comment(list, item)
		if s.expanded.get(item.id, false):
			var page: Dictionary = s.replies.get(item.id, {"items": [], "cursor": ""})
			for reply in page.items: _comment(list, reply, true)
			if s.reply_loading.get(item.id, false): _text(list, "正在加载回复…", 14, host.muted_color)
			elif page.items.is_empty(): _text(list, "暂无回复", 14, host.muted_color)
			if not str(page.cursor).is_empty(): _action(list, "更多回复", func(): store.load_replies(bank, str(item.id), true))
		var divider: ColorRect = host._line(list, Rect2()); divider.custom_minimum_size.y = 1
	if not str(s.error).is_empty() and not s.loading: _action(list, "重试加载", func(): store.load_page(bank, not s.items.is_empty() and not str(s.cursor).is_empty()))
	elif s.loading and not s.items.is_empty(): _text(list, "加载中…", 14, host.muted_color)
	elif not str(s.cursor).is_empty(): _action(list, "加载更多", func(): store.load_page(bank, true))
	_status()
	if s.loaded and rendered_sort != s.sort:
		rendered_sort = s.sort
		host._motion().enter(list, 0.14)
	_restore_scroll.call_deferred(position_before)

func _restore_scroll(value: int) -> void:
	list_scroll.scroll_vertical = value
	rendering = false

func _comment(parent: Node, item: Dictionary, reply := false) -> void:
	var row := HBoxContainer.new(); row.name = "Comment_" + str(item.id); row.add_theme_constant_override("separation", 14); parent.add_child(row)
	var avatar := Avatar.new(); avatar.custom_minimum_size = Vector2(32, 32) if reply else Vector2(42, 42)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	avatar.show_profile(item.get("author", {})); row.add_child(avatar)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 8); row.add_child(body)
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation", 10); body.add_child(heading)
	var name_label: Label = _text(heading, str(item.get("author", {}).get("name", "用户")), 16, host.text_color, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF; name_label.clip_text = true; name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var college := str(item.get("author", {}).get("college", "")).strip_edges()
	if not college.is_empty():
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		name_label.custom_minimum_size.x = minf(120, name_label.get_theme_font("font").get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		var college_label := _text(heading, college, 12, host.muted_color.lightened(0.12) if not host.dark else host.muted_color)
		college_label.name = "AuthorCollege"
		college_label.accessibility_name = "学院：" + college
	_text(body, _time(str(item.get("created_at", ""))), 12, host.muted_color)
	var state := str(item.get("status", "published"))
	if state in ["deleted", "hidden"]:
		_text(body, "该评论已删除" if state == "deleted" else "该评论已隐藏", 16 if not reply else 14, host.text_color)
	else:
		_comment_text(body, item, 16 if not reply else 14)
	if state == "pending": _text(body, "待审核 · 仅自己可见", 12, host.muted_color)
	var actions := HFlowContainer.new(); actions.add_theme_constant_override("h_separation", 6); body.add_child(actions)
	if state == "published":
		var like: Button = _action(actions, str(int(item.get("like_count", 0))), func(): store.mutate(bank, "comment_like", {"comment_id": item.id, "value": not item.get("liked", false)}, str(item.id)))
		like.icon = load("res://assets/discussion/thumbs-up.svg"); like.add_theme_constant_override("icon_max_width", 18)
		like.custom_minimum_size.x += 18
		like.accessibility_name = "取消点赞" if item.get("liked", false) else "点赞"
		like.add_theme_color_override("font_color", host._accent() if item.get("liked", false) else host.muted_color)
		like.add_theme_color_override("icon_normal_color", host._accent() if item.get("liked", false) else host.muted_color)
		like.disabled = store.state(bank).busy.get(str(item.id), false)
		var liked: bool = item.get("liked", false)
		if liked_states.has(item.id) and liked_states[item.id] != liked: host._motion().enter(like, 0.14)
		liked_states[item.id] = liked
		if not reply: _action(actions, "回复", func(): store.reply_to(bank, item); composer.grab_focus())
		_action(actions, "举报", func(): store.mutate(bank, "comment_report", {"comment_id": item.id, "reason": "inappropriate"}, str(item.id)))
	if item.get("can_delete", false) and state not in ["deleted", "hidden"]:
		_action(actions, "删除", func(): store.mutate(bank, "comment_delete", {"comment_id": item.id}, str(item.id)))
	if not reply and int(item.get("reply_count", 0)) > 0:
		_action(body, ("收起回复" if store.state(bank).expanded.get(item.id, false) else "查看 %d 条回复" % int(item.reply_count)), func(): store.load_replies(bank, str(item.id)))

func _comment_text(parent: Node, item: Dictionary, font_size: int) -> void:
	var full_text := str(item.get("body", ""))
	var id := str(item.id)
	if full_text.length() <= TEXT_PREVIEW:
		_text(parent, full_text, font_size, host.text_color); return
	if not text_pages.has(id):
		_text(parent, full_text.left(TEXT_PREVIEW) + "…", font_size, host.text_color)
		_action(parent, "展开全文", _show_text_page.bind(id, 0))
		return
	var offset: int = text_pages[id]
	_text(parent, full_text.substr(offset, TEXT_PAGE), font_size, host.text_color)
	var navigation := HFlowContainer.new(); parent.add_child(navigation)
	if offset > 0: _action(navigation, "上一段", _show_text_page.bind(id, maxi(0, offset - TEXT_PAGE)))
	if offset + TEXT_PAGE < full_text.length(): _action(navigation, "下一段", _show_text_page.bind(id, offset + TEXT_PAGE))
	_action(navigation, "收起", _show_text_page.bind(id, -1))

func _show_text_page(id: String, offset: int) -> void:
	var row := list.get_node_or_null("Comment_" + id) as Control
	if row != null: store.state(bank).scroll = int(row.position.y)
	if offset < 0: text_pages.erase(id)
	else: text_pages[id] = offset
	_render()

func _time(value: String) -> String:
	return preload("res://scripts/time_display.gd").relative(value)

func _publish() -> void:
	if not store.profile.authenticated(): store.profile.run_action("begin_login", "discussion")
	else: store.publish(bank)
