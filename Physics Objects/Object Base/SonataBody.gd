extends Node
# SonataBody.gd — SONATA-I v5  (state-machine + contact-lag fix + gs-change reset)
# Attach as a child of any RigidBody3D in your scene.
#
# v5 Changes (GS-FIX):
#   - on_physics_property_changed() now MUST be called from objbase.gd
#     whenever mass, gravity_scale, linear_damp, or angular_damp change.
#   - Added _gs_change_threshold: any gs delta above this triggers a full
#     warmup reset so the context buffer is never stale after a gs change.
#   - _physics_process now polls gs every frame as a safety net, so even
#     if objbase.gd forgets to call on_physics_property_changed() the
#     reset still fires automatically.
#   - ctx_buffer is cleared and warmup restarted on EVERY property change,
#     not just on ml_enabled toggle or env-state change.

# ── Normalization stats ───────────────────────────────────────────────────────
static var SMEAN : PackedFloat32Array = PackedFloat32Array([
	543.4700, 0.48556, 0.58294, 0.38327, 0.51825,
	0.51825,  0.08427, 0.56180, 2.52111, 0.75252, 0.83914])
static var SSTD  : PackedFloat32Array = PackedFloat32Array([
	1023.330, 4.39475, 0.32203, 0.25406, 0.51240,
	0.51240,  0.07443, 0.49618, 1.70805, 0.24999, 0.68852])
static var DMEAN : PackedFloat32Array = PackedFloat32Array([
	-0.00532,  53.8559,  0.01947,  0.43968,  0.10559,
	 0.11818,  0.09974, -0.00473, 27.9688,  0.00246,
	-0.01681,  0.00927, -0.00700, 29.5774,  807330.95,
	 443.914,-1102996.67,-295221.80, 0.94816,  126.798])
static var DSTD  : PackedFloat32Array = PackedFloat32Array([
	  2.83557, 116.374,   2.84093,  0.44447,  0.43367,
	  0.43895,  0.43968,  1.01805, 55.4346,   1.02147,
	  2.23182,  1.80319,  2.22977, 54.6123, 4835016.5,
	  2945.95, 5751267.2, 1747046.2, 1.45573,  1340.032])
static var TMEAN : PackedFloat32Array = PackedFloat32Array([
	-0.00532, 53.8559, 0.01947, 0.43968, 0.10559,
	 0.11818,  0.09974,-0.00473,27.9688, 0.00246,
	-0.01681,  0.00927,-0.00700])
static var TSTD  : PackedFloat32Array = PackedFloat32Array([
	2.83557, 116.374, 2.84093, 0.44447, 0.43367,
	0.43895,  0.43968,  1.01805,55.4346, 1.02147,
	2.23182,  1.80319, 2.22977])

# ── Inspector exports ─────────────────────────────────────────────────────────
@export_enum("SPHERE:0","CUBE:1","CYLINDER:2","CAPSULE:3","CUBOID:4","PRISM:5")
var shape_type        : int   = 1
@export var env_state      : int   = 0
@export var air_drag_coeff : float = 0.0
@export var ml_enabled     : bool  = true
@export var lv_lateral_decay : float = 0.990
@export var av_decay         : float = 0.970
@export var debug_log    : bool  = false
@export var debug_frames : int   = 120

# GS-FIX: how much gs must change in one poll to trigger a full reset.
# 0.5 catches all intentional slider moves without false-triggering
# on floating-point noise.
@export var gs_change_threshold : float = 0.5

# ── State machine ─────────────────────────────────────────────────────────────
enum State { GODOT_WARMUP, MLFLIGHT, GODOT_CONTACT }

# ── Runtime variables ─────────────────────────────────────────────────────────
var body               : RigidBody3D = null
var orig_gravity_scale : float = 1.0
var orig_linear_damp   : float = 0.0
var orig_angular_damp  : float = 0.0
var shape_dim_primary  : float = 0.5
var shape_dim_secondary: float = 0.0
var staticnorm         : PackedFloat32Array
var ctx_buffer         : Array  = []
var _state             : State  = State.GODOT_WARMUP
var _contact_dur       : int    = 0
var debug_frame_count  : int    = 0

