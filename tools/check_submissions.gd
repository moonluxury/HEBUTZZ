extends SceneTree
const Provider = preload("res://tools/fixtures/submission_http_provider.gd")
var failures: Array[String] = []
var store: Node
var page: Node
var session: Dictionary
var replies: Dictionary = {}
var output := "res://.godot_appdata/submission-validation"

func _init() -> void:
	OS.set_environment("HEGONG_SUBMISSION_QA", "1")
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value: failures.append(description); push_error(description)

func frames(count := 8) -> void:
	for index in count: await process_frame

func until(test: Callable, limit := 15000) -> bool:
	var deadline := Time.get_ticks_msec() + limit
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	var finished: bool = test.call()
	check(finished, "The integrated editor operation completes within its deadline; " + (str(store.error) + " / " + str(store.status) if is_instance_valid(store) else "before store initialization"))
	return finished

func script(expression: String) -> Variant:
	var id := str(Time.get_ticks_usec())
	page.browser.call("eval", "(async()=>{try{let value=await (" + expression + ");window.sendIpcMessage(JSON.stringify({qa_id:" + JSON.stringify(id) + ",value}));}catch(error){window.sendIpcMessage(JSON.stringify({qa_id:" + JSON.stringify(id) + ",error:String(error)}));}})();")
	if not await until(func(): return replies.has(id)): return null
	var result: Dictionary = replies[id]
	check(not result.has("error"), str(result.get("error", "")))
	return result.get("value")

func _message(raw: String) -> void:
	var value: Variant = JSON.parse_string(raw)
	if value is Dictionary and value.has("qa_id"): replies[str(value.qa_id)] = value

func attach_page() -> bool:
	page = current_scene
	if not await until(func(): return is_instance_valid(page.browser) and page.browser_ready): return false
	page.browser.connect("ipc_message", _message)
	await script("document.fonts.ready.then(()=>true)")
	await frames(15)
	return true

