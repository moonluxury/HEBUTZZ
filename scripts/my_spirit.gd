extends Control

var _clock_elapsed := 0.0

@onready var spirit_placeholder: Label = $PageMargin/PageColumn/Body/SpiritColumn/SpiritCenter/SpiritGlyph
@onready var feedback_label: Label = $PageMargin/PageColumn/Body/SpiritColumn/FeedbackLabel
@onready var level_label: Label = $PageMargin/PageColumn/Body/StatsColumn/LevelLabel
@onready var xp_label: Label = $PageMargin/PageColumn/Body/StatsColumn/XpLabel
@onready var xp_bar: ProgressBar = $PageMargin/PageColumn/Body/StatsColumn/XpBar
@onready var online_label: Label = $PageMargin/PageColumn/Body/StatsColumn/OnlineLabel
@onready var answer_stats: Label = $PageMargin/PageColumn/Body/StatsColumn/AnswerStats
@onready var interaction_stats: Label = $PageMargin/PageColumn/Body/StatsColumn/InteractionStats
@onready var unlock_label: Label = $PageMargin/PageColumn/Body/StatsColumn/UnlockLabel
@onready var interact_button: Button = $PageMargin/PageColumn/ActionCenter/ActionRow/TouchButton
@onready var jump_button: Button = $PageMargin/PageColumn/ActionCenter/ActionRow/JumpButton
@onready var spin_button: Button = $PageMargin/PageColumn/ActionCenter/ActionRow/SpinButton
@onready var sparkle_button: Button = $PageMargin/PageColumn/ActionCenter/ActionRow/SparkleButton
@onready var back_button: Button = $PageMargin/PageColumn/BottomRow/BackButton


func _ready() -> void:
	interact_button.pressed.connect(_on_interact_pressed)
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	_app_state().spirit_progress_changed.connect(_refresh_progress)
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)

	spirit_placeholder.text = "精灵形象\n等待美术资源"
	spirit_placeholder.add_theme_font_size_override("font_size", 64)
	interact_button.text = "互动一下"
	jump_button.text = "动作待接入"
	spin_button.text = "动作待接入"
	sparkle_button.text = "动作待接入"
	jump_button.disabled = true
	spin_button.disabled = true
	sparkle_button.disabled = true
	unlock_label.text = "当前为基础 Demo\n收到精灵图片后，将在这里接入升级形态和动作解锁。"

	_app_state().apply_font_scale(self)
	_app_state().apply_color_mode(self)
	_refresh_progress()


func _process(delta: float) -> void:
	_clock_elapsed += delta
	if _clock_elapsed >= 1.0:
		_clock_elapsed = 0.0
		_refresh_online_time()


func _on_interact_pressed() -> void:
	var old_level := int(_app_state().get_spirit_progress()["level"])
	if not _app_state().register_spirit_interaction():
		feedback_label.text = "精灵正在休息，请稍后再互动。"
		return

	var new_level := int(_app_state().get_spirit_progress()["level"])
	feedback_label.text = "互动成功，经验 +2"
	if new_level > old_level:
		feedback_label.text += "，精灵升到 %d 级！" % new_level
	_refresh_progress()


func _refresh_progress() -> void:
	var progress: Dictionary = _app_state().get_spirit_progress()
	level_label.text = "等级 %d" % int(progress["level"])
	xp_label.text = "本级经验：%d / 100" % _app_state().get_spirit_level_progress()
	xp_bar.value = _app_state().get_spirit_level_progress()
	answer_stats.text = "答对题目：%d 道\n答错题目：%d 道" % [
		int(progress["correct_answers"]),
		int(progress["wrong_answers"]),
	]
	interaction_stats.text = "互动次数：%d 次" % int(progress["interactions"])
	_refresh_online_time()


func _refresh_online_time() -> void:
	var seconds := int(float(_app_state().get_spirit_progress()["online_seconds"]))
	var hours := int(floor(float(seconds) / 3600.0))
	var minutes := int(floor(float(seconds % 3600) / 60.0))
	var remaining_seconds := seconds % 60
	online_label.text = "在线时长：%02d:%02d:%02d" % [
		hours,
		minutes,
		remaining_seconds,
	]


func _app_state() -> Node:
	return get_node("/root/AppState")


func _on_font_scale_changed(_scale: float) -> void:
	_app_state().apply_font_scale(self)


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
