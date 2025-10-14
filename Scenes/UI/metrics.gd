extends MarginContainer

@onready var metrics_label: Label = $metrics_label

var fps: float
var physics_time: float
var idle_time: float
var vram: float
var object_count: int
var static_mem: float

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	fps = Engine.get_frames_per_second()
	physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	idle_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	vram = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	static_mem = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	
	update_metrics()
	

func update_metrics() -> void:
	metrics_label.text = """
	FPS: %.2f
	Physics Time: %.2f ms
	Idle Time: %.2f ms
	VRAM: %.2f MB
	Memory: %.2f MB
	""" % [fps, physics_time, idle_time, vram, static_mem]
