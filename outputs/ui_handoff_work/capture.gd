extends SceneTree

const SocialFixture = preload("res://tools/fixtures/social_provider.gd")
const ProfileFixture = preload("res://tools/fixtures/profile_provider.gd")
const WalletFixture = preload("res://tools/fixtures/wallet_provider.gd")
const CardFixture = preload("res://tools/fixtures/card_draw_provider.gd")
const AccountChecks = preload("res://tools/check_account_dialogs.gd")
const AuthDialog = preload("res://scripts/backend_login_dialog.gd")
const Reveal = preload("res://scripts/card_reveal.gd")
const OUT := "res://outputs/PC_UI美术交接_20261102/"
var app: Node
var profile: Node
var page: Node

func _init() -> void: run.call_deferred()

func pause(seconds := 0.35) -> void:
	await create_timer(seconds).timeout
	for i in 4: await process_frame

func visit(scene: String) -> Node:
	root.get_node("PageRouter").go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await pause()
	page = current_scene
	return page

func shot(name: String, settle := true) -> void:
	if settle: await pause()
	await RenderingServer.frame_post_draw
	var path := OUT + name + ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result := root.get_texture().get_image().save_png(path)
	print("SCREENSHOT ", result, " ", name)

func login(api: Node, id: String) -> void:
	profile.use_provider(api, {"state": "authenticated", "account_id": id})
	await pause()

func close_dialog() -> void:
	if is_instance_valid(page.get("dialog")): page.dialog.dismiss()
	await pause()

func run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-") or DisplayServer.get_name() == "headless": quit(2); return
	await process_frame
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(1920, 1260)
	root.unfocusable = true
	root.position = Vector2i(-10000, -10000)
	root.get_node("UiMotion").set_enabled(false)
	app = root.get_node("AppState")
	profile = root.get_node("ProfileStore")
	app.dark_mode = false
	var args := OS.get_cmdline_user_args()
	var part := args[0] if not args.is_empty() else "basic"
	match part:
		"basic": await basic()
		"account": await account()
		"social": await social()
		"wallet": await wallet()
		"cards": await cards()
		"extra": await extra()
		"final": await final_screens()
	print("CAPTURE COMPLETE ", part)
	quit()

func basic() -> void:
	var api := ProfileFixture.new()
	root.add_child(api)
	api.accounts["test-account-a"].display_name = "示例同学"
	api.accounts["test-account-a"].school = "河北工业大学"
	api.accounts["test-account-a"].college = "人工智能与数据科学学院"
	api.accounts["test-account-a"].major = "计算机科学与技术"
	api.accounts["test-account-a"].grade = "2024级"
	await login(api, "test-account-a")
	var stats := root.get_node("StudyStats")
	for subject in app.SUBJECTS:
		for i in range(8): stats.record_review(subject, stats.banks[subject][i])
	await visit("Workbench")
	await shot("01_工作台与题库/01_学习工作台")
	page._show_history()
	await shot("01_工作台与题库/02_学习记录弹窗")
	page._close_details()
	app.quiz_mode = "all"
	await visit("SubjectSelect")
	await shot("01_工作台与题库/03_总题库")
	page.scroll.scroll_vertical = 10000
	await shot("01_工作台与题库/04_总题库_下半页")
	for subject in app.SUBJECTS:
		var ids: Array = []
		for i in range(10): ids.append(stats.banks[subject][i].id)
		var f := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(ids))
	app.quiz_mode = "wrong"
	await visit("SubjectSelect")
	await shot("01_工作台与题库/05_错题库")
	page.scroll.scroll_vertical = 10000
	await shot("01_工作台与题库/06_错题库_下半页")
	app.quiz_mode = "all"
	app.subject_id = "python"
	app.start_index = 0
	await visit("Quiz")
	var kinds := {"single": "01_单选题", "multiple": "03_多选题", "judge": "04_判断题", "fill": "05_填空题", "output": "06_输出题", "program": "07_编程题"}
	for kind in kinds:
		var found := false
		for i in page.questions.size():
			if page.questions[i].type == kind:
				page._jump_to(i)
				await shot("02_答题/" + kinds[kind])
				found = true
				if kind == "single":
					page._on_option_pressed(0)
					await shot("02_答题/02_单选题_作答反馈")
				break
		if not found: print("MISSING QUESTION KIND ", kind)
	page._jump_to(0)
	page.minimal_view._toggle_distraction_free()
	await shot("02_答题/08_F6专注模式")
	page.minimal_view._toggle_distraction_free()
	page.minimal_view._toggle_rail()
	await shot("02_答题/09_收起题号列表")
	page.minimal_view.show_right_pane("discussion")
	await shot("02_答题/10_题库讨论_服务提示")
	await visit("HegongKaiwu")
	await shot("03_河工开物/01_资源列表")
	page._open_entry(page.visible_entries[0])
	await shot("03_河工开物/02_资源示例展开")
	await visit("HegongKaiwu")
	page.tools_root.get_node("Announcement0").pressed.emit()
	await pause()
	page = current_scene
	await shot("03_河工开物/03_征稿公告")
	page.scroll.scroll_vertical = 10000
	await shot("03_河工开物/04_征稿公告_下半页")
	await visit("Workbench")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await shot("09_深色主题参考/01_工作台")
	app.quiz_mode = "all"
	await visit("SubjectSelect")
	await shot("09_深色主题参考/02_总题库")
	await visit("Quiz")
	await shot("09_深色主题参考/03_答题")

