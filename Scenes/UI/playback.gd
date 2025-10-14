extends MarginContainer


@onready var playback_button: Button = $HBoxContainer/Playback_button
@onready var step_button: Button = $HBoxContainer/Step_button


const FIXED_DELTA := 1.0 / 60.0
var is_playing := true
var step_timer: Timer

func _ready() -> void:
	playback_button.text = "Pause"
	step_button.text = "Step"
	step_button.disabled = true
	
	step_timer = Timer.new()
	step_timer.wait_time = FIXED_DELTA
	step_timer.one_shot = true
	step_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(step_timer)
	step_timer.timeout.connect(_on_step_timeout)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_playback_button_pressed() -> void:
	is_playing = !is_playing
	
	if is_playing:
		get_tree().paused = false
		playback_button.text = "Pause"
		step_button.disabled = true
	else:
		get_tree().paused = true
		playback_button.text = "Play"
		step_button.disabled = false


func _on_step_button_pressed() -> void:
	print("step")
	if get_tree().paused:
		# Unpause for one physics frame
		get_tree().paused = false
		step_timer.start()

	
func _on_step_timeout() -> void:
	get_tree().paused = true
