extends Control

#Probably the messiest script in the project for now

@onready var add_floor: Window = $"Top Panel/HBoxContainer/HBoxContainer2/Add Floor"
@onready var item_list: ItemList = $Outliner/VBoxContainer/Objects/ItemList
@onready var playback_button: Button = $Playback/Playback_button



var name_counters := {}

func _ready() -> void:
	SignalManager.spawn_button_pressed.connect(spawn_button_pressed)


func spawn_button_pressed(object: PackedScene) -> void:
	var new_obj = object.instantiate()
	new_obj.add_to_group('obj')
	var phys_mat = PhysicsMaterial.new()
	new_obj.physics_material_override = phys_mat
	var base_name = new_obj.name
	var unique_name = _get_unique_name(base_name)
	new_obj.name = unique_name
	
	SignalManager.on_object_added(new_obj)
	new_obj.global_position = Vector3(0, 5, 0)
	add_child(new_obj)
	
# This should be in outliner.gd
# check if an instance of object already exists
func _name_exists(name: String) -> bool:
	for i in range(item_list.item_count):
		if item_list.get_item_text(i) == name:
			return true
	return false

func _get_unique_name(base_name: String) -> String:
	# If it's the first time we see this name
	if not name_counters.has(base_name):
		name_counters[base_name] = 0

	var candidate = base_name
	if _name_exists(candidate):
		name_counters[base_name] += 1
		candidate = "%s-%d" % [base_name, name_counters[base_name]]

	return candidate

func _on_add_floor_pressed() -> void:
	add_floor.visible = true
