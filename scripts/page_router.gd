extends Node
## Detached pages keep their controls and scroll state, but cannot process input.
## The sidebar is retained separately and attached to the active page's canvas.
const CACHE_LIMIT := 4
const CACHEABLE := ["Workbench", "SubjectSelect", "HegongKaiwu", "MyCollection"]
var pages: Dictionary = {}
var recent: Array[String] = []
var scenes: Dictionary = {}
var sidebar: Panel
var pending := ""
var switch_queued := false
var identity_login_requested := false

func wallet_store() -> Node:
	var store := get_node_or_null("WalletStore")
	if store == null:
		store = preload("res://scripts/wallet_store.gd").new()
		store.name = "WalletStore"
		add_child(store)
	return store

func social_store() -> Node:
	var store := get_node_or_null("SocialStore")
	if store == null:
		store = preload("res://scripts/social_store.gd").new()
		store.name = "SocialStore"
		add_child(store)
	return store

func open_friends(from_bell := false) -> void:
	social_store().bell_requested = from_bell
	go("res://scenes/MyFriends.tscn")

func collection_store() -> Node:
	var store := get_node_or_null("CollectionStore")
	if store == null:
		store = preload("res://scripts/collection_store.gd").new()
		store.name = "CollectionStore"
		add_child(store)
	return store

func open_identity() -> void:
	identity_login_requested = get_node("/root/ProfileStore").session_state == "signed_out"
	go("res://scenes/PersonalCenter.tscn")

func key_for(path: String, mode: String) -> String:
	return path + (":" + mode if path.ends_with("SubjectSelect.tscn") else "")

func packed_scene(path: String) -> PackedScene:
	if not scenes.has(path):
		scenes[path] = load(path)
	return scenes[path]

func go(path: String) -> void:
	pending = path
	if not switch_queued:
		switch_queued = true
		_switch.call_deferred()

func open_subjects(mode: String) -> void:
	var app := get_node("/root/AppState")
	app.quiz_mode = mode
	app.start_index = 0
	go("res://scenes/SubjectSelect.tscn")

func back() -> void:
	# One action closes one local layer, or navigates to this page's parent.
	if switch_queued:
		return
	var page := get_tree().current_scene
	if not is_instance_valid(page):
		return
	if page.has_method("consume_back_action") and page.consume_back_action():
		return
	match page.scene_file_path.get_file().get_basename():
		"Workbench":
			return
		"Quiz":
			# Keep the current all/wrong mode and the cached bank's filters/scroll.
			go("res://scenes/SubjectSelect.tscn")
		"HegongKaiwuDetail":
			go("res://scenes/HegongKaiwu.tscn")
		_:
			go("res://scenes/Workbench.tscn")

func _switch() -> void:
	switch_queued = false
	var path := pending
	var tree := get_tree()
	var key := key_for(path, get_node("/root/AppState").quiz_mode)
	var previous := tree.current_scene
	if is_instance_valid(previous) and previous.get_meta("route_key", "") == key and _cacheable(previous):
		previous.page_activated()
		tree.scene_changed.emit()
		return
	var next: Node = pages.get(key)
	var reused := is_instance_valid(next)
	if not reused:
		var packed := packed_scene(path)
		if packed == null:
			push_error("无法加载页面：" + path)
			return
		next = packed.instantiate()
	pages.erase(key)
	recent.erase(key)
	if is_instance_valid(sidebar):
		sidebar.reparent(self, false)
		sidebar.hide()
	if is_instance_valid(previous):
		get_node("/root/UiMotion").settle_subtree(previous)
		tree.current_scene = null
		previous.hide()
		previous.process_mode = Node.PROCESS_MODE_DISABLED
		tree.root.remove_child(previous)
		if _cacheable(previous):
			var old_key := str(previous.get_meta("route_key", previous.scene_file_path))
			if pages.has(old_key) and pages[old_key] != previous:
				pages[old_key].free()
			pages[old_key] = previous
			recent.erase(old_key)
			recent.append(old_key)
		else:
			previous.queue_free()
	while recent.size() > CACHE_LIMIT:
		var expired: String = recent.pop_front()
		pages[expired].free()
		pages.erase(expired)
	next.set_meta("route_key", key)
	next.process_mode = Node.PROCESS_MODE_INHERIT
	tree.root.add_child(next)
	tree.current_scene = next
	next.show()
	if reused:
		next.page_activated()
	tree.scene_changed.emit()

func _cacheable(page: Node) -> bool:
	return page.scene_file_path.get_file().get_basename() in CACHEABLE

func _exit_tree() -> void:
	# Detached nodes are not freed by SceneTree shutdown.
	for page in pages.values():
		if is_instance_valid(page):
			page.free()
	pages.clear()
