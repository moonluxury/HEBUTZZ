extends Node
## Compose into the existing authenticated provider; never ship a merchant credential.
var endpoint := ""
var authorization: Callable
var response_account: Callable
var allow_loopback_test := false
var pending: Array[HTTPRequest] = []

func wallet_request(action: String, payload: Dictionary) -> Dictionary:
	var account := str(response_account.call()) if response_account.is_valid() else ""
	var loopback := endpoint.begins_with("http://127.0.0.1:")
	var isolated := OS.has_feature("editor") and OS.get_user_data_dir().contains("workbench-check-")
	if not (endpoint.begins_with("https://") or (allow_loopback_test and loopback and isolated)) or not authorization.is_valid():
		return {"ok": false, "account_id": account, "code": "unavailable"}
	var headers: PackedStringArray = authorization.call()
	if headers.is_empty(): return {"ok": false, "account_id": account, "code": "unauthenticated"}
	headers = headers.duplicate()
	headers.append("Content-Type: application/json")
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.body_size_limit = 1048576
	http.max_redirects = 0
	add_child(http)
	pending.append(http)
	var issue := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify({"version": 1, "action": action, "payload": payload}))
	if issue != OK:
		pending.erase(http)
		http.queue_free()
		return {"ok": false, "account_id": account, "code": "unknown"}
	var result: Array = await http.request_completed
	pending.erase(http)
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS: return {"ok": false, "account_id": account, "code": "unknown"}
	if int(result[1]) == 401: return {"ok": false, "account_id": account, "code": "unauthenticated"}
	var parser := JSON.new()
	if parser.parse(result[3].get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": false, "account_id": account, "code": "unknown"}
	var response: Dictionary = parser.data
	if int(result[1]) < 200 or int(result[1]) >= 300: response.ok = false
	return response

func wallet_cancel_requests() -> void:
	for http in pending.duplicate():
		if is_instance_valid(http):
			http.cancel_request()
			# Wake callers so they can discard their captured session epoch.
			http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
