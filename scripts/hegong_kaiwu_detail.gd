extends "res://scripts/minimal_page.gd"
var content_label: RichTextLabel
var article_title: Label
var back_button: Button

func _ready() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	active_nav = "KaiwuButton"
	super._ready()

func _build_content() -> void:
	var article: Dictionary = _app().hegong_kaiwu_article
	back_button = _button(body, "BackButton", "返回", get_node("/root/PageRouter").back)
	back_button.icon = _texture("res://assets/minimal/icons/arrow-left.png")
	_rect(back_button, Rect2(0, 0, 120, 54))
	article_title = _label(body, str(article.get("title", "暂无内容")), TITLE_SIZE, text_color, Rect2(0, 95, 1000, 100), true)
	article_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(body, str(article.get("category", "")), BODY_SIZE, muted_color, Rect2(0, 205, 700, 40))
	content_label = RichTextLabel.new()
	content_label.fit_content = true
	content_label.scroll_active = false
	content_label.text = str(article.get("content", article.get("preview", "暂无正文")))
	content_label.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	content_label.add_theme_color_override("default_color", text_color)
	content_label.add_theme_constant_override("line_separation", 14)
	body.add_child(content_label)
	content_label.minimum_size_changed.connect(_layout)

func _layout_content(width: float) -> void:
	article_title.size.x = width
	_rect(content_label, Rect2(0, 280, width, maxf(500, content_label.get_content_height())))
	content_height = 320 + maxf(500, content_label.get_content_height())
