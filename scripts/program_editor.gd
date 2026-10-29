extends VBoxContainer
const Styles = preload("res://scripts/ui_styles.gd")

signal draft_changed(code: String)
signal reference_toggled(revealed: bool)

const CODE_FONT = preload("res://themes/code_font.tres")
const PythonRunner = preload("res://scripts/python_runner.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
var editor: CodeEdit
var reference_editor: CodeEdit
var reference_box: VBoxContainer
var reveal_button: Button
var run_button: Button
var stop_button: Button
var stdin_editor: CodeEdit
var output_editor: CodeEdit
var run_status: Label
var runner: Node


func configure(question: Dictionary, draft: String, revealed: bool) -> void:
	add_theme_constant_override("separation", 18)
	var hint := Label.new()
	hint.text = "编写 Python 代码 · Tab 缩进 · 草稿自动保存"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 32)
	add_child(hint)
	editor = _code_edit(true)
	editor.name = "PythonCodeEditor"
	editor.placeholder_text = "# 在这里编写你的解答"
	editor.text = draft
	editor.text_changed.connect(func(): draft_changed.emit(editor.text))
	add_child(editor)
	_build_runner()
	reveal_button = _button("查看参考代码")
	add_child(reveal_button)
	reference_box = VBoxContainer.new()
	reference_box.add_theme_constant_override("separation", 16)
	add_child(reference_box)
	var note := Label.new()
	note.text = str(question.get("source_note", "参考代码来自原资料。请对照题目要求检查自己的解法。"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 32)
	reference_box.add_child(note)
	reference_editor = _code_edit(false)
	reference_editor.name = "ReferenceCode"
	reference_editor.text = str(question.get("reference_code", "原资料未提供参考代码。"))
	reference_box.add_child(reference_editor)
	for path in question.get("reference_images", []):
		var picture := TextureRect.new()
		picture.texture = load(str(path))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.resized.connect(_fit_image.bind(picture))
		reference_box.add_child(picture)
		_fit_image.call_deferred(picture)
	reveal_button.pressed.connect(_toggle_reference)
	reference_box.visible = revealed
	reveal_button.text = "收起参考代码" if revealed else "查看参考代码"


func _toggle_reference() -> void:
	get_node("/root/UiMotion").reveal(reference_box, not reference_box.visible)
	reveal_button.text = "收起参考代码" if reference_box.visible else "查看参考代码"
	reference_toggled.emit(reference_box.visible)


func _build_runner() -> void:
	runner = PythonRunner.new()
	add_child(runner)
	var input_hint := Label.new()
	input_hint.text = "输入数据（可选）· 每次 input() 对应一行，运行前填好"
	input_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_hint.add_theme_font_size_override("font_size", 30)
	add_child(input_hint)
	stdin_editor = _code_edit(true)
	stdin_editor.name = "PythonInput"
	stdin_editor.custom_minimum_size.y = 150
	stdin_editor.placeholder_text = "例如：\n3\n5"
	add_child(stdin_editor)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 24)
	add_child(actions)
	run_button = _button("▶ 运行代码")
	stop_button = _button("■ 停止")
	stop_button.disabled = true
	actions.add_child(run_button)
	actions.add_child(stop_button)
	run_status = Label.new()
	run_status.text = "Python 3.13 · 单次运行最多 10 秒"
	run_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_status.add_theme_font_size_override("font_size", 30)
	add_child(run_status)
	output_editor = _code_edit(false)
	output_editor.name = "PythonOutput"
	output_editor.custom_minimum_size.y = 240
	output_editor.gutters_draw_line_numbers = false
	output_editor.placeholder_text = "运行输出和错误信息会显示在这里"
	add_child(output_editor)
	run_button.pressed.connect(_run_code)
	stop_button.pressed.connect(func(): runner.stop())
	runner.output_changed.connect(func(text: String): output_editor.text = text)
	runner.finished.connect(_run_finished)
	if not runner.supported():
		run_button.disabled = true
		run_status.text = "代码运行目前支持 Windows 64 位桌面版。"


func _run_code() -> void:
	if runner.is_running():
		return
	run_button.disabled = true
	stop_button.disabled = false
	run_status.text = "正在运行…"
	runner.run_code(editor.text, stdin_editor.text)


func _run_finished(message: String) -> void:
	run_button.disabled = not runner.supported()
	stop_button.disabled = true
	run_status.text = message


func _fit_image(picture: TextureRect) -> void:
	if is_instance_valid(picture) and picture.texture != null and picture.size.x > 0:
		var display_width := minf(picture.size.x, picture.texture.get_width() * 3.0)
		picture.custom_minimum_size.y = ceilf(display_width * picture.texture.get_height() / picture.texture.get_width())


func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 76
	button.add_theme_font_size_override("font_size", 34)
	return button


func _code_edit(editable_code: bool) -> CodeEdit:
	var field := CodeEdit.new()
	field.custom_minimum_size = Vector2(0, 600)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.editable = editable_code
	field.gutters_draw_line_numbers = true
	field.gutters_draw_fold_gutter = true
	field.indent_size = 4
	field.indent_automatic = true
	field.indent_use_spaces = true
	field.auto_brace_completion_enabled = true
	field.line_folding = true
	field.add_theme_font_override("font", CODE_FONT)
	field.add_theme_font_size_override("font_size", 36)
	return field


func apply_palette(dark: bool) -> void:
	var colors := Styles.code_palette(dark)
	var ink: Color = colors.ink
	for field in [editor, reference_editor, stdin_editor, output_editor]:
		Styles.code_editor(field, dark)
		get_node("/root/UiMotion").bind_input.call_deferred(field)
		var syntax := CodeHighlighter.new()
		for keyword in ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"]:
			syntax.add_keyword_color(keyword, Color("#B9A2FF") if dark else Color("#7041AA"))
		syntax.number_color = Color("#8AD9D9") if dark else Color("#0B6868")
		syntax.function_color = Color("#A9CCFF") if dark else Color("#195E9F")
		syntax.symbol_color = ink
		syntax.add_color_region("#", "", Color("#93AC98") if dark else Color("#4D7754"), true)
		for quote in ["\"\"\"", "'''", "\"", "'"]:
			syntax.add_color_region(quote, quote, Color("#F2CA8E") if dark else Color("#9C5C16"))
		if field in [editor, reference_editor]:
			field.syntax_highlighter = syntax
	for button in [reveal_button, run_button, stop_button]:
		Styles.code_button(button, dark)
		get_node("/root/UiMotion").bind_button.call_deferred(button)
