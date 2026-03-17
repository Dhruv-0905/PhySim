extends VBoxContainer
class_name Physics_prop

@onready var gravity_scale     : HSlider  = $GravityScale
@onready var friction          : HSlider  = $Friction
@onready var bounce            : HSlider  = $Bounce
@onready var check_box         : CheckBox = $CheckBox
@onready var check_box_2       : CheckBox = $CheckBox2
@onready var linear_damp       : HSlider  = $Linear_damp
@onready var angular_damp      : HSlider  = $Angular_damp
@onready var mass_edit         : LineEdit = $mass_edit

@onready var mass_lab           : Label = $"Mass-lab"
@onready var gravity_scale_lab  : Label = $"Gravity Scale-lab"
@onready var friction_label     : Label = $"Friction label"
@onready var bounce_lab         : Label = $"Bounce-lab"
@onready var linear_damp_label  : Label = $"Linear Damp Label"
@onready var angular_damp_label : Label = $"Angular Damp Label"

var current_node     : Node            = null
var current_material : PhysicsMaterial = null

func _process(_delta: float) -> void:
	update_values()

func set_selected_object(obj: Node) -> void:
	current_node     = obj
	current_material = current_node.physics_material_override
	_update_ui_from_material()

func _update_ui_from_material() -> void:
	mass_edit.text      = str(current_node.mass)
	gravity_scale.value = current_node.gravity_scale
	friction.value      = current_material.friction
	bounce.value        = current_material.bounce
	check_box.button_pressed  = current_material.rough
	check_box_2.button_pressed = current_material.absorbent

func _clear_ui() -> void:
	friction.value             = 0
	bounce.value               = 0
	check_box.button_pressed   = false
	check_box_2.button_pressed = false

# ── Handlers that affect SonataBody physics state ────────────────────────────
# These MUST route through the notify methods on PhyObj so that SonataBody
# rebuilds staticnorm and restarts warmup with clean context frames.
# Direct writes (current_node.gravity_scale = value) bypass that pipeline.

func _on_gravity_scale_changed(value: float) -> void:
	if current_node and current_node.has_method("notify_gravity_scale_changed"):
		current_node.notify_gravity_scale_changed(value)
	elif current_node:
		current_node.gravity_scale = value   # fallback for non-PhyObj nodes

func _on_mass_changed(value: float) -> void:
	if current_node and current_node.has_method("notify_mass_changed"):
		current_node.notify_mass_changed(value)
		if current_node.has_method("calculate_density"):
			current_node.object_density = current_node.calculate_density()
	elif current_node:
		current_node.mass = value

func _on_linear_damp_changed(value: float) -> void:
	if current_node:
		current_node.linear_damp = value
		# linear_damp is part of the static tensor — notify SonataBody
		if current_node.has_method("notify_gravity_scale_changed"):
			# PhyObj exposes a unified physics-changed notify
			var sb := current_node.get_node_or_null("SonataBody")
			if sb and sb.has_method("on_physics_property_changed"):
				sb.on_physics_property_changed()

func _on_angular_damp_changed(value: float) -> void:
	if current_node:
		current_node.angular_damp = value
		# angular_damp is also in the static tensor — notify SonataBody
		var sb := current_node.get_node_or_null("SonataBody")
		if sb and sb.has_method("on_physics_property_changed"):
			sb.on_physics_property_changed()

# ── Material handlers (friction/bounce don't affect SonataBody static tensor) ─
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

# ── Signal forwarders (Godot connects slider signals to these) ────────────────
func _on_bounce_value_changed(value: float)        -> void: _on_bounce_changed(value)
func _on_friction_value_changed(value: float)      -> void: _on_friction_changed(value)
func _on_check_box_toggled(toggled_on: bool)       -> void: _on_rough_toggled(toggled_on)
func _on_check_box_2_toggled(toggled_on: bool)     -> void: _on_absorb_toggled(toggled_on)
func _on_gravity_scale_value_changed(value: float) -> void: _on_gravity_scale_changed(value)
func _on_linear_damp_value_changed(value: float)   -> void: _on_linear_damp_changed(value)
func _on_angular_damp_value_changed(value: float)  -> void: _on_angular_damp_changed(value)

func update_values() -> void:
	mass_lab.text           = "Mass(Kg): "      + mass_edit.text
	gravity_scale_lab.text  = "Gravity Scale: " + str(gravity_scale.value)
	friction_label.text     = "Friction: "      + str(friction.value)
	bounce_lab.text         = "Bounce: "        + str(bounce.value)
	linear_damp_label.text  = "Linear Damp: "   + str(linear_damp.value)
	angular_damp_label.text = "Angular Damp: "  + str(angular_damp.value)

func _on_mass_edit_text_submitted(new_text: String) -> void:
	_on_mass_changed(float(new_text))
	print(current_node.mass)