# GS-FIX: tracks the last gs value we built staticnorm for.
# Compared every physics frame; mismatch fires _on_gs_changed().
var _last_polled_gs    : float  = 1.0   # GS-FIX

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	body = get_parent() as RigidBody3D
	assert(body != null, "SonataBody must be a child of RigidBody3D")

	orig_gravity_scale = body.gravity_scale
	orig_linear_damp   = body.linear_damp
	orig_angular_damp  = body.angular_damp

	# GS-FIX: seed the poll tracker so the first frame never false-triggers.
	_last_polled_gs = orig_gravity_scale   # GS-FIX

	detect_shape()
	staticnorm = build_static_norm()

	body.contact_monitor       = true
	body.max_contacts_reported = 4

	add_to_group("sonata_bodies")
	SonataPredictor.register(self)

	if debug_log:
		print("SONATA Logger ON  body=%s  frames=%d" % [body.name, debug_frames])
		print("SONATA orig gs=%.4f  ld=%.4f  ad=%.4f" % [
			orig_gravity_scale, orig_linear_damp, orig_angular_damp])

func _exit_tree() -> void:
	restore_physics()
	SonataPredictor.unregister(self)

# ── Physics isolation ─────────────────────────────────────────────────────────
func isolate_physics() -> void:
	body.gravity_scale = 0.0
	body.linear_damp   = 0.0
	body.angular_damp  = 0.0

func restore_physics() -> void:
	body.gravity_scale = orig_gravity_scale
	body.linear_damp   = orig_linear_damp
	body.angular_damp  = orig_angular_damp

# ── State machine transition ──────────────────────────────────────────────────
func _set_state(new_state: State) -> void:
	if _state == new_state:
		return
	var old_name : String = State.keys()[_state]
	var new_name : String = State.keys()[new_state]
	_state = new_state

	match new_state:
		State.MLFLIGHT:
			isolate_physics()
		State.GODOT_CONTACT:
			restore_physics()
		State.GODOT_WARMUP:
			restore_physics()
			ctx_buffer.clear()
			debug_frame_count = 0

	var extra := ""
	if old_name == "MLFLIGHT" and new_name == "GODOT_CONTACT":
		extra = "  lvy=%.3f" % body.linear_velocity.y
	if old_name == "GODOT_CONTACT" and new_name == "GODOT_WARMUP":
		extra = "  dur=%d frames" % _contact_dur
	_log("STATE %s → %s%s" % [old_name, new_name, extra])

# ── ml_enabled toggle ─────────────────────────────────────────────────────────
func set_ml_enabled(value: bool) -> void:
	ml_enabled = value
	if ml_enabled:
		isolate_physics()
		ctx_buffer.clear()
	else:
		restore_physics()
	_log("ml_enabled = %s" % str(value))

# ── Physics property change notification ─────────────────────────────────────
# Call this from objbase.gd whenever mass, gravity_scale, linear_damp,
# or angular_damp is changed at runtime via UI or script.
func on_physics_property_changed() -> void:
	# GS-FIX: read the LIVE body value — this is called BEFORE isolate_physics
	# zeros it, so body.gravity_scale is still the real intended value here.
	orig_gravity_scale = body.gravity_scale
	orig_linear_damp   = body.linear_damp
	orig_angular_damp  = body.angular_damp

	# GS-FIX: sync the poll tracker so the per-frame guard doesn't
	# double-fire on the same change.
	_last_polled_gs = orig_gravity_scale   # GS-FIX

	staticnorm        = build_static_norm()
	ctx_buffer.clear()
	debug_frame_count = 0

	# Transition through GODOT_WARMUP to collect 10 fresh frames under new gs.
	# _set_state handles restore_physics() → ctx_buffer.clear() internally.
	_set_state(State.GODOT_WARMUP)

	_log("on_physics_property_changed  gs=%.4f  ld=%.4f  ad=%.4f  staticnorm rebuilt  ctx cleared" % [
		orig_gravity_scale, orig_linear_damp, orig_angular_damp])

# ── GS-FIX: per-frame gravity_scale poll (safety net) ────────────────────────
# Catches gs changes that arrive without an on_physics_property_changed() call.
# Reads orig_gravity_scale directly — during MLFLIGHT body.gravity_scale is 0.0
# (isolated), so we compare against the cached intended value instead.
#
# During GODOT_WARMUP and GODOT_CONTACT, body.gravity_scale is live and we can
# compare directly. The match block handles both cases cleanly.
func _poll_gs_change() -> void:                                         # GS-FIX
	# The real intended gs is always orig_gravity_scale.
	# If the body is NOT isolated we can also cross-check the live value.
	var intended_gs : float = orig_gravity_scale
	if _state != State.MLFLIGHT:
		# Body is live — update our cache from the actual body property.
		# This catches external writes to body.gravity_scale directly.
		intended_gs = body.gravity_scale

	if abs(intended_gs - _last_polled_gs) >= gs_change_threshold:
		_log("GS_POLL_CHANGE  %.4f → %.4f  triggering reset" % [
			_last_polled_gs, intended_gs])
		# Update caches first, then call the full reset handler.
		orig_gravity_scale = intended_gs
		_last_polled_gs    = intended_gs                                # GS-FIX
		staticnorm         = build_static_norm()
		ctx_buffer.clear()
		debug_frame_count  = 0
		_set_state(State.GODOT_WARMUP)

