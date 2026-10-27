extends "res://scripts/card_reveal.gd"
## Test-only loading gate; production never references this fixture.
var hold_loading := true

func _poll_resources() -> void:
	if not hold_loading:
		super._poll_resources()
