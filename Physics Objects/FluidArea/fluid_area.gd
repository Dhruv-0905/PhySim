extends Area3D
class_name FluidVolume3D

# ----------------------------------------------------------------
# Fluid Properties
# ----------------------------------------------------------------
@export var fluid_density: float = 1000.0  # kg/m³ (water=1000, oil≈900, honey≈1400)

# ----------------------------------------------------------------
# Basic Object Physics (Phy_Obj — simple linear model)
# ----------------------------------------------------------------
@export_group("Basic Object Physics")
@export var linear_drag: float = 8.0
@export var angular_drag: float = 4.0

# ----------------------------------------------------------------
# Ragdoll Bone Physics (physically accurate quadratic model)
# ----------------------------------------------------------------
@export_group("Ragdoll Bone Physics")
## Drag coefficient for linear motion (~0.8 for cylindrical limbs, 0.47 for spheres)
@export var bone_drag_cd: float = 0.8
## Drag coefficient for rotation (uses volume as rotational cross-section proxy)
@export var bone_angular_drag_cd: float = 0.3
## Buoyancy spring damping. 1.0 = critically damped. >1.0 = overdamped (no oscillation)
@export var damping_ratio: float = 1.5
## m/s² cap on net upward buoyancy acceleration — prevents very light bones from rocketing
@export var max_buoyant_accel: float = 40.0

# ----------------------------------------------------------------
# Waterline Smoothing
# ----------------------------------------------------------------
@export_group("Waterline")
## Smoothing zone height (m) at fluid surface to prevent force snapping
@export var waterline_epsilon: float = 0.02

# ----------------------------------------------------------------
# Internal State
# ----------------------------------------------------------------
var _submerged_bodies: Array[RigidBody3D] = []
var _submerged_bones: Array[PhysicalBone3D] = []
## Cached per bone: { volume: float, height: float, area: float }
var _bone_cache: Dictionary = {}

var _gravity: float = 0.0
@onready var _fluid_col: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# ================================================================
# Physics Tick
# ================================================================

func _physics_process(_delta: float) -> void:
	# Cleanup freed bodies safely (reverse iterate to avoid re-index issues)
	for i in range(_submerged_bodies.size() - 1, -1, -1):
		if not is_instance_valid(_submerged_bodies[i]):
			_submerged_bodies.remove_at(i)
	for i in range(_submerged_bones.size() - 1, -1, -1):
		if not is_instance_valid(_submerged_bones[i]):
			_bone_cache.erase(_submerged_bones[i])
			_submerged_bones.remove_at(i)

	# --- Phy_Obj: simple linear drag model ---
	for body in _submerged_bodies:
		var h :float= body.get_body_height_y()
		var sub := _compute_submersion(body.global_position.y, h)
		if sub.ratio <= 0.0:
			continue
		_apply_buoyancy_force(body.get_rid(), body.mass, body.volume, h,
			sub.submerged_height, sub.ratio, body.linear_velocity.y)
		body.apply_central_force(-linear_drag * body.linear_velocity)
		body.apply_torque(-angular_drag * body.angular_velocity)

	# --- Ragdoll bones: physically accurate quadratic drag model ---
	for bone in _submerged_bones:
		var cache: Dictionary = _bone_cache.get(bone, {})
		var vol: float = cache.get("volume", 0.001)
		var h: float   = cache.get("height",  0.1)
		var area: float = cache.get("area",   0.01)
		var sub := _compute_submersion(bone.global_position.y, h)
		if sub.ratio <= 0.0:
			continue
		var bone_rid := bone.get_rid()
		_apply_buoyancy_force(bone_rid, bone.mass, vol, h,
			sub.submerged_height, sub.ratio, bone.linear_velocity.y)
		_apply_bone_linear_drag(bone_rid, bone.linear_velocity, area, sub.ratio)
		_apply_bone_angular_drag(bone_rid, bone.angular_velocity, vol, sub.ratio)

# ================================================================
# Shared Physics Helpers
# ================================================================

## Computes how much of a body (given its center Y and height) is below the fluid surface.
## Returns { ratio: float, submerged_height: float }.
## Non-box fluid volumes assume full submersion.
func _compute_submersion(center_y: float, body_height: float) -> Dictionary:
	if _fluid_col == null or _fluid_col.shape == null \
			or not (_fluid_col.shape is BoxShape3D):
		return { "ratio": 1.0, "submerged_height": body_height }

	var box := _fluid_col.shape as BoxShape3D
	var surface_y := global_position.y + box.size.y * 0.5
	var h :float= max(body_height, 0.0001)
	var bottom_y := center_y - h * 0.5
	var submerged_h :float= clamp(surface_y - bottom_y, 0.0, h)
	var ratio := submerged_h / h

	# Smoothstep over the first waterline_epsilon meters to prevent force snapping
	if submerged_h < waterline_epsilon:
		var t := submerged_h / waterline_epsilon
		ratio *= t * t * (3.0 - 2.0 * t)

	return { "ratio": ratio, "submerged_height": submerged_h }

