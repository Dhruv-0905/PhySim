# ==============================================================
# SONATA I — Module 6: Per-Object Physics Predictor
# SonataBody.gd  →  Add as child of RigidBody3D
# ==============================================================
extends Node

# ── Inspector properties ──────────────────────────────────────
@export var ml_enabled     := true
@export var env_state      := 0       # 0 = VACUUM,  1 = ATMOSPHERE
@export var air_drag_coeff := 0.0

# FIX 1: @export_enum IS the export annotation — do NOT add @export again
@export_enum("AUTO", "SPHERE:0", "BOX:1", "CAPSULE:2", "CYLINDER:3",
			 "CONCAVE:4", "CONVEX:5") var shape_override: String = "AUTO"

# ── Normalization constants ───────────────────────────────────
# FIX 2: PackedFloat32Array([...]) is a constructor call — not a compile-time
# constant. Change const → var. Values are never written after _ready().

var S_MEAN: PackedFloat32Array = PackedFloat32Array([
	 543.4700,  0.48556, 0.58294, 0.38327,  0.51825,
	   0.51825, 0.08427, 0.56180, 2.52111,  0.75252,  0.83914])

var S_STD: PackedFloat32Array = PackedFloat32Array([
	1023.3305,  4.39475, 0.32203, 0.25406,  0.51240,
	   0.51240, 0.07443, 0.49618, 1.70805,  0.24999,  0.68852])

var D_MEAN: PackedFloat32Array = PackedFloat32Array([
	-0.005323,  53.8559,  0.019467,
	 0.439676,   0.10559,  0.11818,  0.09974,
	-0.004726,  27.9688,  0.002462,
	-0.016807,   0.00927, -0.006999,
	29.5774, 807330.95, 443.914, -1102996.67, -295221.80,
	 0.94816,   126.798])

var D_STD: PackedFloat32Array = PackedFloat32Array([
	 2.83557,  116.374,   2.84093,
	 0.44447,    0.43367,  0.43895,  0.43968,
	 1.01805,   55.4346,   1.02147,
	 2.23182,    1.80319,  2.22977,
	54.6123,  4835016.48, 2945.95, 5751267.23, 1747046.24,
	 1.45573,  1340.032])

var T_MEAN: PackedFloat32Array = PackedFloat32Array([
	-0.005323,  53.8559,   0.019467,
	 0.439676,   0.10559,   0.11818,  0.09974,
	-0.004726,  27.9688,   0.002462,
	-0.016807,   0.00927,  -0.006999])

var T_STD: PackedFloat32Array = PackedFloat32Array([
	 2.83557,  116.374,    2.84093,
	 0.44447,    0.43367,   0.43895,  0.43968,
	 1.01805,   55.4346,   1.02147,
	 2.23182,    1.80319,   2.22977])

const WINDOW      := 10
const STATIC_DIM  := 11
const DYNAMIC_DIM := 20
const FUSED_DIM   := 31

# ── Runtime state ─────────────────────────────────────────────
var _body          : RigidBody3D
var _ctx_buffer    : Array = []
var _static_norm   : PackedFloat32Array
var _contact_count : int   = 0
var _max_impulse   : float = 0.0
var _shape_type    : int   = 0
var _shape_prim    : float = 0.5
var _shape_sec     : float = 0.0


# ── Initialization ────────────────────────────────────────────
func _ready() -> void:
	_body = get_parent() as RigidBody3D
	assert(_body != null, "SonataBody must be a child of RigidBody3D")

	_detect_shape()
	_static_norm = _build_static_norm()

	_body.contact_monitor = true
	_body.max_contacts_reported = 4
	_body.body_entered.connect(_on_contact_enter)
	_body.body_exited.connect(_on_contact_exit)

	# FIX 3: Use /root/ path instead of bare autoload name.
	# The bare name only resolves after the autoload is registered
	# in Project Settings → Autoload. The /root/ path works always.
	get_node("/root/SonataPredictor").register(self)


func _exit_tree() -> void:
	get_node("/root/SonataPredictor").unregister(self)


