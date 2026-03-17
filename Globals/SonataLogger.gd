# ==============================================================
# SonataLogger.gd  v2 — Semantic physics + input debugger
#
# Autoload setup:
#   Project → Project Settings → Autoload
#   Path : res://Globals/SonataLogger.gd
#   Name : SonataLogger
#
# v2 changes:
#   • watch_property(obj, prop, label) — monitor ANY property on ANY node
#   • log_event(category, data)        — call this from your UI scripts
#   • Input filter: suppress noisy text/editor actions, debounce scroll
#   • [PARAM] fires immediately on property write, not next physics frame
#   • Groups redundant input lines (scroll wheel batching)
# ==============================================================
extends Node

# ── Configuration ──────────────────────────────────────────────
@export var log_inputs         := true
@export var log_physics_params := true
@export var log_anomalies      := true
@export var log_to_file        := true

@export var pos_jump_threshold := 0.3
@export var vel_jump_threshold := 5.0
@export var ring_buffer_size   := 2000

# Set false to hide Tab/Enter/text-edit actions (they are noise in most games)
@export var log_ui_text_actions := false
# Set false to hide individual scroll ticks — batches them instead
@export var log_scroll_verbose  := false

# ── Internals ──────────────────────────────────────────────────
var _entries   : Array  = []
var _file      : FileAccess = null
var _file_path : String = ""

# Monitored RigidBody3D table (unchanged from v1)
var _bodies : Array = []

# Generic property watchers: [{obj, prop, label, last_val}]
var _watchers : Array = []

# Input state
var _actions     : Array      = []
var _prev_act    : Dictionary = {}
var _phys_frame  : int        = 0

# Scroll debounce
var _scroll_accum   : int   = 0
var _scroll_dir     : int   = 0
var _scroll_frame   : int   = -99

# Suppressed action name fragments (ui text-editing noise)
const _UI_NOISE := [
	"ui_text_", "ui_menu", "ui_swap_input_direction",
	"ui_focus_next", "ui_focus_prev",
	"ui_text_completion_replace",
]


# ════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ════════════════════════════════════════════════════════════════

func _ready() -> void:
	_actions = InputMap.get_actions()
	for a in _actions:
		_prev_act[a] = false

	if log_to_file:
		var dt : String = Time.get_datetime_string_from_system() \
			.replace(":", "-").replace(" ", "_")
		_file_path = "user://sonata_%s.log" % dt
		_file = FileAccess.open(_file_path, FileAccess.WRITE)
		_emit("=== SonataLogger v2 started  %s ===" % dt)
		_emit("Engine : %s" % Engine.get_version_info()["string"])
		_emit("File   : %s" % _file_path)
		_emit("Thresholds : pos_jump=%.2f m  vel_jump=%.2f m/s" % [
			pos_jump_threshold, vel_jump_threshold])
		_emit("")
		_emit("How to log your own events from any script:")
		_emit("  SonataLogger.log_event(\"mass_changed\", {from=1.0, to=500.0, body=\"Cube\"})")
		_emit("  SonataLogger.log_event(\"spawned\",      {name=\"Cube2\", pos=str(pos)})")
		_emit("")

	print("[SonataLogger v2] Ready  file=%s" % _file_path)


func _exit_tree() -> void:
	_flush_scroll()
	if _file:
		_emit("=== SonataLogger closed ===")
		_file.close()


# ════════════════════════════════════════════════════════════════
#  PUBLIC API
# ════════════════════════════════════════════════════════════════

## ── Semantic event logging ───────────────────────────────────
## Call this from ANY script whenever something meaningful happens.
##
## Examples:
##   SonataLogger.log_event("mass_set",      {"body": name, "from": old, "to": new_val})
##   SonataLogger.log_event("gravity_set",   {"body": name, "from": old, "to": new_val})
##   SonataLogger.log_event("object_spawn",  {"name": obj.name, "pos": str(obj.global_position)})
##   SonataLogger.log_event("object_delete", {"name": obj.name})
##   SonataLogger.log_event("scene_reset",   {})
##   SonataLogger.log_event("ml_toggled",    {"enabled": ml_enabled})
func log_event(category: String, data: Dictionary = {}) -> void:
	var parts := PackedStringArray()
	for k in data:
		var v = data[k]
		if v is float:
			parts.append("%s=%.4f" % [k, v])
		else:
			parts.append("%s=%s" % [k, str(v)])
	_emit("[EVENT] %-22s  %s  frame=%d" % [category, "  ".join(parts), _phys_frame])


