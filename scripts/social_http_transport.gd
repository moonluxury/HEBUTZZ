extends Node
## Optional transport composed into the existing authenticated host provider.
## No endpoint, credential, login system or demo fallback is configured by this project.
var endpoint := ""
var authorization: Callable
var response_account: Callable
var allow_loopback_test := false
const TIMEOUT_SECONDS := 12.0
const RESPONSE_LIMIT := 2097152

func social_request(action: String, payload: Dictionary) -> Dictionary:
	var account := str(response_account.call()) if response_account.is_valid() else ""
	var local := endpoint.begins_with("http://127.0.0.1:") or endpoint.begins_with("http://localhost:")
	if not (endpoint.begins_with("https://") or (allow_loopback_test and local)) or not authorization.is_valid():
		return {"ok": false, "account_id": account, "code": "unavailable", "message": "尚未配置已有服务的 HTTPS 地址与会话授权。"}
	var headers: PackedStringArray = authorization.call()
	if headers.is_empty():
		return {"ok": false, "account_id": account, "code": "unauthenticated", "message": "登录已失效，请重新登录。"}
	headers.append("Content-Type: application/json")
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	http.body_size_limit = RESPONSE_LIMIT
	http.max_redirects = 0 # Never forward a credential to a redirected endpoint.
	add_child(http)
	var error := http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify({"version": 1, "action": action, "payload": payload}))
	if error != OK:
		http.queue_free()
		return {"ok": false, "account_id": account, "code": "network", "message": "无法发起请求，请检查网络后重试。"}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "account_id": account, "code": "unknown", "message": "网络中断或超时，结果尚未确认。请使用原操作重试。"}
	if int(result[1]) == 401:
		return {"ok": false, "account_id": account, "code": "unauthenticated", "message": "登录已失效。"}
	var parser := JSON.new()
	var parsed_ok := parser.parse(result[3].get_string_from_utf8()) == OK
	var parsed: Variant = parser.data
	if not parsed_ok or not parsed is Dictionary:
		return {"ok": false, "account_id": account, "code": "unknown", "message": "服务响应格式异常，结果尚未确认。"}
	if int(result[1]) < 200 or int(result[1]) >= 300:
		parsed.ok = false
	return parsed