func capture(name: String) -> void:
	print("CAPTURE: ", name)
	await script("Promise.all([...document.images].map(image=>image.decode().catch(()=>{}))).then(()=>true)")
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check") or DisplayServer.get_name() == "headless": quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1710, 920)
	root.content_scale_size = root.size
	root.position = Vector2i(-10000, -10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	session = JSON.parse_string(FileAccess.get_file_as_string("res://.godot_appdata/submission-check-session.json"))
	var api := Provider.new()
	api.base_url = "http://127.0.0.1:8059"
	root.add_child(api)
	api.access_token = session.access_token
	api.account_id = session.account_id
	var profile := root.get_node("ProfileStore")
	profile.use_provider(api, {"state":"authenticated","account_id":api.account_id})
	await until(func(): return not profile.loading)
	store = root.get_node("AppServices").submission_store()
	if not is_instance_valid(store): quit(1); return
	var opened: Dictionary = await store.open_draft(str(session.draft_id))
	check(opened.get("ok", false), "Open the real server-owned test draft")
	if store.current.get("state") == "pending": await store.transition("submission_withdraw")
	if session.get("initial_data") is Dictionary:
		store.update(session.initial_data)
		await store.save()
	root.get_node("PageRouter").go("res://scenes/Submissions.tscn")
	await scene_changed
	if not await attach_page(): quit(1); return
	await until(func(): return not store.config.is_empty())
	await capture("01-settings")
	root.size = Vector2i(1366, 768); root.content_scale_size = root.size
	await frames(20)
	check(bool(await script("document.documentElement.scrollWidth<=innerWidth")), "Narrow settings have no horizontal page overflow")
	await capture("09-settings-narrow")
	root.size = Vector2i(1710, 920); root.content_scale_size = root.size
	await frames(20)
	var before: Dictionary = await script("window.hegong.inspect()")
	check(before.client_key == store.current.client_key, "Native store and browser share the same draft identity")
	await script("window.hegong.qa('navigate','writer')")
	await until(func(): return store.view == "writer")
	await frames(12)
	var writer: Dictionary = await script("window.hegong.inspect()")
	check(writer.client_key == before.client_key and writer.document == before.document, "Settings and immersive writing share one structured document")
	check(writer.headings.size() >= 5, "The actual heading nodes generate the writing outline")
	check(bool(await script("getComputedStyle(document.querySelector('.outline')).display!=='none'")), "The outline remains visible in a full-size Windows DPI-scaled window")
	check(absf(float(await script("devicePixelRatio")) - page.canvas.scale.x) < 0.02, "Native and embedded UI share the same DPI-adjusted layout unit")
	await capture("02-writer")
	root.size = Vector2i(1366, 768); root.content_scale_size = root.size
	await frames(20)
	await capture("07-writer-narrow")
	check(bool(await script("document.documentElement.scrollWidth<=innerWidth")), "Narrow writing has no horizontal page overflow")
	root.size = Vector2i(1710, 920); root.content_scale_size = root.size
	await frames(20)
	var long_paragraph := {"type":"paragraph","content":[{"type":"text","text":"长文中文测试".repeat(2000)}]}
	await script("window.hegong.qa('insert'," + JSON.stringify(long_paragraph) + ")")
	await until(func(): return not store.dirty and not store.busy)
	check(bool(await script("document.querySelector('.ProseMirror').textContent.length>12000")), "The embedded editor supports and saves more than ten thousand Chinese characters")
	await script("document.querySelector('button[title=\"撤销\"]').click()")
	await until(func(): return not store.dirty and not store.busy)
	var addition := {"type":"paragraph","content":[{"type":"text","text":"自动保存验证：中文编辑与格式保持。","marks":[{"type":"bold"}]}]}
	await script("window.hegong.qa('insert'," + JSON.stringify(addition) + ")")
	await until(func(): return store.dirty)
	await until(func(): return not store.dirty and not store.busy)
	var remote: Dictionary = await api.social_request("submission_get", {"submission_id":store.current.id})
	check(JSON.stringify(remote.submission.data.document).contains("自动保存验证"), "Typing in the embedded editor automatically persists the latest Chinese text to the real backend")
	await script("window.hegong.qa('navigate','settings')")
	await until(func(): return store.view == "settings")
	await frames()
	var back: Dictionary = await script("window.hegong.inspect()")
	check(JSON.stringify(back.document).contains("自动保存验证"), "Returning to settings cannot restore an obsolete copy")
	await script("window.hegong.qa('scroll',180)")
	await page.prepare_navigation()
	await frames()
	var remembered: Dictionary = store.current.ui.duplicate(true)
	await store.save()
	await store.open_draft(str(store.current.id))
	await frames(15)
	check(store.current.ui.selection == remembered.selection and absf(float(store.current.ui.scroll.settings) - float(remembered.scroll.settings)) < 0.1, "Reopening a saved draft retains caret and scroll metadata")
	await script("document.querySelector('button[title=\"插入表格\"]').click()")
	await script("[...document.querySelectorAll('.dialog button')].find(button=>button.textContent==='插入').click()")
	await frames()
	check(bool(await script("!!document.querySelector('.ProseMirror table')")), "The table tool inserts a real editable table")
	await script("[...document.querySelectorAll('.toolbar button')].find(button=>button.textContent==='fx').click()")
	await script("(()=>{const field=document.querySelector('.dialog textarea');field.value='x^{2}+y^{2}=1';field.dispatchEvent(new Event('input'));return true;})()")
	await script("[...document.querySelectorAll('.dialog button')].find(button=>button.textContent==='应用').click()")
	await frames()
	check(bool(await script("[...document.querySelectorAll('.math-block')].some(node=>node.textContent.includes('x'))")), "The formula tool renders and retains editable mathematical source")
	var imported_asset: Dictionary = store.add_image(str(session.image))
	check(imported_asset.get("ok", false), "User-selected image decoding and private staging succeed")
	if imported_asset.get("ok", false):
		await script("window.hegong.qa('insert'," + JSON.stringify({"type":"image","attrs":{"asset_id":imported_asset.asset.id,"width":400,"alt":"隔离插入图片验证"}}) + ")")
	await until(func(): return not store.dirty and not store.busy)
	var docx_path := ProjectSettings.globalize_path(output.path_join("editor-roundtrip.docx"))
	var exported: Dictionary = await page.word.export_file(docx_path, store)
	check(exported.get("ok", false) and FileAccess.file_exists(docx_path), "The application exports a genuine DOCX including Chinese, tables, formulas and images")
	if exported.get("ok", false):
		var reimported: Dictionary = await page.word.import_file(docx_path, store)
		check(reimported.get("ok", false) and JSON.stringify(reimported.get("document", {})).contains("自动保存验证"), "The application reimports the exported DOCX without losing Chinese body text")
	var submitted: Dictionary = await store.submit()
	check(submitted.get("ok", false) and store.current.state == "pending", "Submitting fixes the latest saved revision as pending review")
	var not_public: Dictionary = await api.submission_get("/v1/articles/" + str(store.current.id))
	check(not not_public.get("ok", false), "The submitted draft is not exposed through the public article endpoint")
	await script("window.hegong.qa('navigate','preview')")
	await until(func(): return store.view == "preview")
	await frames()
	check(bool(await script("document.body.textContent.includes('私有预览')")), "Draft preview is explicitly private")
	var removable_data: Dictionary = session.initial_data.duplicate(true)
	removable_data.title = "待整理的课程笔记"
	var removable_result: Dictionary = await api.social_request("submission_create", {"client_key":store._key(),"operation_id":store._key(),"data":removable_data})
	check(removable_result.get("ok", false), "Prepare an isolated draft for the visible delete action")
	var removable: Dictionary = removable_result.get("submission", {})
	await script("window.hegong.qa('navigate','mine')")
	await until(func(): return store.view == "mine" and store.records.size() >= 6)
	await frames()
	await capture("03-mine")
	var delete_selector := ".submission-row[data-draft-key=\"" + str(removable.get("client_key", "")) + "\"] .delete-action"
	check(bool(await script("!!document.querySelector(" + JSON.stringify(delete_selector) + ")")), "A directly visible delete button is present for the unpublished draft")
	await script("document.querySelector(" + JSON.stringify(delete_selector) + ").click()")
	check(bool(await script("document.querySelector('.dialog').textContent.includes('待整理的课程笔记')")), "Delete confirmation identifies the selected manuscript")
	await capture("11-delete-confirmation")
	await script("[...document.querySelectorAll('.dialog button')].find(button=>button.textContent==='取消').click()")
	var after_cancel: Dictionary = await api.social_request("submission_get", {"submission_id":removable.id})
	check(after_cancel.get("ok", false), "Cancelling leaves the manuscript intact")
	await script("document.querySelector(" + JSON.stringify(delete_selector) + ").click()")
	await script("(()=>{const button=[...document.querySelectorAll('.dialog button')].find(button=>button.textContent==='删除');button.click();button.click();return true;})()")
	await until(func(): return not store.busy and store.records.all(func(item): return item.id != removable.id))
	var after_delete: Dictionary = await api.social_request("submission_get", {"submission_id":removable.id})
	check(not after_delete.get("ok", false) and store.view == "mine", "Confirmed deletion removes exactly the chosen draft and stays on the list")
	root.size = Vector2i(1366, 768); root.content_scale_size = root.size
	await frames(20)
	check(bool(await script("document.documentElement.scrollWidth<=innerWidth")), "Narrow submission list has no horizontal page overflow")
	await capture("10-mine-narrow")
	root.size = Vector2i(1710, 920); root.content_scale_size = root.size
	await frames(20)
	check(int(store.counts.get("pending", 0)) >= 2 and int(store.counts.get("published", 0)) >= 3, "List counts are read from authoritative server states")
	var article_response: Dictionary = await store.open_article(str(session.article_id))
	check(article_response.get("ok", false), "Published article is obtained from the actual public service")
	root.get_node("PageRouter").go("res://scenes/SubmissionArticle.tscn")
	await scene_changed
	if not await attach_page(): quit(1); return
	await capture("04-article-top")
	var route_id: int = page.get_instance_id()
	await script("window.hegong.qa('scroll',100000)")
	await frames(15)
	await capture("05-article-bottom")
	check(page.get_instance_id() == route_id and str(store.article.id) == str(session.article_id), "Article top and lower reading state use one route and one article")
	check(bool(await script("document.querySelector('.outline-items .current')?.textContent.includes('参考资料')")), "The reader outline follows the lower visible section")
	var reading_position := float(await script("window.hegong.inspect().scroll"))
	var reaction: Dictionary = await store.react("like", true)
	check(reaction.get("ok", false), "The article reaction is persisted by the real backend")
	await frames(15)
	check(absf(float(await script("window.hegong.inspect().scroll")) - reading_position) < 3, "Liking at the bottom keeps the reading position")
	root.size = Vector2i(1366, 768); root.content_scale_size = root.size
	await frames(20)
	await capture("06-reader-narrow")
	check(bool(await script("document.documentElement.scrollWidth<=innerWidth")), "Narrow reading has no horizontal page overflow")
	await store.open_draft(str(session.draft_id))
	await store.transition("submission_withdraw")
	api.base_url = "http://127.0.0.1:1"
	var offline_data: Dictionary = store.current.data.duplicate(true)
	offline_data.title = "断网恢复验证"
	store.update(offline_data, {"selection":{"from":2,"to":2},"scroll":{"writer":130}})
	var failed_save: Dictionary = await store.save()
	check(not failed_save.get("ok", false) and store.dirty, "Connection failure leaves the unsaved working copy recoverable")
	var recovered := preload("res://scripts/submission_store.gd").new()
	root.add_child(recovered)
	await recovered.activate()
	check(recovered.current.get("data", {}).get("title") == "断网恢复验证" and recovered.dirty, "A fresh store restores the account's disconnected draft from disk")
	api.base_url = "http://127.0.0.1:8059"
	var resumed: Dictionary = await recovered.save()
	check(resumed.get("ok", false) and not recovered.dirty, "Reconnected draft retries synchronize with the authoritative revision")
	# The original store must reload before its exit hook persists again.
	store.current = {}; store.dirty = false; store.pending = {}
	await store.open_draft(str(session.draft_id))
	recovered.queue_free()
	await frames(15)
	var missing_delete: Dictionary = await store.delete_draft("0".repeat(32), "0".repeat(32))
	var preserved_draft: Dictionary = await api.social_request("submission_get", {"submission_id":session.draft_id})
	check(not missing_delete.get("ok", false) and preserved_draft.get("ok", false), "A failed lookup never deletes the previously open manuscript")
	root.get_node("PageRouter").go("res://scenes/Workbench.tscn")
	await scene_changed
	check(store.persist(), "Leaving safely preserves the account-scoped working draft")
	print("SUBMISSION INTEGRATION: ", failures.size(), " failures")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
