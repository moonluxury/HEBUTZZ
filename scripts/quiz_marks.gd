extends Node
## Stable bank/question keys; separate from wrong answers and rewards.
signal changed
const JsonStore = preload("res://scripts/local_json_store.gd")
const PATH := "user://quiz_marks_v1.json"
var accounts: Dictionary = {}
var account_key := "guest"

func _ready() -> void:
	var saved: Variant = JsonStore.read(PATH, {})
	if saved is Dictionary: accounts = saved
	get_node("/root/ProfileStore").changed.connect(_session_changed)
	_session_changed()

func _session_changed() -> void:
	var profile := get_node("/root/ProfileStore")
	var next := str(profile.account_id) if profile.authenticated() else "guest"
	if account_key != next:
		account_key = next
		changed.emit()

func marked(bank: String, question: String) -> bool:
	return accounts.get(account_key, {}).get(bank, {}).get(question, false) == true

func toggle(bank: String, question: String) -> bool:
	var next := accounts.duplicate(true)
	if not next.has(account_key): next[account_key] = {}
	if not next[account_key].has(bank): next[account_key][bank] = {}
	if marked(bank, question): next[account_key][bank].erase(question)
	else: next[account_key][bank][question] = true
	if JsonStore.write(PATH, next) != OK: return false
	accounts = next
	changed.emit()
	return true
