extends Node
## One-shot visual reveal; values remain available before the animation completes.
const Tokens = preload("res://scripts/ui_tokens.gd")
var animate_on_ready := true
var amount := 0.0:
	set(value):
		amount = value
		if is_instance_valid(target):
			target.queue_redraw()
var target: Control
var motion: Node
var waiting := false
var check_queued := false
var observed: Array[Signal] = []

func _ready() -> void:
	target = get_parent() as Control
	motion = get_node("/root/UiMotion")
	target.visibility_changed.connect(_visibility_changed)
	motion.preference_changed.connect(_preference_changed)
	restart(animate_on_ready)

func restart(animated := true) -> void:
	motion.cancel(self)
	_stop_observing()
	waiting = animated and not motion.reduced() and Tokens.DATA > 0
	amount = 0.0 if waiting else 1.0
	if not waiting:
		return
	# Watch layout/scroll events only until the first visible frame, not every frame.
	var ancestor: Node = target
	while ancestor != null:
		if ancestor is Control:
			_observe(ancestor.item_rect_changed)
			_observe(ancestor.visibility_changed)
		if ancestor is ScrollContainer:
			_observe(ancestor.get_v_scroll_bar().value_changed)
			_observe(ancestor.get_h_scroll_bar().value_changed)
		ancestor = ancestor.get_parent()
	_observe(target.get_viewport().size_changed)
	_schedule_check()

func _observe(event: Signal) -> void:
	if not event.is_connected(_schedule_check):
		event.connect(_schedule_check)
		observed.append(event)

func _stop_observing() -> void:
	for event in observed:
		if is_instance_valid(event.get_object()) and event.is_connected(_schedule_check):
			event.disconnect(_schedule_check)
	observed.clear()

func _schedule_check(_unused: Variant = null) -> void:
	if waiting and not check_queued:
		check_queued = true
		_check_visible.call_deferred()

func _check_visible() -> void:
	check_queued = false
	if not waiting or not is_inside_tree() or not target.is_visible_in_tree():
		return
	var visible_rect := target.get_global_rect()
	if not visible_rect.has_area():
		return
	visible_rect = visible_rect.intersection(target.get_viewport_rect())
	var ancestor := target.get_parent()
	while ancestor != null and visible_rect.has_area():
		if ancestor is Control and ancestor.clip_contents:
			visible_rect = visible_rect.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	if not visible_rect.has_area():
		return
	waiting = false
	_stop_observing()
	motion.animate(self, self, ^"amount", 1.0, Tokens.DATA)

func _visibility_changed() -> void:
	if waiting:
		_schedule_check()
	elif not target.is_visible_in_tree():
		motion.cancel(self)

func _preference_changed() -> void:
	if motion.reduced():
		waiting = false
		_stop_observing()
		motion.cancel(self)
		amount = 1.0

func _exit_tree() -> void:
	waiting = false
	_stop_observing()
