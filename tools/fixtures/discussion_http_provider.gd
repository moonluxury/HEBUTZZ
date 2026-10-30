extends "res://scripts/backend_provider.gd"
## Loopback exception exists only in this isolated test provider.
var requests: Array = []
var fail_next := false
var response_delay := 0.0
var read_delay := 0.0

func _ready() -> void:
	base_url = "http://127.0.0.1:18547"

func _endpoint_allowed() -> bool:
	return OS.get_user_data_dir().contains("workbench-check") and base_url == "http://127.0.0.1:18547"

func _remember_session(_response: Dictionary) -> void:
	pass

func comment_request(action: String, payload: Dictionary) -> Dictionary:
	requests.append({"action": action, "payload": payload.duplicate(true)})
	if fail_next:
		fail_next = false
		await get_tree().create_timer(0.08).timeout
		return {"ok": false, "code": "network", "message": "隔离测试：网络连接失败，输入已保留。"}
	var delay := response_delay + (read_delay if action in ["comment_list", "comment_replies"] else 0.0)
	var response := await super.comment_request(action, payload)
	if delay > 0: await get_tree().create_timer(delay).timeout
	return response
