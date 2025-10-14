extends Node

signal spawn_button_pressed(object: PackedScene)
signal object_added(obj: Node3D)
signal object_selected(obj: Node)
signal  camera_obj_selected(obj: Node)

# when the object button is pressed
func on_spawn_button_pressed(object: PackedScene):
	spawn_button_pressed.emit(object)
	
# when an object is added to the environment
func on_object_added(obj: Node3D):
	object_added.emit(obj)

func on_object_selected(obj: Node):
	object_selected.emit(obj)

func on_camera_obj_selected(obj_idx: int):
	camera_obj_selected.emit(obj_idx)
