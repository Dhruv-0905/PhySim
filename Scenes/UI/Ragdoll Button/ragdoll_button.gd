extends Button

@export var ragdoll: PackedScene

func _on_pressed() -> void:
	SignalManager.on_ragdoll_button_pressed(ragdoll)
	focus_mode = 0
