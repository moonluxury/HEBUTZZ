extends "res://scripts/backend_provider.gd"
## Explicit isolated integration adapter. Production still enforces HTTPS.
func _endpoint_allowed() -> bool:
	return OS.get_user_data_dir().contains("workbench-check") and base_url == "http://127.0.0.1:8059"

func _remember_session(_response: Dictionary) -> void:
	pass
