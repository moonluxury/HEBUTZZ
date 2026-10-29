extends Node
## Last account metadata plus an OS-protected session, scoped to the exact server.
signal changed
const JsonStore = preload("res://scripts/local_json_store.gd")
const Protection = preload("res://scripts/windows_data_protection.gd")
const SAVE_DIR := "user://last_login_v1"
var endpoint := ""
var record: Dictionary = {}
var revision := 0
var busy := false
var protection: Node

func configure(server: String) -> void:
	revision += 1
	busy = false
	endpoint = server.trim_suffix("/")
	record = {}
	if not is_instance_valid(protection):
		protection = Protection.new()
		add_child(protection)
	var saved = JsonStore.read(path(), {})
	if saved is Dictionary and saved.get("version") == 1 and saved.get("endpoint") == endpoint and valid_username(str(saved.get("username", ""))) and not str(saved.get("account_id", "")).is_empty():
		record = saved
	changed.emit()

static func valid_username(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_]{4,32}$")
	return pattern.search(value) != null

func path() -> String:
	return SAVE_DIR.path_join(endpoint.sha256_text() + ".json")

func account() -> Dictionary:
	if record.is_empty(): return {}
	return {"username": record.username, "account_id": record.account_id,
		"can_resume": protection.supported() and not str(record.get("protected_session", "")).is_empty()}

func remember(username: String, account_id: String, token: String, expires_at := "") -> bool:
	if not valid_username(username) or account_id.is_empty() or token.is_empty(): return false
	revision += 1
	var ticket := revision
	record = {"version": 1, "endpoint": endpoint, "username": username, "account_id": account_id,
		"expires_at": expires_at, "protected_session": ""}
	# Save the last successful account immediately, even if secure storage is unavailable.
	if JsonStore.write(path(), record) != OK: return false
	changed.emit()
	if not protection.supported(): return false
	busy = true
	var payload := JSON.stringify({"endpoint": endpoint, "username": username, "account_id": account_id, "access_token": token})
	var encrypted: PackedByteArray = await protection.transform(payload.to_utf8_buffer(), true)
	if ticket != revision: return false
	busy = false
	if encrypted.is_empty(): return false
	var next := record.duplicate(true)
	next.protected_session = Marshalls.raw_to_base64(encrypted)
	if JsonStore.write(path(), next) != OK: return false
	record = next
	changed.emit()
	return true

func credential() -> Dictionary:
	if record.is_empty() or not account().can_resume: return {}
	var ticket := revision
	var saved := record.duplicate(true)
	var encoded := str(saved.protected_session)
	if encoded.length() > 32768: return {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if encoded.length() % 4 != 0 or pattern.search(encoded) == null: return {}
	var decrypted: PackedByteArray = await protection.transform(Marshalls.base64_to_raw(encoded), false)
	if ticket != revision or decrypted.is_empty(): return {}
	var value = JSON.parse_string(decrypted.get_string_from_utf8())
	if not value is Dictionary or value.get("endpoint") != endpoint or value.get("username") != saved.username or value.get("account_id") != saved.account_id:
		return {}
	if not value.get("access_token") is String or value.access_token.is_empty() or value.access_token.length() > 256: return {}
	return value

func invalidate(owner: String) -> void:
	if record.is_empty() or record.account_id != owner: return
	revision += 1
	busy = false
	record.protected_session = ""
	JsonStore.write(path(), record)
	changed.emit()

func forget() -> bool:
	if JsonStore.write(path(), {}) != OK: return false
	revision += 1
	busy = false
	record = {}
	changed.emit()
	return true