func account() -> void:
	var api := ProfileFixture.new()
	root.add_child(api)
	api.accounts["test-account-a"].merge({"display_name":"示例同学", "school":"河北工业大学", "college":"人工智能与数据科学学院", "major":"计算机科学与技术", "grade":"2024级"}, true)
	api.permissions.school = {}
	await login(api, "test-account-a")
	await visit("PersonalCenter")
	await shot("04_个人中心与账号/01_个人中心")
	page.show_panel("edit", page.edit_button)
	await shot("04_个人中心与账号/02_编辑个人资料")
	await close_dialog()
	page.show_panel("avatar", page.avatar_button)
	await pause()
	page.dialog._select_card_avatar("0002")
	await shot("04_个人中心与账号/03_更换卡牌头像")
	await close_dialog()
	page.show_panel("logout", page.logout_button)
	await shot("04_个人中心与账号/04_退出登录确认")
	await close_dialog()
	var auth := AccountChecks.AccountFixture.new()
	root.add_child(auth)
	auth.account_id = "account-design_user"
	await login(auth, auth.account_id)
	page.show_panel("account", page.edit_button)
	await shot("04_个人中心与账号/05_账号与安全")
	await close_dialog()
	var dialog := AuthDialog.new()
	dialog.provider = auth
	page.add_child(dialog)
	dialog.present()
	await shot("04_个人中心与账号/06_账号登录")
	dialog._switch_mode()
	await shot("04_个人中心与账号/07_账号注册")
	dialog._cancel()
	await pause()
	dialog = AuthDialog.new()
	dialog.provider = auth
	dialog.password_mode = true
	page.add_child(dialog)
	dialog.present()
	await shot("04_个人中心与账号/08_修改密码")
	dialog._cancel()

func social() -> void:
	var api := SocialFixture.new()
	root.add_child(api)
	api.users[SocialFixture.A].name = "示例同学"
	api.users[SocialFixture.B].merge({"name":"好友小林", "school":"河北工业大学", "college":"人工智能与数据科学学院", "major":"计算机科学与技术", "grade":"2024级", "bio":"喜欢编程、阅读与卡牌收藏。\n希望和同学们交流学习方法，一起进步。", "avatar_card_id":"0004"}, true)
	api.users[SocialFixture.C].name = "好友小陈"
	api.stocks[SocialFixture.A] = {"0001":5,"0002":3,"0003":2,"0004":1,"0005":2,"0006":1,"0007":1}
	api.wanted[SocialFixture.B] = ["0001","0003","0005"]
	var cid: String = api.pair(SocialFixture.A, SocialFixture.B)
	api.append(cid, SocialFixture.A, "text", {"text":"可以呀，我也想收集这个系列。"})
	api.append(cid, SocialFixture.B, "text", {"text":"先一起做题吧，晚点再看看想要的卡牌。"})
	await login(api, SocialFixture.A)
	await visit("MyFriends")
	page._select(cid)
	await shot("06_好友与会话/01_好友会话")
	page.store.set_tab("friends")
	await shot("06_好友与会话/02_好友列表")
	page.store.set_tab("recent")
	page._select("system:" + SocialFixture.A)
	await shot("06_好友与会话/03_系统通知")
	page._select(cid)
	page.show_panel("add")
	await shot("06_好友与会话/04_添加好友")
	page.dialog.query.text = "QA-000003"
	page.dialog._search()
	await shot("06_好友与会话/05_添加好友_搜索结果")
	await close_dialog()
	api.execute(SocialFixture.C, "request_friend", {"peer_id":SocialFixture.A,"note":"同学你好，一起交流学习吧。","request_id":"design-request"})
	page.store.refresh()
	page.show_panel("requests")
	await shot("06_好友与会话/06_好友申请")
	await close_dialog()
	page.more_button.pressed.emit()
	await shot("06_好友与会话/07_会话操作菜单")
	for mode in ["profile", "remark", "block", "remove"]:
		page.dialog._switch(mode)
		await shot("06_好友与会话/" + {"profile":"08_查看好友资料","remark":"09_修改好友备注","block":"10_屏蔽确认","remove":"11_删除好友确认"}[mode])
	await close_dialog()
	page.show_panel("wishlist", {"peer":api.users[SocialFixture.B]})
	await shot("06_好友与会话/12_好友想要的卡牌")
	await close_dialog()
	page.show_panel("exchange", {"peer":api.users[SocialFixture.B],"give_card_id":"0003","receive_card_id":"0002"})
	await shot("06_好友与会话/13_发起换卡")
	page.dialog._review_create()
	await shot("06_好友与会话/14_换卡确认")
	await close_dialog()
	page.open_gift("0001", api.users[SocialFixture.B])
	await shot("06_好友与会话/15_赠送卡牌")
	page.gift_dialog.dismiss()
	await pause()
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await shot("09_深色主题参考/04_好友会话")