# ── Main physics loop ─────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not ml_enabled:
		return

	# GS-FIX: poll every frame as a safety net. Cheap — one float subtract.
	_poll_gs_change()   # GS-FIX

	var contacts : int = body.get_contact_count()

	match _state:
		State.GODOT_WARMUP:
			ctx_buffer.append(_build_frame())
			if ctx_buffer.size() > 10:
				ctx_buffer.pop_front()
			if ctx_buffer.size() >= 10:
				_set_state(State.MLFLIGHT)

		State.MLFLIGHT:
			if contacts > 0:
				_contact_dur = 0
				_set_state(State.GODOT_CONTACT)
				return
			ctx_buffer.append(_build_frame())
			if ctx_buffer.size() > 10:
				ctx_buffer.pop_front()

		State.GODOT_CONTACT:
			_contact_dur += 1
			if contacts == 0:
				_set_state(State.GODOT_WARMUP)

# ── Predictor interface ───────────────────────────────────────────────────────
func is_ready_for_inference() -> bool:
	return _state == State.MLFLIGHT

func get_context() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(10 * 31)
	for i in range(10):
		var frame : PackedFloat32Array = ctx_buffer[i]
		for j in range(31):
			result[i * 31 + j] = frame[j]
	return result

func apply_prediction(pred: PackedFloat32Array) -> void:
	var lx : float = pred[7]  * TSTD[7]  + TMEAN[7]
	var ly : float = pred[8]  * TSTD[8]  + TMEAN[8]
	var lz : float = pred[9]  * TSTD[9]  + TMEAN[9]
	var ax : float = pred[10] * TSTD[10] + TMEAN[10]
	var ay : float = pred[11] * TSTD[11] + TMEAN[11]
	var az : float = pred[12] * TSTD[12] + TMEAN[12]

	var newlv := Vector3(lx, ly, lz)
	var newav := Vector3(ax, ay, az)

	newlv = newlv.clamp(Vector3(-400.0, -400.0, -400.0), Vector3(400.0, 400.0, 400.0))
	newav = newav.clamp(Vector3(-50.0,  -50.0,  -50.0),  Vector3(50.0,  50.0,  50.0))

	newlv.x *= lv_lateral_decay
	newlv.z *= lv_lateral_decay
	newav   *= av_decay

	body.linear_velocity  = newlv
	body.angular_velocity = newav

	if debug_log and debug_frame_count < debug_frames:
		debug_frame_count += 1
		var pos := body.global_position
		var lva := body.linear_velocity
		# GS-FIX: log orig_gravity_scale (not body.gravity_scale which is 0.0 in MLFLIGHT)
		print("SONATA F%03d %s MLFLIGHT  pos %.3f,%.3f,%.3f  lvset %.4f,%.4f,%.4f  lvactual %.4f,%.4f,%.4f  avset %.4f,%.4f,%.4f  gs_orig %.4f  gs_live %.4f  contacts %d" % [
			debug_frame_count, body.name,
			pos.x, pos.y, pos.z,
			newlv.x, newlv.y, newlv.z,
			lva.x, lva.y, lva.z,
			ax, ay, az,
			orig_gravity_scale,    # GS-FIX: the real intended gs
			body.gravity_scale,    # GS-FIX: must always be 0.0 in MLFLIGHT
			body.get_contact_count()])
	elif debug_log and debug_frame_count == debug_frames:
		debug_frame_count += 1
		print("SONATA Logger done — %d frames captured" % debug_frames)
		print(get_debug_summary())

# ── Feature extraction ────────────────────────────────────────────────────────
func _build_frame() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(31)
	var dyn := extract_dynamic_norm()
	for i in range(11):
		result[i] = staticnorm[i]
	for i in range(20):
		result[11 + i] = dyn[i]
	return result

func build_static_norm() -> PackedFloat32Array:
	var phys_mat := body.physics_material_override
	var friction : float = phys_mat.friction if phys_mat else 0.5
	var bounce   : float = phys_mat.bounce   if phys_mat else 0.3
	var raw := PackedFloat32Array([
		body.mass,            # 0  mass
		orig_gravity_scale,   # 1  gravity_scale  — GS-FIX: always use cached value
		friction,             # 2  friction_applied
		bounce,               # 3  bounce_applied
		orig_linear_damp,     # 4  linear_damp
		orig_angular_damp,    # 5  angular_damp
		air_drag_coeff,       # 6  air_drag_coefficient
		float(env_state),     # 7  env_state_binary
		float(shape_type),    # 8  shape_type_int
		shape_dim_primary,    # 9  shape_dim_primary
		shape_dim_secondary   # 10 shape_dim_secondary
	])
	var result := PackedFloat32Array()
	result.resize(11)
	for i in range(11):
		var s : float = SSTD[i]
		result[i] = (raw[i] - SMEAN[i]) / (s if s > 1e-6 else 1.0)
	return result

