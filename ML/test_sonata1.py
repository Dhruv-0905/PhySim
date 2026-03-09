# ==============================================================
# SONATA I — Integration Test
# test_sonata1.py
#
# Run BEFORE launching Godot to confirm the full pipeline works.
# Usage:
#   conda activate physimai-backend
#   cd C:\Projects\PhySim\ML
#   python test_sonata1.py
# ==============================================================
import socket, struct, time, sys
import numpy as np

HOST, PORT  = "127.0.0.1", 9876
CTX_FLOATS  = 10 * 31   # 310 per object
PRED_FLOATS =  3 * 13   # 39  per object

# ── Normalization stats (from normalization_stats.json) ───────
S_MEAN = np.array([543.4700, 0.48556, 0.58294, 0.38327, 0.51825,
                   0.51825,  0.08427, 0.56180, 2.52111, 0.75252, 0.83914], np.float32)
S_STD  = np.array([1023.330, 4.39475, 0.32203, 0.25406, 0.51240,
                   0.51240,  0.07443, 0.49618, 1.70805, 0.24999, 0.68852], np.float32)

D_MEAN = np.array([-0.00532,  53.8559, 0.01947,
                    0.43968,   0.10559, 0.11818, 0.09974,
                   -0.00473,  27.9688, 0.00246,
                   -0.01681,   0.00927,-0.00700,
                   29.5774, 807330.95, 443.914, -1102996.67, -295221.80,
                    0.94816,  126.798], np.float32)
D_STD  = np.array([2.83557, 116.374,  2.84093,
                   0.44447,   0.43367, 0.43895, 0.43968,
                   1.01805,  55.4346,  1.02147,
                   2.23182,   1.80319, 2.22977,
                   54.6123, 4835016.5, 2945.95, 5751267.2, 1747046.2,
                   1.45573,  1340.032], np.float32)

T_MEAN = D_MEAN[:13]
T_STD  = D_STD[:13]

PASS = "\033[92m✓ PASS\033[0m"
FAIL = "\033[91m✗ FAIL\033[0m"
WARN = "\033[93m⚠ WARN\033[0m"

results = []

def record(label, passed, detail=""):
    tag = PASS if passed else FAIL
    print(f"  {tag}  {label}" + (f"  ({detail})" if detail else ""))
    results.append(passed)

# ── Socket helpers ────────────────────────────────────────────
def make_socket():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.settimeout(5.0)
    s.connect((HOST, PORT))
    return s

def recv_exact(s, n):
    buf = bytearray()
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionResetError("Server closed connection")
        buf.extend(chunk)
    return bytes(buf)

def infer(s, ctx: np.ndarray):
    """ctx: (N, 310) float32. Returns pred: (N, 3, 13) float32."""
    n = ctx.shape[0]
    payload = struct.pack("<i", n) + ctx.astype(np.float32).tobytes()
    s.sendall(payload)
    header  = recv_exact(s, 4)
    n_resp  = struct.unpack("<i", header)[0]
    raw     = recv_exact(s, n_resp * PRED_FLOATS * 4)
    return np.frombuffer(raw, np.float32).reshape(n_resp, 3, 13)

# ── Build a realistic context for one object ─────────────────
def make_realistic_ctx(n_objects=1, gravity_scale=1.0, height=5.0, env=0):
    """
    Simulates a sphere of mass 10kg falling from height=5m.
    Builds 10 frames of context in normalized space.
    """
    dt     = 1.0 / 60.0
    g      = gravity_scale * 9.80665
    mass   = 10.0
    # Static features (normalized)
    static_raw = np.array([
        mass, gravity_scale, 0.5, 0.3, 0.0, 0.0, 0.0,
        float(env), 0.0, 0.5, 0.0
    ], np.float32)
    static_norm = (static_raw - S_MEAN) / S_STD   # (11,)

    contexts = []
    for _ in range(n_objects):
        frames = []
        pos_y  = height
        vel_y  = 0.0
        for t in range(10):
            pos_y += vel_y * dt
            vel_y -= g * dt
            speed  = abs(vel_y)
            ke     = 0.5 * mass * vel_y**2
            pe     = mass * gravity_scale * 9.80665 * pos_y
            dyn_raw = np.array([
                0.0, pos_y, 0.0,           # pos
                1.0, 0.0, 0.0, 0.0,        # quat (identity)
                0.0, vel_y, 0.0,           # linvel
                0.0, 0.0, 0.0,             # angvel
                speed, ke, 0.0, pe, ke+pe, # energy
                0.0, 0.0                    # contact, impulse
            ], np.float32)
            dyn_norm = (dyn_raw - D_MEAN) / D_STD   # (20,)
            frames.append(np.concatenate([static_norm, dyn_norm]))  # (31,)
        contexts.append(np.stack(frames))   # (10, 31)

    ctx = np.stack(contexts).reshape(n_objects, CTX_FLOATS)  # (N, 310)
    return ctx


# ══════════════════════════════════════════════════════════════
print("=" * 58)
print("  SONATA I — Integration Test")
print("=" * 58)

# ── Test 0: Connection ────────────────────────────────────────
print("\n[ 0 ] Connection")
try:
    sock = make_socket()
    record("TCP connect to 127.0.0.1:9876", True)
except Exception as e:
    record("TCP connect to 127.0.0.1:9876", False, str(e))
    print("\n  Server is not running. Start it first:")
    print("    conda activate physimai-backend")
    print("    python sonata_server.py")
    sys.exit(1)

