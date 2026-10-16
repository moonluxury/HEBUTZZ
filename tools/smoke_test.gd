extends SceneTree

const QUESTIONS_PATH := "res://data/questions.json"
const REPORT_PATH := "res://tools/smoke_report.txt"

var failures: Array[String] = []
var report_lines: Array[String] = []


func _init() -> void:
    print("SMOKE: starting")
    _run.call_deferred()


func _finish() -> void:
    _write_report()
    if failures.is_empty():
        print("SMOKE: PASS")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        print("SMOKE: FAIL (%d)" % failures.size())
        quit(1)


func _run() -> void:
    report_lines.append("SMOKE: starting")
    var questions := _load_questions()
    _expect(questions.size() == 540, "题库应包含 540 道题，实际 %d" % questions.size())
    report_lines.append("题库加载：%d 道" % questions.size())

    var counts := {"single": 0, "multiple": 0, "judge": 0}
    var max_options := 0
    for question in questions:
        var type := str(question["type"])
        counts[type] = int(counts.get(type, 0)) + 1
        max_options = max(max_options, question["options"].size())
        var correct_count := 0
        for option in question["options"]:
            if bool(option["correct"]):
                correct_count += 1
        _expect(correct_count >= 1, "第 %s 题缺少正确答案" % str(question["id"]))
        if type == "judge":
            _expect(question["options"].size() == 2, "判断题应有对/错两个选项：第 %s 题" % str(question["id"]))
        else:
            _expect(question["options"].size() >= 2, "选择题选项不足：第 %s 题" % str(question["id"]))

    _expect(counts["single"] == 190, "单选题数量应为 190，实际 %d" % counts["single"])
    _expect(counts["multiple"] == 160, "多选题数量应为 160，实际 %d" % counts["multiple"])
    _expect(counts["judge"] == 190, "判断题数量应为 190，实际 %d" % counts["judge"])
    _expect(max_options <= 4, "当前界面按最多 4 个选项设计，实际最大 %d" % max_options)
    report_lines.append("题型统计：single=%d multiple=%d judge=%d max_options=%d" % [counts["single"], counts["multiple"], counts["judge"], max_options])

    var main_scene = load("res://scenes/Main.tscn").instantiate()
    root.add_child(main_scene)
    await process_frame
    _expect(main_scene.has_method("_start_quiz"), "主页面缺少进入答题页的方法")
    _expect(main_scene.total_count == 540, "主页面总题数应显示为 540")
    report_lines.append("主页面：加载成功，总题数=%d" % main_scene.total_count)
    main_scene.queue_free()

    var app_state = root.get_node_or_null("/root/AppState")
    _expect(app_state != null, "AppState 自动加载未注册")
    if app_state == null:
        _finish()
        return
    app_state.set("quiz_mode", "all")
    app_state.set("start_index", 0)
    var quiz_scene = load("res://scenes/Quiz.tscn").instantiate()
    root.add_child(quiz_scene)
    await process_frame
    _expect(quiz_scene.questions.size() == 540, "总题库模式应加载 540 题")
    _expect(quiz_scene.jump_spin != null, "答题页应有跳题输入框")
    _expect(quiz_scene.jump_spin.max_value == 540, "跳题输入框最大值应为 540")
    if quiz_scene.is_mobile_layout:
        _expect(quiz_scene.question_grid == null, "手机布局不应创建右侧题号栏")
        report_lines.append("答题页：手机布局，总题库=%d，跳题输入框可用" % quiz_scene.questions.size())
    else:
        _expect(quiz_scene.question_grid != null, "桌面布局应有右侧题号跳转栏")
        _expect(quiz_scene.question_buttons.size() == 540, "右侧跳转栏应有 540 个题号按钮")
        report_lines.append("答题页：桌面布局，总题库=%d，跳转按钮=%d" % [quiz_scene.questions.size(), quiz_scene.question_buttons.size()])

    quiz_scene._jump_to(9)
    _expect(quiz_scene.current_index == 9, "跳转到第 10 题失败")
    report_lines.append("跳题：跳转到第 10 题，current_index=%d" % quiz_scene.current_index)

    var first_question_options := _option_key_order(quiz_scene.shuffled_options)
    var changed_order := false
    for i in range(20):
        quiz_scene._show_question()
        if _option_key_order(quiz_scene.shuffled_options) != first_question_options:
            changed_order = true
            break
    _expect(changed_order, "多次刷新同一题后选项顺序未发生变化")
    report_lines.append("选项乱序：%s" % ("通过" if changed_order else "失败"))

    var correct_index := _first_correct_option_index(quiz_scene.shuffled_options)
    quiz_scene._on_option_pressed(correct_index)
    _expect(quiz_scene.has_answered, "单选/判断点击选项后应立即显示答案")
    _expect("正确" in quiz_scene.result_label.text, "点击正确选项后应显示回答正确")
    _expect("正确答案" in quiz_scene.answer_label.text, "答题后应显示正确答案")
    report_lines.append("判题反馈：%s / %s" % [quiz_scene.result_label.text, quiz_scene.answer_label.text])

    var original_wrong_count = int(quiz_scene.wrong_ids.size())
    var question_id := str(quiz_scene.questions[quiz_scene.current_index]["id"])
    if quiz_scene.wrong_ids.has(question_id):
        quiz_scene._toggle_wrong_current()
        original_wrong_count = quiz_scene.wrong_ids.size()
    quiz_scene._toggle_wrong_current()
    _expect(quiz_scene.wrong_ids.has(question_id), "收藏到错题库失败")
    _expect(quiz_scene.wrong_ids.size() == original_wrong_count + 1, "错题库数量未增加")
    quiz_scene._toggle_wrong_current()
    _expect(not quiz_scene.wrong_ids.has(question_id), "移出错题库失败")
    report_lines.append("错题收藏：收藏和移出通过")

    quiz_scene.queue_free()
    _finish()


func _write_report() -> void:
    var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
    if file == null:
        return
    if failures.is_empty():
        report_lines.append("SMOKE: PASS")
    else:
        report_lines.append("SMOKE: FAIL")
        for failure in failures:
            report_lines.append("FAIL: " + failure)
    file.store_string("\n".join(report_lines) + "\n")


func _load_questions() -> Array:
    var file := FileAccess.open(QUESTIONS_PATH, FileAccess.READ)
    _expect(file != null, "无法打开题库 JSON")
    if file == null:
        return []
    var parsed = JSON.parse_string(file.get_as_text())
    _expect(typeof(parsed) == TYPE_ARRAY, "题库 JSON 不是数组")
    return parsed if typeof(parsed) == TYPE_ARRAY else []


func _option_key_order(options: Array) -> String:
    var keys: Array[String] = []
    for option in options:
        keys.append(str(option["key"]))
    return "|".join(keys)


func _first_correct_option_index(options: Array) -> int:
    for i in range(options.size()):
        if bool(options[i]["correct"]):
            return i
    return 0


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
