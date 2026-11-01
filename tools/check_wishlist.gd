extends SceneTree
const Fixture = preload("res://tools/fixtures/social_provider.gd")
const Collection = preload("res://scripts/collection_store.gd")
var failures: Array[String] = []
var assertions := 0
var api: Node
var collection: Node
var page: Node
const OUT := "res://.godot_appdata/wishlist-validation"

class CloudFixture extends Fixture:
	var lists: Dictionary = {}
	var operations: Dictionary = {}
	var writes := 0
	var offline := false
	var drop_reply := false
	var lag := 0.0
	func wishlist_request(action: String, payload: Dictionary) -> Dictionary:
		var owner := actor
		if lag > 0: await get_tree().create_timer(lag).timeout
		if offline: return failure(owner,"network","网络不可用")
		var current: Dictionary = lists.get(owner,{"wishlist_revision":0,"initialized":false,"card_ids":[]})
		if action == "wishlist_load": return response(owner,current.duplicate(true))
		var operation := owner + ":" + str(payload.operation_id)
		if operations.has(operation): return response(owner,operations[operation].duplicate(true))
		if int(payload.expected_revision) != int(current.wishlist_revision): return failure(owner,"wishlist_conflict")
		writes += 1
		var ids: Array = current.card_ids.duplicate()
		for id in payload.changes:
			if payload.changes[id] and not id in ids: ids.append(id)
			elif not payload.changes[id]: ids.erase(id)
		ids.sort()
		current = {"wishlist_revision":int(current.wishlist_revision)+1,"initialized":true,"card_ids":ids}
		lists[owner] = current
		wanted[owner] = ids.duplicate()
		operations[operation] = current.duplicate(true)
		if drop_reply:
			drop_reply = false
			return failure(owner,"unknown","响应丢失")
		return response(owner,current)

func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message); push_error(message)
func frames(count := 15) -> void:
	for index in count: await process_frame
func settle() -> void:
	await create_timer(1.0).timeout
func capture(name: String, window: Window) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var screen := root.get_texture().get_image()
	var scale := Vector2(screen.get_size())/root.get_visible_rect().size
	screen.get_region(Rect2i(Vector2(window.position)*scale,Vector2(window.size)*scale)).save_png(OUT.path_join(name+".png"))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size=Vector2i(1672,941); root.size=Vector2i(1672,941)
	if DisplayServer.get_name() != "headless": root.position=Vector2i(-10000,-10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUT)
	api = CloudFixture.new(); root.add_child(api)
	root.get_node("ProfileStore").use_provider(api,{"state":"authenticated","account_id":Fixture.A})
	collection = root.get_node("AppServices").collection_store()
	collection.wanted = {"0003":true}; collection._save_local()
	await settle()
	check(api.lists[Fixture.A].card_ids == ["0003"],"The first cloud initialization imports existing account marks")
	var writes: int = api.writes
	for enabled in [true,false,true]: collection.set_wanted("0001",enabled)
	check(api.writes==writes,"Rapid toggles are batched before a write")
	await settle()
	check(api.writes==writes+1 and api.lists[Fixture.A].card_ids==["0001","0003"],"Only the final card intent is submitted")
	var other := Collection.new(); root.add_child(other)
	other.use_provider(api,Fixture.A); await settle()
	check(other.is_wanted("0001") and other.is_wanted("0003"),"A fresh store reads the cloud list")
	api.offline=true
	collection.set_wanted("0002",true); await settle()
	check(collection.is_wanted("0002") and not collection.wishlist.error.is_empty(),"Offline changes remain marked and visibly pending")
	collection.use_provider(api,Fixture.A)
	check(collection.is_wanted("0002") and collection.wishlist.pending.has("0002"),"Pending changes survive a store reload")
	api.offline=false; collection.wishlist.refresh(); await settle()
	check(api.lists[Fixture.A].card_ids==["0001","0002","0003"],"Reconnection flushes saved intent")
	# Other device changes a different card before this device sends its patch.
	api.lists[Fixture.A].card_ids.erase("0001"); api.lists[Fixture.A].wishlist_revision+=1
	collection.set_wanted("0004",true); await settle(); await settle()
	check(not collection.is_wanted("0001") and collection.is_wanted("0004"),"Revision conflicts merge only edited cards without restoring stale marks")
	api.drop_reply=true
	collection.set_wanted("0005",true); await settle()
	check(not collection.wishlist.inflight.is_empty(),"A lost reply retains the original operation ID")
	api.lists[Fixture.A].card_ids.erase("0005"); api.lists[Fixture.A].wishlist_revision+=1
	collection.wishlist.refresh(); await settle()
	check(not collection.is_wanted("0005") and not "0005" in api.lists[Fixture.A].card_ids,"Replaying a receipt cannot resurrect a later removal")
	api.lag=0.3
	collection.set_wanted("0006",true); collection.wishlist.refresh()
	api.actor=Fixture.B; collection.use_provider(api,Fixture.B)
	await settle()
	check(collection.account_id==Fixture.B and not collection.is_wanted("0006"),"Account switch discards the previous account's late reply")
	api.lag=0; other.queue_free()
	api.actor=Fixture.A
	root.get_node("ProfileStore").use_provider(api,{"state":"authenticated","account_id":Fixture.A})
	api.wanted[Fixture.B] = ["0001","0002","0003"]
	await collection.refresh(); await settle()
	var social: Node = root.get_node("AppServices").social_store()
	social.refresh(); await frames()
	root.get_node("PageRouter").go("res://scenes/MyFriends.tscn"); await scene_changed; await frames()
	page=current_scene
	page.show_panel("wishlist",{"peer":api.users[Fixture.B]}); await frames()
	var window: Window = page.dialog
	check(window.card_rows.size()==3 and window.size.x>500,"Friend wishlist uses the shared full-sized card dialog")
	check(window.card_rows[0].art.texture.get_width()>=1000,"Wishlist displays original high-resolution artwork")
	check(not window.card_rows[0].gift.disabled and window.card_rows[2].gift.disabled,"Gift actions use real transferable stock")
	await capture("wishlist-light",window)
	window.card_rows[0].gift.pressed.emit(); await frames()
	check(is_instance_valid(page.gift_dialog) and page.gift_dialog.card_id=="0001","Wishlist gift opens confirmation with the exact card and friend")
	page.gift_dialog.dismiss(); await frames()
	page.show_panel("wishlist",{"peer":api.users[Fixture.B]}); await frames()
	window=page.dialog
	root.get_node("AppState").dark_mode=true;root.get_node("AppState").color_mode_changed.emit(true); await frames()
	await capture("wishlist-dark",window)
	root.content_scale_size=Vector2i(600,680);root.size=Vector2i(600,680); await frames(25)
	check(window.size.x<=600 and window.size.y<=680,"Wishlist fits a compact window")
	await capture("wishlist-small",window)
	root.content_scale_size=Vector2i(1672,941);root.size=Vector2i(1672,941)
	root.get_node("AppState").dark_mode=false;root.get_node("AppState").color_mode_changed.emit(false); await frames()
	api.wanted[Fixture.B]=[];window._load_wishlist(); await frames()
	check(window.card_rows.is_empty(),"Empty remote lists clear stale cards")
	await capture("wishlist-empty",window)
	api.fail_action="wishlist";window._load_wishlist(); await frames()
	check(not window.response_data.ok and window.card_rows.is_empty(),"Failed reads offer retry without showing stale friend cards")
	await capture("wishlist-error",window)
	window.dismiss();await frames()
	print("WISHLIST ASSERTIONS: ",assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL",failures.size()])
	quit(0 if failures.is_empty() else 1)
