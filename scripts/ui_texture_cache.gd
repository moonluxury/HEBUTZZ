extends Node
## Shared asynchronous texture cache; no page or account lifecycle.
var textures: Dictionary = {}
var _texture_requests: Dictionary = {}
var _texture_failures: Dictionary = {}

func _ready() -> void:
	set_process(false)

func texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load(path)
	return textures[path]

func request_texture(path: String) -> bool:
	# The persistent cache drains requests even if their requesting page is closed.
	# No worker completion owns a UI node or can reopen a cancelled presentation.
	if textures.get(path) is Texture2D or _texture_requests.has(path):
		return true
	_texture_failures.erase(path)
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		_texture_failures[path] = true
		return false
	if ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
		_texture_failures[path] = true
		return false
	_texture_requests[path] = true
	set_process(true)
	return true

func texture_load_status(path: String) -> int:
	if textures.get(path) is Texture2D:
		return ResourceLoader.THREAD_LOAD_LOADED
	if _texture_failures.has(path):
		return ResourceLoader.THREAD_LOAD_FAILED
	return ResourceLoader.THREAD_LOAD_IN_PROGRESS if _texture_requests.has(path) else ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

func _process(_delta: float) -> void:
	for path in _texture_requests.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_texture_requests.erase(path)
		var loaded: Texture2D = ResourceLoader.load_threaded_get(path) as Texture2D if status == ResourceLoader.THREAD_LOAD_LOADED else null
		if loaded != null:
			textures[path] = loaded
		else:
			_texture_failures[path] = true
	if _texture_requests.is_empty():
		set_process(false)