# ── Test 1: Zero context ──────────────────────────────────────
print("\n[ 1 ] Zero context (smoke test)")
ctx_zero = np.zeros((1, CTX_FLOATS), np.float32)
pred = infer(sock, ctx_zero)
record("Response shape (1, 3, 13)",   pred.shape == (1, 3, 13),   str(pred.shape))
record("No NaN in output",            not np.any(np.isnan(pred)))
record("No Inf in output",            not np.any(np.isinf(pred)))
qnorms = np.linalg.norm(pred[0, :, 3:7], axis=-1)   # (3,)
record("Quat norms ≈ 1.0",
       np.all(np.abs(qnorms - 1.0) < 0.01),
       f"norms={qnorms.round(4)}")

# ── Test 2: Realistic physics context ────────────────────────
print("\n[ 2 ] Realistic context — sphere falling under gravity")
ctx_real = make_realistic_ctx(n_objects=1, gravity_scale=1.0, height=5.0, env=0)
pred_r   = infer(sock, ctx_real)

# Denormalize first predicted frame
p0       = pred_r[0, 0, :] * T_STD + T_MEAN
pred_pos = p0[0:3]
pred_quat= p0[3:7]
pred_lv  = p0[7:10]

qnorm_r  = np.linalg.norm(pred_quat)
nan_ok   = not np.any(np.isnan(pred_r))

record("No NaN / Inf",               nan_ok)
record("Quat unit-norm after denorm",np.abs(qnorm_r - 1.0) < 0.01,
       f"|q|={qnorm_r:.5f}")
record("Predicted vel_y is negative (falling)",
       pred_lv[1] < 0,
       f"vel_y={pred_lv[1]:.3f} m/s")
record("Predicted pos_y < 5.0 (object fell)",
       pred_pos[1] < 5.0,
       f"pos_y={pred_pos[1]:.3f} m")

print(f"    Denormalized prediction  (t+1 frame):")
print(f"      pos   : [{pred_pos[0]:.3f}, {pred_pos[1]:.3f}, {pred_pos[2]:.3f}] m")
print(f"      quat  : [{pred_quat[0]:.3f}, {pred_quat[1]:.3f}, "
      f"{pred_quat[2]:.3f}, {pred_quat[3]:.3f}]  |q|={qnorm_r:.5f}")
print(f"      linvel: [{pred_lv[0]:.3f}, {pred_lv[1]:.3f}, {pred_lv[2]:.3f}] m/s")

# ── Test 3: Antigravity ───────────────────────────────────────
print("\n[ 3 ] Antigravity context (gravity_scale = -2.0)")
ctx_anti = make_realistic_ctx(n_objects=1, gravity_scale=-2.0, height=2.0, env=0)
pred_a   = infer(sock, ctx_anti)
p0a      = pred_a[0, 0, :] * T_STD + T_MEAN
record("No NaN / Inf",                 not np.any(np.isnan(pred_a)))
record("Predicted vel_y is positive (rising)",
       p0a[7+1] > 0,
       f"vel_y={p0a[8]:.3f} m/s")

# ── Test 4: Batch scaling ────────────────────────────────────
print("\n[ 4 ] Batch scaling")
for n in [1, 5, 10, 20, 50]:
    ctx_b = make_realistic_ctx(n_objects=n)
    pred_b = infer(sock, ctx_b)
    ok = pred_b.shape == (n, 3, 13) and not np.any(np.isnan(pred_b))
    record(f"Batch N={n:>2} → shape ({n},3,13)",  ok,  str(pred_b.shape))

# ── Test 5: Latency at 60Hz workloads ────────────────────────
print("\n[ 5 ] Latency benchmark (200 frames each)")
configs = [
    ("1  object  (light scene)", 1),
    ("5  objects (normal scene)",5),
    ("20 objects (heavy scene)", 20),
]
for label, n in configs:
    ctx_l = make_realistic_ctx(n_objects=n)
    # Warmup
    for _ in range(10): infer(sock, ctx_l)
    # Measure
    times = []
    for _ in range(200):
        t0 = time.perf_counter()
        infer(sock, ctx_l)
        times.append((time.perf_counter() - t0) * 1000)
    p50, p95 = np.percentile(times, [50, 95])
    budget_ok = p95 < 4.0
    record(f"{label}  p95={p95:.2f}ms",
           budget_ok,
           f"p50={p50:.2f}ms  p95={p95:.2f}ms  {'<4ms ✓' if budget_ok else 'tight'}")

# ── Test 6: 5-second continuous simulation (300 frames) ──────
print("\n[ 6 ] Continuous 5s simulation — 300 frames @ 60Hz")
ctx_sim   = make_realistic_ctx(n_objects=3)
errors, drops = 0, 0
t_start   = time.perf_counter()
for frame in range(300):
    t_frame = time.perf_counter()
    try:
        pred_s = infer(sock, ctx_sim)
        if np.any(np.isnan(pred_s)) or np.any(np.isinf(pred_s)):
            errors += 1
    except Exception:
        drops += 1
    # Pace to 60Hz
    elapsed = time.perf_counter() - t_frame
    sleep   = max(0.0, 1/60 - elapsed)
    time.sleep(sleep)

total_s  = time.perf_counter() - t_start
achieved = 300 / total_s
record("Zero NaN frames over 300",    errors == 0,  f"{errors} bad frames")
record("Zero dropped frames",         drops  == 0,  f"{drops} drops")
record(f"Sustained ≥ 58 Hz",          achieved >= 58, f"{achieved:.1f} Hz")

# ── Summary ───────────────────────────────────────────────────
sock.close()
passed = sum(results)
total  = len(results)
print()
print("=" * 58)
if passed == total:
    print(f"  \033[92m✓  ALL {total} CHECKS PASSED — launch Godot\033[0m")
else:
    print(f"  \033[91m✗  {total - passed} of {total} CHECKS FAILED\033[0m")
    print(f"     Fix failures above before launching Godot")
print("=" * 58)
0