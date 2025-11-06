extends RigidBody3D
class_name Phy_Obj

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_color()
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#despawn()
	if Input.is_action_just_pressed("ui_accept"):
		linear_velocity.y = 10

func set_color() -> void:
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(randf(), randf(), randf(),1)
	material.emission_enabled = false
	mesh_instance_3d.material_override = material

func despawn() -> void:
	if global_position.y <= -50:
		queue_free()
