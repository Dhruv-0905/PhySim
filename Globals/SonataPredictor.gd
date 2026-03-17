# ==============================================================
# SONATA I — Module 6: Godot Inference Client
# SonataPredictor.gd  →  Add as Autoload singleton
# ==============================================================
extends Node

const HOST                := "127.0.0.1"
const PORT                := 9876
const CTX_FLOATS          := 10 * 31
const PRED_FLOATS         := 3  * 13
const CONNECT_TIMEOUT_MS  := 5000
const HUD_UPDATE_INTERVAL := 10   # frames between HUD refreshes

var _peer      : StreamPeerTCP = null
var _bodies    : Array         = []
var _connected := false   # FIX: was incorrectly initialized to true

# ── Telemetry state ───────────────────────────────────────────
var _frame_count       := 0
var _last_batch_ms     := 0.0
var _total_inferences  := 0
var _failed_frames     := 0
var _bodies_this_frame := 0

# ── HUD ───────────────────────────────────────────────────────
var _hud : Label = null


# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	set_physics_process(false)
	_build_hud()
	_log("SonataPredictor init — connecting to %s:%d" % [HOST, PORT])

	# Print log file location to Output immediately
	var log_dir  := OS.get_user_data_dir()
	print("SonataPredictor: user:// maps to → ", log_dir)
	print("SonataPredictor: log files written to → ", log_dir)

	call_deferred("_connect_to_server")


func _connect_to_server() -> void:
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(HOST, PORT)
	if err != OK:
		_log("ERROR: cannot initiate TCP connect (err=%d) — is sonata_server.py running?" % err)
		_set_hud_status("OFFLINE", Color.RED)
		return

	_set_hud_status("CONNECTING…", Color.YELLOW)
	var t0 := Time.get_ticks_msec()
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.poll()
		if Time.get_ticks_msec() - t0 > CONNECT_TIMEOUT_MS:
			_log("ERROR: connection timeout — server did not respond in %d ms" % CONNECT_TIMEOUT_MS)
			_set_hud_status("TIMEOUT", Color.RED)
			return
		OS.delay_msec(5)

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_log("ERROR: failed to connect to %s:%d" % [HOST, PORT])
		_set_hud_status("FAILED", Color.RED)
		return

	_peer.set_no_delay(true)
	_connected = true
	set_physics_process(true)
	_log("connected to inference server at %s:%d" % [HOST, PORT])
	_set_hud_status("ACTIVE", Color.GREEN)
	print("SonataPredictor: connected to inference server ✓")


# ── HUD construction ──────────────────────────────────────────
func _build_hud() -> void:
	_hud = Label.new()
	_hud.name            = "SonataPredictorHUD"
	_hud.position        = Vector2(8, 8)
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color",          Color.WHITE)
	_hud.add_theme_color_override("font_shadow_color",   Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x",  1)
	_hud.add_theme_constant_override("shadow_offset_y",  1)
	_hud.z_index = 100
	get_tree().get_root().call_deferred("add_child", _hud)
	_refresh_hud("OFFLINE")


func _set_hud_status(status: String, color: Color) -> void:
	if _hud:
		_hud.add_theme_color_override("font_color", color)
	_refresh_hud(status)


func _refresh_hud(status: String = "") -> void:
	if not _hud:
		return
	var s := status if status != "" else ("ACTIVE" if _connected else "OFFLINE")
	_hud.text = (
		"[SONATA I Predictor]\n"
		+ "Status   : %s\n" % s
		+ "Bodies   : %d registered / %d ready\n" % [_bodies.size(), _bodies_this_frame]
		+ "Infer    : #%d  last=%.2f ms\n" % [_total_inferences, _last_batch_ms]
		+ "Failures : %d dropped frames" % _failed_frames
	)


# ── Registration ──────────────────────────────────────────────
func register(body: Node) -> void:
	if body not in _bodies:
		_bodies.append(body)
		_log("body registered: %s  (total=%d)" % [body.name, _bodies.size()])

func unregister(body: Node) -> void:
	_bodies.erase(body)
	_log("body unregistered: %s  (total=%d)" % [body.name, _bodies.size()])


# ── Main physics loop ─────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not _connected or _bodies.is_empty():
		return

	_frame_count += 1

	# ── 1. Collect ready bodies ──
	var ready_bodies : Array = []
	for body in _bodies:
		if body.is_ready_for_inference():
			ready_bodies.append(body)

	_bodies_this_frame = ready_bodies.size()

	if _frame_count % HUD_UPDATE_INTERVAL == 0:
		_refresh_hud()

	if ready_bodies.is_empty():
		return

	var n := ready_bodies.size()

	# ── 2. Build batched context ──
	var ctx_buf := PackedFloat32Array()
	ctx_buf.resize(n * CTX_FLOATS)
	for i in range(n):
		var body_ctx : PackedFloat32Array = ready_bodies[i].get_context()
		for j in range(CTX_FLOATS):
			ctx_buf[i * CTX_FLOATS + j] = body_ctx[j]

	# ── 3. Send ──
	var t_send := Time.get_ticks_usec()
	var request := PackedByteArray()
	request.resize(4 + n * CTX_FLOATS * 4)
	request.encode_s32(0, n)
	var raw_ctx := ctx_buf.to_byte_array()
	for i in range(raw_ctx.size()):
		request[4 + i] = raw_ctx[i]
	_peer.put_data(request)

	# ── 4. Receive ──
	var response_size := 4 + n * PRED_FLOATS * 4
	var resp_bytes    := _recv_exact(response_size)
	if resp_bytes.is_empty():
		_failed_frames += 1
		_log("WARNING: recv timeout on frame %d — bodies=%d" % [_frame_count, n])
		return

	var elapsed_ms := (Time.get_ticks_usec() - t_send) / 1000.0
	_last_batch_ms  = elapsed_ms
	_total_inferences += 1

	# Log every 300 frames (~5s) as a heartbeat
	if _total_inferences % 300 == 0:
		_log("heartbeat  frame=%d  bodies=%d  latency=%.2fms  failures=%d"
			% [_frame_count, n, _last_batch_ms, _failed_frames])

	var n_resp := resp_bytes.decode_s32(0)
	if n_resp != n:
		push_warning("SonataPredictor: expected %d predictions, got %d" % [n, n_resp])
		return

	var pred_buf := resp_bytes.slice(4).to_float32_array()

	# ── 5. Distribute ──
	for i in range(n):
		var pred_i := pred_buf.slice(i * PRED_FLOATS, (i + 1) * PRED_FLOATS)
		ready_bodies[i].apply_prediction(pred_i)


# ── Reliable receive ──────────────────────────────────────────
func _recv_exact(n_bytes: int) -> PackedByteArray:
	var buf      := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 50

	while buf.size() < n_bytes:
		_peer.poll()
		var available := _peer.get_available_bytes()
		if available > 0:
			var chunk_size : int = min(available, n_bytes - buf.size())
			var result     := _peer.get_data(chunk_size)
			if result[0] == OK:
				buf.append_array(result[1])
		elif Time.get_ticks_msec() > deadline:
			push_error("SonataPredictor: receive timeout (%d/%d bytes)" % [buf.size(), n_bytes])
			return PackedByteArray()

	return buf


# ── Internal logger (routes through SonataLogger if present) ──
func _log(msg: String) -> void:
	var full := "SonataPredictor: " + msg
	print(full)
	if Engine.has_singleton("SonataLogger") or get_node_or_null("/root/SonataLogger") != null:
		SonataLogger.log_event("predictor", {msg = msg, frame = _frame_count})


# ── Cleanup ───────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _peer != null:
		_peer.disconnect_from_host()
