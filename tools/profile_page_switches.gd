extends SceneTree
## Read-only UI timing diagnostic; run with run_workbench_checks.py for isolated saves.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	var app := root.get_node("AppState")
	var motion := root.get_node("UiMotion")
	var router := root.get_node("PageRouter")
	var routes := [
		["Workbench", "all", "marxism"],
		["SubjectSelect", "all", "marxism"],
		["SubjectSelect", "wrong", "marxism"],
		["HegongKaiwu", "all", "marxism"],
		["MyCollection", "all", "marxism"],
		["Quiz", "all", "marxism"],
		["Workbench", "all", "marxism"],
		["Quiz", "all", "python"],
		["Workbench", "all", "marxism"],
	]
	for pass_index in 3:
		motion.set_enabled(pass_index != 2)
		for route in routes:
			app.quiz_mode = route[1]
			app.subject_id = route[2]
			app.start_index = 0
			var started := Time.get_ticks_usec()
			var path := "res://scenes/%s.tscn" % route[0]
			var packed: PackedScene = router.packed_scene(path)
			var loaded := Time.get_ticks_usec()
			if packed == null:
				quit(1)
				return
			router.go(path)
			await scene_changed
			var ready_at := Time.get_ticks_usec()
			var last := ready_at
			var intervals: Array[float] = []
			for frame in 45:
				await process_frame
				var now := Time.get_ticks_usec()
				intervals.append((now - last) / 1000.0)
				last = now
			var first := intervals[0]
			intervals.sort()
			print(JSON.stringify({"pass": pass_index, "motion": pass_index != 2, "page": route[0], "mode": route[1], "subject": route[2], "load_ms": (loaded - started) / 1000.0, "enter_ms": (ready_at - loaded) / 1000.0, "first_frame_ms": first, "max_frame_ms": intervals[-1], "median_frame_ms": intervals[22], "node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}))
	print("WORKBENCH CHECKS: PASS (timing diagnostic complete)")
	quit()
