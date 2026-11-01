extends SceneTree
## Explicit opt-in; temporary account IDs are recorded for guarded server cleanup.
const Provider = preload("res://scripts/backend_provider.gd")
const Collection = preload("res://scripts/collection_store.gd")
var failures := 0
var assertions := 0

class SecondDevice extends Collection:
	func _path() -> String: return "user://second-device/" + account_id.sha256_text()+".json"

func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(label)
func settled(collection: Node) -> void:
	for attempt in 150:
		await create_timer(0.1).timeout
		if collection.wishlist.loaded and not collection.wishlist.busy and collection.wishlist.pending.is_empty() and collection.wishlist.inflight.is_empty() and collection.wishlist.error.is_empty(): return
	check(false,"Wishlist synchronization timed out")

func _run() -> void:
	if OS.get_environment("HEGONG_WISHLIST_LIVE") != "1" or not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await process_frame
	var api: Node = root.get_node("BackendProvider")
	check(api.base_url=="https://39.107.44.18","Use the configured verified HTTPS service")
	var username := "wishcheck_"+Crypto.new().generate_random_bytes(6).hex_encode()+"a"
	var password := Crypto.new().generate_random_bytes(24).hex_encode()
	var account: Dictionary = await api.password_auth(username,password,true)
	check(account.get("ok",false),"Register disposable live identity")
	if not account.get("ok",false): quit(1);return
	var record := FileAccess.open(OS.get_environment("HEGONG_WISHLIST_ACCOUNTS"),FileAccess.WRITE)
	record.store_string(JSON.stringify({"accounts":[{"id":account.account_id,"username":username}]}));record.close()
	api.account_id=account.account_id;api.access_token=account.access_token
	root.get_node("ProfileStore").use_provider(api,{"state":"authenticated","account_id":api.account_id})
	var collection: Node = root.get_node("AppServices").collection_store()
	collection.wanted={"0003":true};collection._save_local()
	await settled(collection)
	var data: Dictionary = await api.wishlist_request("wishlist_load",{})
	check(data.get("card_ids")==["0003"],"Real cloud receives the original local wishlist")
	for enabled in [true,false,true]: collection.set_wanted("0001",enabled)
	await settled(collection)
	data=await api.wishlist_request("wishlist_load",{})
	check(data.get("card_ids")==["0001","0003"],"Actual Godot JSON writes the final desired card state")
	var second := Provider.new();root.add_child(second)
	var login: Dictionary = await second.password_auth(username,password)
	check(login.get("ok",false),"Second session signs in")
	second.account_id=login.account_id;second.access_token=login.access_token
	var device := SecondDevice.new();root.add_child(device);device.use_provider(second,api.account_id)
	await settled(device)
	check(device.is_wanted("0001") and device.is_wanted("0003"),"An empty second-device cache reads the cloud list")
	device.set_wanted("0001",false);device.set_wanted("0002",true);await settled(device)
	await collection.wishlist.refresh()
	check(not collection.is_wanted("0001") and collection.is_wanted("0002"),"First device reads additions and removals from the second device")
	data=await api.wishlist_request("wishlist_load",{})
	var payload := {"operation_id":Crypto.new().generate_random_bytes(24).hex_encode(),"expected_revision":int(data.wishlist_revision),"changes":{"0004":true}}
	check((await api.wishlist_request("wishlist_update",payload)).get("ok",false),"Prepare a committed operation with a simulated lost local receipt")
	collection.wishlist.inflight=payload;collection.wishlist.pending={"0004":true};collection._save_local()
	collection.use_provider(api,api.account_id);await settled(collection)
	check(collection.is_wanted("0004") and collection.wishlist.inflight.is_empty(),"Reloaded JSON outbox replays the original operation over HTTPS")
	check(collection.wishlist.error.is_empty(),"No sync error after real persistence and replay")
	root.get_node("ProfileStore").use_provider(api,{"state":"signed_out"})
	device.use_provider(null,"local-profile")
	await api.logout(api.account_id);await second.logout(second.account_id)
	print("WISHLIST HTTPS ASSERTIONS: ",assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	quit(0 if failures==0 else 1)