# ── Shape detection ───────────────────────────────────────────
func _detect_shape() -> void:
	if shape_override != "AUTO":
		_shape_type = int(shape_override.split(":")[1])

	for child in _body.get_children():
		if child is CollisionShape3D and child.shape != null:
			# FIX 4: Explicit type annotation required — := cannot infer
			# a concrete type when the property returns base class Shape3D
			var s: Shape3D = child.shape

			if shape_override == "AUTO":
				if   s is SphereShape3D:         _shape_type = 0
				elif s is BoxShape3D:            _shape_type = 1
				elif s is CapsuleShape3D:        _shape_type = 2
				elif s is CylinderShape3D:       _shape_type = 3
				elif s is ConcavePolygonShape3D: _shape_type = 4
				else:                            _shape_type = 5

			if s is SphereShape3D:
				_shape_prim = (s as SphereShape3D).radius
				_shape_sec  = 0.0
			elif s is BoxShape3D:
				_shape_prim = (s as BoxShape3D).size.x * 0.5
				_shape_sec  = (s as BoxShape3D).size.y * 0.5
			elif s is CapsuleShape3D:
				_shape_prim = (s as CapsuleShape3D).radius
				_shape_sec  = (s as CapsuleShape3D).height
			elif s is CylinderShape3D:
				_shape_prim = (s as CylinderShape3D).radius
				_shape_sec  = (s as CylinderShape3D).height
			break


# ── Static feature vector (computed once) ────────────────────
func _build_static_norm() -> PackedFloat32Array:
	var mat      := _body.physics_material_override
	var friction := mat.friction if mat else 0.5
	var bounce   := mat.bounce   if mat else 0.3

	var raw := PackedFloat32Array([
		_body.mass,
		_body.gravity_scale,
		friction,
		bounce,
		_body.linear_damp,
		_body.angular_damp,
		air_drag_coeff,
		float(env_state),
		float(_shape_type),
		_shape_prim,
		_shape_sec,
	])
	return _normalize(raw, S_MEAN, S_STD)


# ── Dynamic feature extraction ────────────────────────────────
func _extract_dynamic_norm() -> PackedFloat32Array:
	var p  := _body.global_position
	var q  := _body.quaternion
	var lv := _body.linear_velocity
	var av := _body.angular_velocity
	var m  := _body.mass
	var gs := _body.gravity_scale

	var speed := lv.length()
	var ke    := 0.5 * m * speed * speed
	var re    := 0.5 * m * (_shape_prim * _shape_prim) * av.length_squared()
	var pe    := m * absf(gs) * 9.80665 * p.y
	var te    := ke + re + pe

	var raw := PackedFloat32Array([
		p.x,  p.y,  p.z,
		q.w,  q.x,  q.y,  q.z,
		lv.x, lv.y, lv.z,
		av.x, av.y, av.z,
		speed, ke, re, pe, te,
		float(_contact_count),
		_max_impulse,
	])
	_max_impulse = 0.0
	return _normalize(raw, D_MEAN, D_STD)


# ── Context window ────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not ml_enabled:
		return

	var dyn_norm := _extract_dynamic_norm()
	var frame    := PackedFloat32Array()
	frame.append_array(_static_norm)
	frame.append_array(dyn_norm)

	_ctx_buffer.push_back(frame)
	if _ctx_buffer.size() > WINDOW:
		_ctx_buffer.pop_front()


func is_ready_for_inference() -> bool:
	return ml_enabled and _ctx_buffer.size() == WINDOW


func get_context() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(WINDOW * FUSED_DIM)
	for t in range(WINDOW):
		for f in range(FUSED_DIM):
			out[t * FUSED_DIM + f] = _ctx_buffer[t][f]
	return out


# ── Apply prediction ──────────────────────────────────────────
func apply_prediction(pred: PackedFloat32Array) -> void:
	"""
	Velocity-only mode: model sets velocity each tick,
	Godot physics integrates position and resolves collisions.
	This prevents levitation from position error accumulation.
	"""
	# Denormalize first predicted frame (indices 0-12)
	var new_lv := Vector3(
		pred[7]  * T_STD[7]  + T_MEAN[7],
		pred[8]  * T_STD[8]  + T_MEAN[8],
		pred[9]  * T_STD[9]  + T_MEAN[9]
	)
	var new_av := Vector3(
		pred[10] * T_STD[10] + T_MEAN[10],
		pred[11] * T_STD[11] + T_MEAN[11],
		pred[12] * T_STD[12] + T_MEAN[12]
	)

	# Clamp to physically plausible range — prevents rare model outliers
	# from launching objects off-screen
	new_lv = new_lv.clamp(Vector3(-400, -400, -400), Vector3(400, 400, 400))
	new_av = new_av.clamp(Vector3(-50, -50, -50),    Vector3(50,  50,  50))

	_body.linear_velocity  = new_lv
	_body.angular_velocity = new_av


# ── Contact tracking ──────────────────────────────────────────
func _on_contact_enter(_body_node: Node) -> void:
	_contact_count += 1

func _on_contact_exit(_body_node: Node) -> void:
	_contact_count = max(0, _contact_count - 1)


# ── Utility ───────────────────────────────────────────────────
func _normalize(raw: PackedFloat32Array,
				mean: PackedFloat32Array,
				std:  PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(raw.size())
	for i in range(raw.size()):
		out[i] = (raw[i] - mean[i]) / std[i]
	return out