## Applies Archimedes buoyancy + critical-damping vertical stabilization.
## Uses PhysicsServer3D so it works for both RigidBody3D and PhysicalBone3D. [web:149]
func _apply_buoyancy_force(
		body_rid: RID,
		mass: float, volume: float, body_h: float,
		submerged_h: float, ratio: float, v_y: float) -> void:
	if volume <= 0.0:
		return
	var h :float= max(body_h, 0.0001)
	# k: buoyancy spring constant (N/m) — force increases linearly with submersion depth
	var k := (fluid_density * _gravity * volume) / h
	var buoyant_force := k * submerged_h
	# Auto-computed critical damping coefficient: c_crit = 2√(m·k)
	# Prevents oscillation without needing manual tuning per body. [web:110]
	var c := 2.0 * sqrt(mass * k) * damping_ratio
	var damp_force := -c * v_y * ratio
	# Only cap upward direction — never artificially prevent sinking
	var total_up := minf(buoyant_force + damp_force, mass * max_buoyant_accel)
	PhysicsServer3D.body_apply_central_force(body_rid, Vector3.UP * total_up)

# ================================================================
# Ragdoll-Specific Quadratic Drag
# ================================================================

## Linear drag: F = -½ · ρ · Cd · A · |v|² (quadratic, density-scaled). [web:134]
## Correctly increases with fluid density and bone cross-section size.
func _apply_bone_linear_drag(
		bone_rid: RID, velocity: Vector3, area: float, ratio: float) -> void:
	var speed := velocity.length()
	if speed < 0.001:
		return
	# Vector form: F = -½ · ρ · Cd · A · |v| · v̂  (magnitude = ½ρCdAv²)
	var drag := -0.5 * fluid_density * bone_drag_cd * area * speed \
		* velocity.normalized() * ratio
	PhysicsServer3D.body_apply_central_force(bone_rid, drag)

## Rotational drag: T = -½ · ρ · C_ang · V · |ω|² (quadratic, density-scaled). [web:150]
## Uses volume as a proxy for the bone's rotational cross-section.
func _apply_bone_angular_drag(
		bone_rid: RID, angular_velocity: Vector3, volume: float, ratio: float) -> void:
	var speed := angular_velocity.length()
	if speed < 0.001:
		return
	var torque := -0.5 * fluid_density * bone_angular_drag_cd * volume * speed \
		* angular_velocity.normalized() * ratio
	PhysicsServer3D.body_apply_torque(bone_rid, torque)

# ================================================================
# Shape Helpers (Volume / Height / Cross-Sectional Area)
# ================================================================

func _volume_from_shape(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		return s.x * s.y * s.z
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return (4.0 / 3.0) * PI * r * r * r
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var cyl_h := cap.height - 2.0 * cap.radius
		return PI * cap.radius * cap.radius * cyl_h \
			+ (4.0 / 3.0) * PI * cap.radius * cap.radius * cap.radius
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return PI * cyl.radius * cyl.radius * cyl.height
	return 0.001

func _height_from_shape(shape: Shape3D) -> float:
	if shape is BoxShape3D:     return (shape as BoxShape3D).size.y
	if shape is SphereShape3D:  return (shape as SphereShape3D).radius * 2.0
	if shape is CapsuleShape3D: return (shape as CapsuleShape3D).height
	if shape is CylinderShape3D:return (shape as CylinderShape3D).height
	return 0.1

## Returns the broadside (maximum) cross-sectional area — the worst-case drag profile.
## Capsule/cylinder limbs use their side-on rectangle; spheres always return πr².
func _area_from_shape(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		# Largest face = maximum resistance orientation
		return maxf(s.x * s.y, maxf(s.x * s.z, s.y * s.z))
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return PI * r * r  # constant in all directions
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return 2.0 * cap.radius * cap.height  # side-on profile
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return 2.0 * cyl.radius * cyl.height  # side-on profile
	return 0.01

## Computes and caches volume, height, and drag area for a bone on entry.
## Done once at entry — shape properties don't change at runtime.
func _cache_bone(bone: PhysicalBone3D) -> void:
	for child in bone.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s = child.shape
			_bone_cache[bone] = {
				"volume": _volume_from_shape(s),
				"height": _height_from_shape(s),
				"area":   _area_from_shape(s)
			}
			return
	# Fallback for bones with no detectable shape
	_bone_cache[bone] = { "volume": 0.001, "height": 0.1, "area": 0.01 }

# ================================================================
# Body Tracking
# ================================================================

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("get_body_height_y") and not _submerged_bodies.has(body): 
		_submerged_bodies.append(body)
		body.is_in_fluid = true
	elif body is PhysicalBone3D and not _submerged_bones.has(body):
		_submerged_bones.append(body)
		body.set_meta("is_in_fluid", true)  # tells EnvironmentManager to skip air drag
		_cache_bone(body)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("get_body_height_y"): 
		_submerged_bodies.erase(body)
		body.is_in_fluid = false
	elif body is PhysicalBone3D:
		_submerged_bones.erase(body)
		_bone_cache.erase(body)
		body.remove_meta("is_in_fluid")

func get_submerged_bodies() -> Array[RigidBody3D]:
	return _submerged_bodies
