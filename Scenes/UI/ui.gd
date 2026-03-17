extends Control

@onready var add_floor: Window = $"Top Panel/HBoxContainer/VBOx/Add Floor"
@onready var item_list: ItemList = $Outliner/VBoxContainer/Objects/ItemList
@onready var playback_button: Button = $Playback/HBoxContainer/Playback_button
@onready var add_fluid: Window = $"Top Panel/HBoxContainer/VBOx/Add Fluid"

var name_counters := {}

func _ready() -> void:
	SignalManager.spawn_button_pressed.connect(spawn_button_pressed)
	SignalManager.ragdoll_button_pressed.connect(ragdoll_button_pressed)


func ragdoll_button_pressed(ragdoll: PackedScene) -> void:
	var new_ragdoll = ragdoll.instantiate()
	new_ragdoll.add_to_group("Ragdoll")
	var base_name = new_ragdoll.name
	var unique_name = _get_unique_name(base_name)
	new_ragdoll.name = unique_name
	add_child(new_ragdoll)                    # FIX: in tree BEFORE global_position
	new_ragdoll.global_position = Vector3(0, 0, 0)
	SignalManager.on_object_added(new_ragdoll)


func spawn_button_pressed(object: PackedScene) -> void:
	var new_obj = object.instantiate()
	new_obj.add_to_group('obj')
	var phys_mat = PhysicsMaterial.new()
	new_obj.physics_material_override = phys_mat
	var base_name = new_obj.name
	var unique_name = _get_unique_name(base_name)
	new_obj.name = unique_name
	add_child(new_obj)                        # FIX line 36/37: add_child FIRST
	new_obj.global_position = Vector3(0, 5, 0) # now safe — node is in tree
	SignalManager.on_object_added(new_obj)


func _name_exists(name: String) -> bool:
	for i in range(item_list.item_count):
		if item_list.get_item_text(i) == name:
			return true
	return false

func _get_unique_name(base_name: String) -> String:
	if not name_counters.has(base_name):
		name_counters[base_name] = 0
	var candidate = base_name
	if _name_exists(candidate):
		name_counters[base_name] += 1
		candidate = "%s-%d" % [base_name, name_counters[base_name]]
	return candidate

func _on_add_floor_pressed() -> void:
	add_floor.visible = true

func _on_button_pressed() -> void:
	add_fluid.visible = true
