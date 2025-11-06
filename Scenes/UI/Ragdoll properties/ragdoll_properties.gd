extends VBoxContainer
class_name Ragdoll_Property
@onready var mass_lab: Label = $"VBoxContainer/Mass-lab"
@onready var grav_scale: Label = $"VBoxContainer/Grav-Scale"
@onready var linear_damp_lab: Label = $"VBoxContainer/Linear-damp-lab"
@onready var angular_damp_lab: Label = $"VBoxContainer/Angular-damp-lab"

@onready var mass_slider: HSlider = $"VBoxContainer/Mass-slider"
@onready var gravity_scale_slider: HSlider = $"VBoxContainer/gravity-scale-slider"
@onready var linear_damp_slider: HSlider = $"VBoxContainer/Linear-damp-slider"
@onready var angular_damp_slider: HSlider = $"VBoxContainer/Angular-damp-slider"


var current_ragdoll: Ragdoll

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	update_values()


func _update_ui_from_ragdoll() -> void:
	mass_slider.value = current_ragdoll.Bones[0].mass
	gravity_scale_slider.value = current_ragdoll.Bones[0].gravity_scale
	linear_damp_slider.value = current_ragdoll.Bones[0].linear_damp
	angular_damp_slider.value = current_ragdoll.Bones[0].angular_damp

# functions to change the values
func set_selected_ragdoll(ragdoll: Ragdoll):
	current_ragdoll = ragdoll
	_update_ui_from_ragdoll()

func _on_mass_changed(value: float):
	for bone in current_ragdoll.Bones:
		bone.mass = value

func _on_grav_scale_changed(value: float):
	for bone in current_ragdoll.Bones:
		bone.gravity_scale = value

func _on_angular_damp_changed(value: float):
	for bone in current_ragdoll.Bones:
		bone.angular_damp = value

func _on_linear_damp_changed(value: float):
	for bone in current_ragdoll.Bones:
		bone.linear_damp = value



# Signals that initiate the change
func _on_massslider_value_changed(value: float) -> void:
	_on_mass_changed(value)

func _on_gravityscaleslider_value_changed(value: float) -> void:
	_on_grav_scale_changed(value)

func _on_lineardampslider_value_changed(value: float) -> void:
	_on_linear_damp_changed(value)

func _on_angulardampslider_value_changed(value: float) -> void:
	_on_angular_damp_changed(value)


func update_values() -> void:
	mass_lab.text = "Mass Per bone(Kg): " + str(mass_slider.value)
	grav_scale.text = "Gravity Scale Per bone: " + str(gravity_scale_slider.value)
	linear_damp_lab.text = "Linear Damp Per bone: " + str(linear_damp_slider.value)
	angular_damp_lab.text = "Angular Damp Per bone: " + str(angular_damp_slider.value)