func extract_dynamic_norm() -> PackedFloat32Array:
	var lv   := body.linear_velocity
	var av   := body.angular_velocity
	var pos  := body.global_position
	var quat := body.quaternion
	var m    := body.mass
	var gs   := orig_gravity_scale   # GS-FIX: always use cached — live is 0.0 in MLFLIGHT
	var y    := pos.y
	var speed  := lv.length()
	var ke     := 0.5 * m * lv.length_squared()
	var re     := 0.5 * approx_moi() * av.length_squared()
	var pe     := m * gs * 9.81 * y
	var total  := ke + re + pe
	var raw := PackedFloat32Array([
		pos.x,  pos.y,  pos.z,
		quat.w, quat.x, quat.y, quat.z,
		lv.x,   lv.y,   lv.z,
		av.x,   av.y,   av.z,
		speed, ke, re, pe, total,
		float(body.get_contact_count()),
		0.0
	])
	var result := PackedFloat32Array()
	result.resize(20)
	for i in range(20):
		var s : float = DSTD[i]
		result[i] = (raw[i] - DMEAN[i]) / (s if s > 1e-6 else 1.0)
	return result

func approx_moi() -> float:
	var m := body.mass
	var r := shape_dim_primary
	match shape_type:
		0: return 0.4  * m * r * r
		1: return m / 6.0 * r * r
		2: return 0.5  * m * r * r
		3: return 0.4  * m * r * r
		4: return m / 12.0 * shape_dim_primary * shape_dim_primary
		5: return m / 18.0 * shape_dim_primary * shape_dim_primary
	return m * 0.1

# ── Shape detection ───────────────────────────────────────────────────────────
func detect_shape() -> void:
	var cs : CollisionShape3D = null
	for child in body.get_children():
		if child is CollisionShape3D:
			cs = child as CollisionShape3D
			break
	if cs == null:
		push_warning("SonataBody: no CollisionShape3D found on " + body.name)
		return
	var s : Shape3D = cs.shape
	if s is SphereShape3D:
		shape_type = 0;  shape_dim_primary = (s as SphereShape3D).radius;  shape_dim_secondary = 0.0
	elif s is CylinderShape3D:
		shape_type = 2;  shape_dim_primary = (s as CylinderShape3D).radius;  shape_dim_secondary = (s as CylinderShape3D).height
	elif s is CapsuleShape3D:
		shape_type = 3;  shape_dim_primary = (s as CapsuleShape3D).radius;  shape_dim_secondary = (s as CapsuleShape3D).height
	elif s is ConvexPolygonShape3D:
		shape_type = 5;  shape_dim_primary = 1.0;  shape_dim_secondary = 1.0
	elif s is BoxShape3D:
		var b := s as BoxShape3D
		if b.size.z > b.size.x * 1.4:
			shape_type = 4;  shape_dim_primary = b.size.x;  shape_dim_secondary = b.size.z
		else:
			shape_type = 1;  shape_dim_primary = b.size.x;  shape_dim_secondary = 0.0
	else:
		shape_type = 1;  shape_dim_primary = 0.5;  shape_dim_secondary = 0.0

# ── Debug helper ──────────────────────────────────────────────────────────────
func get_debug_summary() -> Dictionary:
	return {
		"body":              body.name if body else "null",
		"state":             State.keys()[_state],
		"ml_enabled":        ml_enabled,
		"ctx_size":          ctx_buffer.size(),
		"orig_gs":           orig_gravity_scale,
		"last_polled_gs":    _last_polled_gs,      # GS-FIX: shows last confirmed gs
		"orig_ld":           orig_linear_damp,
		"live_gs":           body.gravity_scale if body else -1.0,
		"contacts":          body.get_contact_count() if body else 0,
		"lv":                body.linear_velocity if body else Vector3.ZERO,
		"shape_type":        shape_type,
		"shape_dim_primary": shape_dim_primary
	}

func _log(msg: String) -> void:
	print("SONATA %s  body=%s" % [msg, body.name if body else "?"])
	var logger := get_node_or_null("/root/SonataLogger")
	if logger:
		logger.log_event("sonata_body", {"msg": msg, "body": body.name if body else "?"})
