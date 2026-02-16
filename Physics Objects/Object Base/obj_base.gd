extends RigidBody3D
class_name Phy_Obj

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var height_ref: Marker3D = $Marker3D

@export var volume: float = 0.125  # m³ (default: 0.5×0.5×0.5 cube)
@export var object_density: float = 500.0  # kg/m³ (< 1000 floats in water, > 1000 sinks)

var is_in_fluid := false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_color()
	volume = estimate_volume()
	object_density = calculate_density()
	print(volume)
	print(object_density)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if not is_in_fluid:
		apply_air_drag()
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

func apply_air_drag() -> void:
	var drag_coefficient = EnvironmentManager.get_drag_coefficeint()
	
	if drag_coefficient > 0.0:
		var drag_force = -linear_velocity * drag_coefficient
		apply_central_force(drag_force)

func estimate_volume() -> float:
	var shape = collision_shape_3d.shape
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return size.x*size.y*size.z
	
	if shape is SphereShape3D:
		var radius = (shape as SphereShape3D).radius
		return (4.0/3.0) * PI * radius*radius*radius
	
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var r := cap.radius
		var h := cap.height - 2.0 * r  # cylinder height
		return PI * r * r * h + (4.0/3.0) * PI * r * r * r  # cylinder + sphere
	
	if shape is CylinderShape3D:
		var cyl = shape as CylinderShape3D
		var r = cyl.radius
		var h = cyl.height
		return PI * r * r * h

		
	if shape is ConvexPolygonShape3D:
		var points = shape.points
		var side = abs((points[0] as Vector3).distance_to(points[1] as Vector3))
		var height = abs((points[0] as Vector3).distance_to(height_ref.position))
		return side * side * height
	
	return 0.125

func calculate_density()-> float:
	return mass / volume

func get_body_height_y() -> float:
	var s := collision_shape_3d.shape
	if s is BoxShape3D:
		return (s as BoxShape3D).size.y # box height comes from size [page:8]
	if s is SphereShape3D:
		return (s as SphereShape3D).radius * 2.0
	if s is CapsuleShape3D:
		var cap := s as CapsuleShape3D
		# Keep consistent with your volume estimator (you treated cap.height as total height).
		return cap.height # capsule has height + radius properties [page:9]
	if s is CylinderShape3D:
		return (s as CylinderShape3D).height
	return 1.0
