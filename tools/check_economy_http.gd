extends SceneTree
const Provider = preload("res://tools/fixtures/submission_http_provider.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var store: Node
var api: Node
var wallet: Node
var replies: Dictionary = {}
var output := "res://.godot_appdata/battery-economy-20261031/visual"

func _init() -> void:
	OS.set_environment("HEGONG_SUBMISSION_QA", "1")
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 8) -> void:
	for i in count: await process_frame

func until(test: Callable, timeout := 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	check(test.call(), "The integrated operation completes within its deadline")
	return test.call()

func _message(raw: String) -> void:
	var value: Variant = JSON.parse_string(raw)
	if value is Dictionary and value.has("qa_id"): replies[str(value.qa_id)] = value

func script(expression: String) -> Variant:
	var id := str(Time.get_ticks_usec())
	page.browser.call("eval", "(async()=>{try{let value=await (" + expression + ");window.sendIpcMessage(JSON.stringify({qa_id:" + JSON.stringify(id) + ",value}));}catch(error){window.sendIpcMessage(JSON.stringify({qa_id:" + JSON.stringify(id) + ",error:String(error)}));}})();")
	if not await until(func(): return replies.has(id)): return null
	check(not replies[id].has("error"), str(replies[id].get("error", "Browser request succeeds")))
	return replies[id].get("value")

func attach_page() -> bool:
	page = current_scene
	if not await until(func(): return is_instance_valid(page.browser) and page.browser_ready): return false
	page.browser.connect("ipc_message", _message)
	await script("document.fonts.ready.then(()=>true)")
	await frames(16)
	return true

func capture(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func session(value: Dictionary) -> void:
	api.account_id = value.account_id
	api.access_token = value.access_token
	api.auth_generation += 1
	root.get_node("ProfileStore").use_provider(api, {"state":"authenticated","account_id":api.account_id})
	await until(func(): return not root.get_node("ProfileStore").loading and not wallet.catalog_loading and not wallet.balance_loading)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check") or DisplayServer.get_name() == "headless": quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1710, 1000); root.content_scale_size = root.size
	root.position = Vector2i(-10000,-10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	var accounts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.godot_appdata/battery-economy-20261031/e2e-session.json"))
	api = Provider.new(); api.base_url = "http://127.0.0.1:8059"; root.add_child(api)
	wallet = root.get_node("AppServices").wallet_store()
	await session(accounts.author)
	root.get_node("AppState").subject_id = "marxism"
	root.get_node("AppState").start_index = 0
	root.get_node("PageRouter").go("res://scenes/Quiz.tscn")
	await scene_changed; await frames()
	page = current_scene
	var rewards: Node = root.get_node("AppServices").practice_rewards()
	await until(func(): return rewards.preparing.is_empty())
	for index in page.shuffled_options.size():
		if page.shuffled_options[index].get("correct",false): page.selected_indices.append(index)
	page._reveal_answer()
	check(wallet.balance == 0, "A correct answer has not yet credited the real HTTP wallet")
	page.minimal_view.finish.pressed.emit()
	await scene_changed; await frames()
	check(wallet.balance == 1 and current_scene.name == "Workbench", "Finish credits one battery through the real client adapter and returns home")
	await capture("01-practice-settled")
	store = root.get_node("AppServices").submission_store()
	store.new_draft()
	var data: Dictionary = store.current.data.duplicate(true)
	data.title = "电池结算联调稿件"
	data.category_id = "course"
	data.course = "隔离测试课程"
	data.document = {"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"只有购买后才能查看的测试正文。"}]}]}
	store.update(data)
	root.get_node("PageRouter").go("res://scenes/Submissions.tscn", "settings")
	await scene_changed
	if not await attach_page(): quit(1); return
	check(bool(await script("!!document.querySelector('.pricing-panel')")), "Submission settings contain the real pricing control")
	await script("(()=>{document.querySelectorAll('.price-options button')[1].click();const n=document.querySelector('[data-price-input]');n.value='199';n.dispatchEvent(new Event('input',{bubbles:true}));return !n.checkValidity();})()")
	check(bool(await script("!document.querySelector('[data-price-input]').checkValidity()")), "The UI rejects prices below 200")
	await script("(()=>{const n=document.querySelector('[data-price-input]');n.value='250';n.dispatchEvent(new Event('input',{bubbles:true}));return true;})()")
	await until(func(): return int(store.current.data.get("price_batteries",0)) == 250)
	await capture("02-submission-price")
	await script("document.querySelector('[data-save]').click()")
	await until(func(): return not store.busy and not store.dirty and not str(store.current.id).is_empty())
	check(store.current.data.price_batteries == 250, "Saving round-trips the chosen price through the production-shaped API")
	await script("[...document.querySelectorAll('.settings-side button')].find(b=>b.textContent==='提交审核').click()")
	check(bool(await script("document.querySelector('#dialog-root').textContent.includes('250 电池')")), "Submission confirmation includes the exact price")
	await script("document.querySelector('#dialog-root button.primary').click()")
	await until(func(): return store.current.state == "pending" and not store.busy)
	var admin := Provider.new(); admin.base_url = "http://127.0.0.1:8059"; root.add_child(admin)
	admin.account_id = accounts.admin.account_id; admin.access_token = accounts.admin.access_token
	var approved: Dictionary = await admin.social_request("publication_review", {"submission_id":store.current.id,"expected_revision":int(store.current.revision),"decision":"approve","operation_id":Crypto.new().generate_random_bytes(16).hex_encode()})
	check(approved.get("ok",false), "The submitted revision can be approved")
	if not approved.get("ok",false): quit(1); return
	var published: Dictionary = await admin.social_request("publication_review", {"submission_id":store.current.id,"expected_revision":int(approved.submission.revision),"decision":"publish","operation_id":Crypto.new().generate_random_bytes(16).hex_encode()})
	check(published.get("ok",false) and published.submission.reward.amount == 50, "Publishing posts the fixed 50-battery reward")
	await store.refresh_mine()
	await until(func(): return not wallet.balance_loading)
	check(wallet.balance == 51, "The author's refreshed submission list also refreshes the credited balance")
	await store.refresh_public()
	check(store.public_items.size() == 1 and not store.public_items[0].data.has("document"), "Published list shows the new article without downloading its body")
	var article_id: String = str(published.submission.article_id)
	await session(accounts.buyer)
	await store.open_article(article_id)
	check(not store.article.can_read and not store.article.data.has("document"), "Unpurchased article data excludes paid content")
	root.get_node("PageRouter").go("res://scenes/SubmissionArticle.tscn")
	await scene_changed
	if not await attach_page(): quit(1); return
	check(bool(await script("!!document.querySelector('.purchase-wall')&&!document.querySelector('.article-document')")), "The reader presents a purchase panel instead of hidden paid text")
	await capture("03-purchase-confirm")
	await script("document.querySelector('.purchase-wall button').click()")
	await script("document.querySelector('#dialog-root button.primary').click()")
	await until(func(): return store.article.get("can_read",false) and not store.purchase_busy)
	check(wallet.balance == 250, "The purchase receipt updates the balance without an extra balance query")
	check(bool(await script("document.querySelector('.article-document')?.textContent.includes('只有购买后')")), "Successful purchase renders the real article body")
	await capture("04-purchased-reader")
	var again: Dictionary = await api.social_request("article_purchase", {"article_id":article_id,"expected_revision_id":store.article.revision_id,"expected_price":250,"operation_id":Crypto.new().generate_random_bytes(16).hex_encode()})
	check(again.get("ok",false) and again.balance == 250, "A second purchase attempt never debits again")
	var seller := Provider.new(); seller.base_url = "http://127.0.0.1:8059"; root.add_child(seller)
	seller.account_id = accounts.author.account_id; seller.access_token = accounts.author.access_token
	var seller_balance: Dictionary = await seller.wallet_request("balance",{})
	check(seller_balance.balance == 51, "A sale leaves author commission pending until scheduled settlement")
	print("ECONOMY HTTP ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
