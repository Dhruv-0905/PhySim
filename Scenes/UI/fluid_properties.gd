extends VBoxContainer
class_name Fluid_Properties

@onready var fluid_density: Label = $Fluid_density
@onready var fluid_den_slider: HSlider = $fluid_den_slider

var fluid : FluidVolume3D

func _ready() -> void:
	SignalManager.fluid_spawned.connect(set_inital_fluid_properties)
	visible = false


func _on_fluid_den_slider_value_changed(value: float) -> void:
	fluid.fluid_density = value
	print(fluid.fluid_density)
	update_value()

func update_value() -> void:
	fluid_density.text = "Fluid density:" + str(fluid.fluid_density)
	
func set_inital_fluid_properties(new_fluid: FluidVolume3D) -> void:
	
	fluid = new_fluid
	fluid_den_slider.value = fluid.fluid_density
	visible = true
