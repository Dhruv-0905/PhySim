extends VBoxContainer
class_name  Physics_prop
# Actual Values
@onready var mass: HSlider = $Mass
@onready var gravity_scale: HSlider = $GravityScale
@onready var friction: HSlider = $Friction
@onready var bounce: HSlider = $Bounce
@onready var check_box: CheckBox = $CheckBox
@onready var check_box_2: CheckBox = $CheckBox2

# Labels for the values
@onready var mass_lab: Label = $"Mass-lab"
@onready var gravity_scale_lab: Label = $"Gravity Scale-lab"
@onready var friction_label: Label = $"Friction label"
@onready var bounce_lab: Label = $"Bounce-lab"


var current_node: Node = null
var current_material: PhysicsMaterial = null

func _process(delta: float) -> void:
	update_values()

func set_selected_object(obj: Node) -> void:
	current_node = obj
	current_material = current_node.physics_material_override
	_update_ui_from_material()


func _update_ui_from_material() -> void:
	mass.value = current_node.mass
	gravity_scale.value = current_node.gravity_scale
	friction.value = current_material.friction
	bounce.value = current_material.bounce
	check_box.button_pressed = current_material.rough
	check_box_2.button_pressed = current_material.absorbent

func _clear_ui() -> void:
	friction.value = 0
	bounce.value = 0
	check_box.button_pressed = false
	check_box_2.button_pressed = false

# Called when UI changes
func _on_mass_changed(value: float) -> void:
	if current_node:
		current_node.mass = value

func _on_gravity_scale_changed(value: float) -> void:
	if current_node:
		current_node.gravity_scale = value

func _on_friction_changed(value: float) -> void:
	if current_material:
		current_material.friction = value

func _on_bounce_changed(value: float) -> void:
	if current_material:
		current_material.bounce = value

func _on_rough_toggled(pressed: bool) -> void:
	if current_material:
		current_material.rough = pressed

func _on_absorb_toggled(pressed: bool) -> void:
	if current_material:
		current_material.absorbent = pressed




func _on_bounce_value_changed(value: float) -> void:
	_on_bounce_changed(value)

func _on_friction_value_changed(value: float) -> void:
	_on_friction_changed(value)

func _on_check_box_toggled(toggled_on: bool) -> void:
	_on_rough_toggled(toggled_on)

func _on_check_box_2_toggled(toggled_on: bool) -> void:
	_on_absorb_toggled(toggled_on)

func _on_mass_value_changed(value: float) -> void:
	_on_mass_changed(value)

func _on_gravity_scale_value_changed(value: float) -> void:
	_on_gravity_scale_changed(value)


func update_values() -> void:
	mass_lab.text = "Mass(Kg): " + str(mass.value)
	gravity_scale_lab.text = "Gravity Scale: " + str(gravity_scale.value)
	friction_label.text = "Friction: " + str(friction.value)
	bounce_lab.text = "Bounce: " + str(bounce.value)
