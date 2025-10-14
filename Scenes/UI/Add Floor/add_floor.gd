extends Window

@onready var button: Button = $VBoxContainer/Button
@onready var x_dim: LineEdit = $"VBoxContainer/HBoxContainer/X-dim"
@onready var z_dim: LineEdit = $"VBoxContainer/HBoxContainer2/Z-dim"


func _on_button_pressed() -> void:
	var x_size = x_dim.text.to_float()
	var z_size = z_dim.text.to_float()
	
	if x_size <=0 or z_size <=0:
		push_warning("Invalid size!")
		return
	
	create_floor(x_size,z_size)
	
	visible = false

func create_floor(x: float, z: float):
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	var mesh_material = StandardMaterial3D.new()
	mesh_material.albedo_color = Color.SLATE_GRAY
	plane_mesh.size = Vector2(x,z)
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = mesh_material
	mesh_instance.global_position = Vector3(0, 0, 0)
	add_child(mesh_instance)
	
	var collision = StaticBody3D.new()
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(x, 0.01, z)
	collider.shape = shape
	collision.add_child(collider)
	mesh_instance.add_child(collision)
	


func _on_close_requested() -> void:
	visible = false
