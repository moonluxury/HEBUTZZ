extends "res://outputs/ui_handoff_work/capture.gd"

var store: Node
var replies: Dictionary = {}
const ASSET := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

class PublicationFixture extends ProfileFixture:
	var rows: Array = []
	func social_request(action: String, _payload: Dictionary) -> Dictionary:
		if action == "submission_config":
			return {"ok":true,"categories":[{"id":"course","name":"课程经验"},{"id":"tech","name":"技术教程"},{"id":"campus","name":"校园故事"}],"limits":{"title":100,"text":50000,"tags":5,"images":9,"image_bytes":6291456},"pricing":{"free":true,"minimum":200,"maximum":500,"currency":"batteries","commission_percent":20,"settlement_days":3},"publication_reward":50,"reward_configured":true,"comments_enabled":false}
		if action == "submission_mine": return {"ok":true,"items":rows,"counts":{"draft":1,"pending":2,"published":2,"returned":1},"next_cursor":""}
		return {"ok":false,"message":"截图示例数据"}
	func submission_get(_path: String, _binary := false) -> Dictionary:
		return {"ok":true,"items":[],"next_cursor":""}

func paragraph(text: String) -> Dictionary:
	return {"type":"paragraph","content":[{"type":"text","text":text}]}

func js(expression: String) -> Variant:
	var id := str(Time.get_ticks_usec())
	page.browser.call("eval", "(async()=>{try{let value=await (" + expression + ");window.sendIpcMessage(JSON.stringify({handoff_id:"+JSON.stringify(id)+",value}));}catch(e){window.sendIpcMessage(JSON.stringify({handoff_id:"+JSON.stringify(id)+",error:String(e)}));}})();")
	for i in 600:
		if replies.has(id):
			if replies[id].has("error"): print("BROWSER ERROR ",replies[id].error)
			return replies[id].get("value")
		await process_frame
	print("BROWSER TIMEOUT ", expression)
	return null

func received(raw: String) -> void:
	var value: Variant = JSON.parse_string(raw)
	if value is Dictionary and value.has("handoff_id"): replies[str(value.handoff_id)] = value

func attach() -> void:
	for i in 900:
		if is_instance_valid(page.browser) and page.browser_ready: break
		await process_frame
	page.browser.connect("ipc_message", received)
	await js("document.fonts.ready.then(()=>true)")
	await pause(0.7)

func subshot(name: String) -> void:
	await js("Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))).then(()=>true)")
	await shot("08_投稿与文章/" + name)

func run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-"): quit(2); return
	OS.set_environment("HEGONG_SUBMISSION_QA", "1")
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
	var api := PublicationFixture.new()
	root.add_child(api)
	api.accounts["test-account-a"].display_name = "示例同学"
	await login(api, "test-account-a")
	var blocks: Array = []
	for heading in ["一、课程基本信息", "二、重点内容总结", "三、常见题型", "四、复习建议", "五、参考资料"]:
		blocks.append({"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":heading}]})
		blocks.append(paragraph("传热学是能源与动力工程等专业的基础课程，主要研究热量传递的基本机理及其工程应用。复习时先理解物理过程，再分析边界条件，最后选择适用公式。"))
		blocks.append(paragraph("每次计算应写出已知条件、基本方程、代入过程与结果检验。以课堂和课程教学大纲为准，结合真实作业与练习归纳解题方法，并检查单位与适用条件。"))
		if heading.begins_with("二"):
			blocks.append({"type":"mathBlock","attrs":{"latex":"q=-\\lambda A\\frac{dT}{dx}"}})
	var data := {"title":"传热学期末复习经验（含重点总结与例题）","category_id":"course","course":"能源与动力工程","tags":["传热学","期末","复习"],"cover_asset_id":"","sources":"示例文章，仅用于 UI 美术交接。","price_batteries":0,"document":{"type":"doc","content":blocks}}
	var states := ["draft","pending","published","returned","published","pending"]
	var titles := [data.title,"工程热力学期末重点整理","Fluent 入门：从网格到后处理","制冷循环常用工质对比","校园里的学习空间","课堂笔记与复习方法"]
	for i in states.size():
		var content: Dictionary = data.duplicate(true)
		content.title = titles[i]
		api.rows.append({"id":"design-submission-"+str(i),"client_key":"%032d" % (i+1),"revision":1,"revision_id":"v1","state":states[i],"data":content,"ui":{},"updated_at":"2026-11-02T08:00:00Z","review_note":"请补充资料来源与参考文献。" if states[i]=="returned" else "","article_id":"design-article-"+str(i) if states[i]=="published" else ""})
	store = root.get_node("AppServices").submission_store()
	await visit("Submissions")
	await attach()
	await subshot("01_我的投稿")
	await js("[...document.querySelectorAll('.list-tabs button')].find(b=>b.textContent.includes('草稿')).click()")
	await subshot("02_我的投稿_草稿筛选")
	await js("document.querySelector('.delete-action').click()")
	await subshot("03_删除草稿确认")
	await js("document.querySelector('#dialog-root').replaceChildren()")
	store.current = api.rows[0].duplicate(true)
	store.current.data.price_batteries = 200
	store.view = "settings"
	store.changed.emit("open")
	await subshot("04_投稿设置")
	await js("window.hegong.qa('scroll',100000)")
	await subshot("05_投稿设置_下半页")
	store.switch_view("writer")
	await subshot("06_正文编辑器")
	store.switch_view("preview")
	await subshot("07_稿件预览")
	store.switch_view("settings")
	await pause()
	await js("[...document.querySelectorAll('button')].find(b=>b.textContent==='提交审核').click()")
	await subshot("08_提交审核确认")
	store.article = {"id":"design-article", "data":data.duplicate(true),"author":{"display_name":"示例作者","avatar_card_id":"0004"},"can_edit":false,"can_read":true,"published_at":"2026-11-02T08:00:00Z","views":128,"like_count":18,"bookmark_count":6,"liked":false,"bookmarked":false,"price_batteries":0}
	store.view = "article"
	await visit("SubmissionArticle")
	await attach()
	await subshot("09_文章阅读_顶部")
	await js("window.hegong.qa('scroll',100000)")
	await subshot("10_文章阅读_底部")
	await js("[...document.querySelectorAll('button')].find(b=>b.textContent==='举报').click()")
	await subshot("11_举报文章")
	store.article.can_read = false
	store.article.price_batteries = 200
	store.changed.emit("article")
	await pause()
	await js("document.querySelector('#dialog-root')?.replaceChildren()")
	await js("window.hegong.qa('scroll',0)")
	await subshot("12_付费文章_解锁入口")
	await js("document.querySelector('.purchase-wall button').click()")
	await subshot("13_购买文章确认")
	print("CAPTURE COMPLETE submissions")
	quit()