func wallet() -> void:
	var api := WalletFixture.new()
	root.add_child(api)
	api.nickname = "示例同学"
	await login(api, api.actor)
	await visit("Recharge")
	await shot("07_充值与电池/01_充值页面")
	var store: Node = page.store
	store.create_order()
	await shot("07_充值与电池/02_充值订单_待支付")
	await close_dialog()
	var id: String = store.current_order
	api.settle(id)
	store.query_order(id)
	page.show_panel("order", id)
	await shot("07_充值与电池/03_充值订单_已到账")
	await close_dialog()
	for mode in ["ledger", "orders", "rules", "help"]:
		page.show_panel(mode)
		await shot("07_充值与电池/" + {"ledger":"04_电池明细","orders":"05_充值记录","rules":"06_充值说明","help":"07_支付帮助"}[mode])
		await close_dialog()

func cards() -> void:
	var api := CardFixture.new()
	root.add_child(api)
	await login(api, CardFixture.A)
	await visit("MyCollection")
	await shot("05_我的收藏/01_收藏总览")
	page._toggle_group("season-001")
	await shot("05_我的收藏/02_系列收起")
	page._select_card("0001")
	await pause(1.0)
	if is_instance_valid(page.reveal): page.reveal.skip()
	await shot("05_我的收藏/03_已拥有卡牌详情")
	page._select_card("0007")
	await pause(1.0)
	if is_instance_valid(page.reveal): page.reveal.skip()
	await shot("05_我的收藏/04_未拥有卡牌详情")
	page.consume_back_action()
	await pause()
	page.acquire_button.pressed.emit()
	await shot("05_我的收藏/05_获取卡牌_等待开卡")
	var dialog: Node = page.acquisition
	var motion := root.get_node("UiMotion")
	motion.suspended = false
	motion.system_reduced = 0
	motion.set_enabled(true)
	dialog.hit.pressed.emit()
	await pause(0.4)
	for i in 240:
		if is_instance_valid(dialog.preview) and dialog.preview.state != "loading": break
		await process_frame
	dialog.preview._kill_tween()
	dialog.preview._set_elapsed(Reveal.ENTRY + 0.79)
	await shot("05_我的收藏/06_获取卡牌_动效关键帧", false)
	dialog.preview.skip()
	await shot("05_我的收藏/07_获取卡牌_结果")
	dialog.dismiss()
	await pause()
	motion.set_enabled(false)
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await shot("09_深色主题参考/05_收藏总览")

