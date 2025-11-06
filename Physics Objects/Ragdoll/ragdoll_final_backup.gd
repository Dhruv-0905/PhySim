extends Node3D
class_name Ragdoll

@onready var physical_bone_simulator_3d: PhysicalBoneSimulator3D = $metarig/Skeleton3D/PhysicalBoneSimulator3D

var Bones 

func _ready() -> void:
	Bones = physical_bone_simulator_3d.get_children()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		physical_bone_simulator_3d.physical_bones_start_simulation()