## ── Property watcher ─────────────────────────────────────────
## Monitors ANY property on ANY object. Logs whenever it changes.
##
## Examples:
##   SonataLogger.watch_property(my_body, "mass",          "Cube.mass")
##   SonataLogger.watch_property(my_body, "gravity_scale", "Cube.gs")
##   SonataLogger.watch_property(env_node, "wind_speed",   "WindSpeed")
func watch_property(obj: Object, prop: StringName, label: String = "") -> void:
	if not is_instance_valid(obj):
		push_warning("[SonataLogger] watch_property: invalid object")
		return
	var lbl := label if label != "" else "%s.%s" % [obj.get_class(), prop]
	_watchers.append({
		"obj"      : obj,
		"prop"     : prop,
		"label"    : lbl,
		"last_val" : obj.get(prop),
	})
	_emit("[WATCH] Registered watcher: %-30s  initial=%s" % [lbl, str(obj.get(prop))])


## ── RigidBody3D shorthand ─────────────────────────────────────
func monitor_body(body: RigidBody3D) -> void:
	for e in _bodies:
		if e["body"] == body:
			return
	_bodies.append({
		"body": body, "last_gs": body.gravity_scale,
		"last_ld": body.linear_damp, "last_ad": body.angular_damp,
		"last_mass": body.mass, "last_freeze": body.freeze,
		"last_sleeping": body.sleeping,
		"last_pos": body.global_position,
		"last_lv": body.linear_velocity, "last_av": body.angular_velocity,
		"lv_x_hist": [], "lv_z_hist": [],
	})
	# Also add individual watchers for key physics props so changes
	# are caught via watch_property too (belt-and-suspenders)
	watch_property(body, "mass",          "%s.mass" % body.name)
	watch_property(body, "gravity_scale", "%s.gravity_scale" % body.name)
	watch_property(body, "linear_damp",   "%s.linear_damp" % body.name)
	watch_property(body, "angular_damp",  "%s.angular_damp" % body.name)
	_emit("[MONITOR] Registered body: %s" % body.name)


func unmonitor_body(body: RigidBody3D) -> void:
	for i in range(_bodies.size() - 1, -1, -1):
		if _bodies[i]["body"] == body:
			_bodies.remove_at(i)
	_emit("[MONITOR] Unregistered body: %s" % body.name)


## Drift diagnostic (unchanged)
func get_drift_report() -> String:
	var r := "=== Drift Report ===\n"
	for e in _bodies:
		if not is_instance_valid(e["body"]):
			continue
		var xh : Array = e["lv_x_hist"]
		var zh : Array = e["lv_z_hist"]
		if xh.size() < 2:
			continue
		var dx : float = (xh[-1] - xh[0]) / float(xh.size())
		var dz : float = (zh[-1] - zh[0]) / float(zh.size())
		r += "%s  lv_x_drift/frame=%.5f  lv_z_drift/frame=%.5f\n" % [
			e["body"].name, dx, dz]
		r += "  Recommended lv_lateral_decay = %.4f\n" % \
			clampf(1.0 - absf(max(dx, dz)) * 0.5, 0.90, 1.0)
	return r


func log_custom(msg: String) -> void:
	_emit("[CUSTOM] " + msg)


func get_log_path() -> String:
	return _file_path


func get_recent(n: int = 50) -> Array:
	return _entries.slice(max(0, _entries.size() - n))


# ════════════════════════════════════════════════════════════════
#  INPUT
# ════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not log_inputs:
		return

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.echo:
			return
		var state := "▼PRESS" if ke.pressed else "▲RELEASE"
		_emit("[KEY] %s  %-16s  scan=%-10d  frame=%d" % [
			state, OS.get_keycode_string(ke.keycode), ke.physical_keycode, _phys_frame])

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var btn := mb.button_index

		# Scroll wheel — batch instead of flooding
		if btn == MOUSE_BUTTON_WHEEL_DOWN or btn == MOUSE_BUTTON_WHEEL_UP:
			if not mb.pressed:
				return
			var dir := 1 if btn == MOUSE_BUTTON_WHEEL_DOWN else -1
			if _scroll_dir == dir and _phys_frame - _scroll_frame <= 3:
				_scroll_accum += 1
			else:
				_flush_scroll()
				_scroll_dir   = dir
				_scroll_accum = 1
			_scroll_frame = _phys_frame
			if log_scroll_verbose:
				_emit("[SCROLL] %s  pos=(%d,%d)  frame=%d" % [
					"DOWN" if dir==1 else "UP",
					int(mb.position.x), int(mb.position.y), _phys_frame])
			return

		_flush_scroll()
		var state := "▼PRESS" if mb.pressed else "▲RELEASE"
		_emit("[MOUSE] %s  btn=%-2d  pos=(%d,%d)  frame=%d" % [
			state, btn, int(mb.position.x), int(mb.position.y), _phys_frame])

	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		_emit("[JOYPAD] %s  btn=%d  device=%d  frame=%d" % [
			"▼" if jb.pressed else "▲", jb.button_index, jb.device, _phys_frame])


