extends RigidBody3D
class_name PhyObj

@onready var mesh_instance_3d   : MeshInstance3D   = $MeshInstance3D
@onready var collision_shape_3d : CollisionShape3D  = $CollisionShape3D

@export var volume          : float = 0.125
@export var object_density  : float = 500.0

var is_in_fluid  : bool = false
var _sonata_body : Node = null

func _ready() -> void:
	set_color()
	volume         = estimate_volume()
	object_density = calculate_density()
	print(volume)
	print(object_density)

	var sonata : Node = preload("res://Physics Objects/Object Base/SonataBody.gd").new()
	sonata.set("env_state",      EnvironmentManager.env_binary)
	sonata.set("air_drag_coeff", EnvironmentManager.get_drag_coefficeint())
	add_child(sonata)
	_sonata_body = sonata

	call_deferred("_log_spawn")

	var logger := get_node_or_null("/root/SonataLogger")
	if logger:
		logger.watch_property(self, "mass",          name + ".mass")
		logger.watch_property(self, "gravity_scale", name + ".gravity_scale")

func _log_spawn() -> void:
	var logger := get_node_or_null("/root/SonataLogger")
	if logger:
		logger.log_event("spawned", {
			"name": name,
			"pos":  str(global_position),
			"mass": mass
		})

# ── Notification API ──────────────────────────────────────────────────────────
# Your UI MUST call these instead of writing gravity_scale / mass directly.
# Both functions write the value first, then notify SonataBody so it can
# rebuild staticnorm and restart warmup with coherent context frames.

func notify_gravity_scale_changed(new_gs: float) -> void:
	gravity_scale = new_gs   # write the real value BEFORE notifying SonataBody
	var logger := get_node_or_null("/root/SonataLogger")
	if logger:
		logger.log_event("gs_changed", {"body": name, "to": new_gs})
	if _sonata_body and _sonata_body.has_method("on_physics_property_changed"):
		_sonata_body.on_physics_property_changed()

func notify_mass_changed(new_mass: float) -> void:
	mass = new_mass          # write the real value BEFORE notifying SonataBody
	var logger := get_node_or_null("/root/SonataLogger")
	if logger:
		logger.log_event("mass_changed", {"body": name, "to": new_mass})
	if _sonata_body and _sonata_body.has_method("on_physics_property_changed"):
		_sonata_body.on_physics_property_changed()

# ── Physics process ───────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not is_in_fluid:
		apply_air_drag()
	despawn()
	if Input.is_action_just_pressed("add"):
		linear_velocity.y += 10

# ── Helpers ───────────────────────────────────────────────────────────────────
func set_color() -> void:
	if mesh_instance_3d == null:
		push_warning("mesh_instance_3d is null on '%s'." % name)
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(randf(), randf(), randf(), 1.0)
	mesh_instance_3d.material_override = material

func despawn() -> void:
	if global_position.y < -50.0:
		queue_free()

func apply_air_drag() -> void:
	var drag_coefficient : float = EnvironmentManager.get_drag_coefficeint()
	if drag_coefficient > 0.0:
		apply_central_force(-linear_velocity * drag_coefficient)

func estimate_volume() -> float:
	if collision_shape_3d == null:
		push_warning("collision_shape_3d is null on '%s'." % name)
		return 0.125
	var shape := collision_shape_3d.shape
	if shape == null:
		return 0.125
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		return s.x * s.y * s.z
	if shape is SphereShape3D:
		var r : float = (shape as SphereShape3D).radius
		return (4.0 / 3.0) * PI * r * r * r
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var r   : float = cap.radius
		var h   : float = cap.height - 2.0 * r
		return PI * r * r * h + (4.0 / 3.0) * PI * r * r * r
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return PI * cyl.radius * cyl.radius * cyl.height
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		if pts.size() >= 2:
			var side : float = (pts[0] as Vector3).distance_to(pts[1] as Vector3)
			return side * side * 1.0
	return 0.125

func calculate_density() -> float:
	return mass / maxf(volume, 1e-6)

func get_body_height_y() -> float:
	if collision_shape_3d == null:
		return 1.0
	var s := collision_shape_3d.shape
	if s == null:             return 1.0
	if s is BoxShape3D:       return (s as BoxShape3D).size.y
	if s is SphereShape3D:    return (s as SphereShape3D).radius * 2.0
	if s is CapsuleShape3D:   return (s as CapsuleShape3D).height
	if s is CylinderShape3D:  return (s as CylinderShape3D).height
	return 1.0
