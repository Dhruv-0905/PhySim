extends Camera3D
@onready var ray_cast_3d: RayCast3D = $RayCast3D

var physics_property

var orbit_sensitivity := 0.005
var pan_sensitivity := 0.01
var zoom_sensitivity := 1.0

var pitch := 0.0
var yaw := 0.0
var distance := 10.0
var target_position := Vector3.ZERO  # The point to orbit around

func _ready():
	physics_property = get_tree().get_first_node_in_group("Physics_property") #not the cleanest way of doing it, but it works
	pitch = deg_to_rad(20)  # tilt down a bit
	distance = 10
	target_position = Vector3.ZERO
	_update_camera_position()

func _process(delta: float) -> void:
	var mouse_position: Vector2 =get_viewport().get_mouse_position()
	ray_cast_3d.target_position = project_local_ray_normal(mouse_position) * 100
	ray_cast_3d.force_raycast_update()
	select_object_click()

func select_object_click():
	var nodes = get_tree().get_nodes_in_group("obj")
	if ray_cast_3d.is_colliding():
		var collider = ray_cast_3d.get_collider()
		if collider.is_in_group("obj"):
			var index = nodes.find(collider)
			if Input.is_action_just_pressed("Click"):
				physics_property.set_selected_object(collider)
				SignalManager.on_camera_obj_selected(index)

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if Input.is_key_pressed(KEY_SHIFT):
			_pan(event.relative)
		elif not Input.is_key_pressed(KEY_CTRL):
			_orbit(event.relative)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(-zoom_sensitivity)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(zoom_sensitivity)

func _orbit(relative: Vector2):
	yaw -= relative.x * orbit_sensitivity
	pitch += relative.y * orbit_sensitivity
	pitch = clamp(pitch, deg_to_rad(-89), deg_to_rad(89))
	_update_camera_position()

func _pan(relative: Vector2):
	# Calculate the right and up directions
	var right = global_transform.basis.x.normalized()
	var up = global_transform.basis.y.normalized()
	
	# Pan in screen space (left/right and up/down)
	target_position -= (right * relative.x + up * -relative.y) * pan_sensitivity
	_update_camera_position()

func _zoom(amount: float):
	distance = max(0.1, distance + amount)
	_update_camera_position()

func _update_camera_position():
	var offset = Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	global_position = target_position + offset
	look_at(target_position, Vector3.UP)