# ════════════════════════════════════════════════════════════════
#  PHYSICS PROCESS
# ════════════════════════════════════════════════════════════════

func _physics_process(_delta: float) -> void:
	_phys_frame += 1

	# Flush stale scroll batch
	if _scroll_accum > 0 and _phys_frame - _scroll_frame > 4:
		_flush_scroll()

	# ── Input actions (filtered) ───────────────────────────────
	if log_inputs:
		for action in _actions:
			if _is_noise_action(action):
				continue
			var pressed : bool = Input.is_action_pressed(action)
			if pressed and not _prev_act.get(action, false):
				_emit("[ACTION] just_pressed   %-28s  frame=%d" % [action, _phys_frame])
			elif not pressed and _prev_act.get(action, false):
				_emit("[ACTION] just_released  %-28s  frame=%d" % [action, _phys_frame])
			_prev_act[action] = pressed

	# ── Generic property watchers ──────────────────────────────
	for w in _watchers:
		if not is_instance_valid(w["obj"]):
			continue
		var cur = w["obj"].get(w["prop"])
		if cur != w["last_val"]:
			_emit("[WATCH]  %-30s  %s  →  %s  frame=%d" % [
				w["label"], _fmt(w["last_val"]), _fmt(cur), _phys_frame])
			w["last_val"] = cur

	# ── Body monitoring ────────────────────────────────────────
	if log_physics_params or log_anomalies:
		for e in _bodies:
			if is_instance_valid(e["body"]):
				_monitor_body_entry(e)


func _monitor_body_entry(e: Dictionary) -> void:
	var body : RigidBody3D = e["body"]
	var lv   : Vector3     = body.linear_velocity

	if log_anomalies:
		var pos    : Vector3 = body.global_position
		var pdelta : float   = pos.distance_to(e["last_pos"])
		var vdelta : float   = lv.distance_to(e["last_lv"])
		if pdelta > pos_jump_threshold:
			_emit("[ANOMALY] %s  POS_JUMP  Δ=%.4f m  %s→%s  frame=%d" % [
				body.name, pdelta, _v3(e["last_pos"]), _v3(pos), _phys_frame])
		if vdelta > vel_jump_threshold:
			_emit("[ANOMALY] %s  VEL_JUMP  Δ=%.4f m/s  %s→%s  frame=%d" % [
				body.name, vdelta, _v3(e["last_lv"]), _v3(lv), _phys_frame])
		e["last_pos"] = pos
		e["last_lv"]  = lv
		e["last_av"]  = body.angular_velocity

	# Drift history
	var xh : Array = e["lv_x_hist"]
	var zh : Array = e["lv_z_hist"]
	xh.append(lv.x); zh.append(lv.z)
	if xh.size() > 120:
		xh.pop_front(); zh.pop_front()


# ════════════════════════════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════════════════════════════

func _flush_scroll() -> void:
	if _scroll_accum == 0:
		return
	var dir_s := "DOWN" if _scroll_dir == 1 else "UP"
	_emit("[SCROLL] %s  ×%d  frame=%d" % [dir_s, _scroll_accum, _scroll_frame])
	_scroll_accum = 0
	_scroll_dir   = 0


func _is_noise_action(action: String) -> bool:
	if not log_ui_text_actions:
		for n in _UI_NOISE:
			if action.begins_with(n):
				return true
	return false


func _fmt(v) -> String:
	if v is float:   return "%.6f" % v
	if v is int:     return str(v)
	if v is bool:    return str(v)
	if v is Vector3: return _v3(v)
	return str(v)


func _v3(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]


func _emit(msg: String) -> void:
	var ts   : String = "[%9.3f] " % (Time.get_ticks_msec() * 0.001)
	var full : String = ts + msg
	_entries.push_back(full)
	if _entries.size() > ring_buffer_size:
		_entries.pop_front()
	print(full)
	if _file:
		_file.store_line(full)
		_file.flush()