func extra() -> void:
	var api := SocialFixture.new()
	root.add_child(api)
	api.users[SocialFixture.A].name = "示例同学"
	api.users[SocialFixture.B].name = "好友小林"
	await login(api, SocialFixture.A)
	app.subject_id = "marxism"
	app.quiz_mode = "all"
	await visit("Quiz")
	for kind in ["multiple", "judge"]:
		for i in page.questions.size():
			if page.questions[i].type == kind:
				page._jump_to(i)
				await shot("02_答题/" + ("03_多选题" if kind == "multiple" else "04_判断题"))
				break
	var discussions: Node = root.get_node("AppServices").bank_discussions()
	var s: Dictionary = discussions.state("marxism")
	s.loaded = true
	s.items = [{"id":"design-comment-1", "author":{"name":"好友小林","college":"人工智能与数据科学学院","avatar_card_id":"0004"},"body":"这道题可以结合教材中的基本概念一起理解。大家复习时会怎么整理这部分知识？","created_at":"2026-11-02T08:30:00Z","like_count":6,"reply_count":1}, {"id":"design-comment-2", "author":{"name":"示例同学","college":"经济管理学院"},"body":"我会先按章节列提纲，再把容易混淆的概念放在一起对比。","created_at":"2026-11-02T08:20:00Z","like_count":3,"reply_count":0}]
	s.error = ""
	page.minimal_view.show_right_pane("discussion")
	discussions.changed.emit("marxism", "items")
	await shot("02_答题/11_题库讨论_评论列表")
	s.expanded["design-comment-1"] = true
	s.replies["design-comment-1"] = {"items":[{"id":"design-reply", "author":{"name":"好友小陈","college":"理学院"},"body":"可以试试把每章的关键词写成一张思维导图。","created_at":"2026-11-02T08:40:00Z","like_count":2}],"cursor":""}
	discussions.reply_to("marxism", s.items[0])
	discussions.changed.emit("marxism", "items")
	await shot("02_答题/12_题库讨论_展开回复")
	await visit("MyFriends")
	page._select(api.pair(SocialFixture.A, SocialFixture.B))
	api.execute(SocialFixture.C, "request_friend", {"peer_id":SocialFixture.A,"note":"同学你好，一起交流学习吧。"})
	page.store.refresh()
	page.show_panel("requests")
	await shot("06_好友与会话/06_好友申请")
	await close_dialog()
	for mode in ["recent_menu", "records", "blacklist"]:
		page.show_panel(mode)
		await shot("06_好友与会话/" + {"recent_menu":"16_最近会话菜单","records":"17_换卡记录","blacklist":"18_黑名单"}[mode])
		await close_dialog()
	var terms := {"peer_id":SocialFixture.A,"give":[{"card_id":"0002","season_id":"season-001","quantity":1}],"receive":[{"card_id":"0001","season_id":"season-001","quantity":1}],"terms_version":1,"client_id":"handoff-trade"}
	var result: Dictionary = api.execute(SocialFixture.B, "create_trade", terms)
	if result.get("ok",false) and result.has("trade"):
		page.store.refresh()
		page.show_panel("trade_review", {"trade":result.trade})
		await shot("06_好友与会话/19_收到换卡邀请")
		await close_dialog()
		page.show_panel("trade_reject", {"trade":result.trade})
		await shot("06_好友与会话/20_拒绝换卡确认")
		await close_dialog()
		page.show_panel("records")
		await shot("06_好友与会话/17_换卡记录")
		await close_dialog()
	await visit("MyCollection")
	page._set_filter("all")
	await shot("05_我的收藏/08_全部卡牌")
	page._set_filter("wanted")
	await shot("05_我的收藏/09_想要的卡牌")
	page._set_filter("owned")
	page._toggle_group("season-001")
	await shot("05_我的收藏/02_系列收起")
	await visit("SubjectSelect")
	page.search_edit.text = "不存在的课程"
	page.search_edit.text_changed.emit(page.search_edit.text)
	await shot("01_工作台与题库/07_题库搜索_无结果")

func final_screens() -> void:
	var api := SocialFixture.new()
	root.add_child(api)
	api.users[SocialFixture.A].name = "示例同学"
	await login(api, SocialFixture.A)
	app.subject_id = "matlab"
	app.quiz_mode = "all"
	await visit("Quiz")
	for i in page.questions.size():
		if page.questions[i].type == "judge":
			page._jump_to(i)
			await shot("02_答题/04_判断题")
			break
	await visit("HegongKaiwu")
	page.scroll.scroll_vertical = 10000
	await shot("03_河工开物/05_资源列表_下半页")
	var announcements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/hegong_announcements.json"))
	for i in range(1, announcements.size()):
		app.hegong_kaiwu_article = announcements[i]
		await visit("HegongKaiwuDetail")
		await shot("03_河工开物/%02d_%s" % [i+5, announcements[i].title])
	await visit("Workbench")
	var startup: Node = preload("res://tools/fixtures/startup_login_provider.gd").new()
	root.add_child(startup)
	await pause()
	await shot("04_个人中心与账号/00_软件启动_一键登录")
