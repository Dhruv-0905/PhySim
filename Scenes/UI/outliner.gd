extends MarginContainer

@onready var item_list: ItemList = $VBoxContainer/Objects/ItemList
@onready var physics_properties: VBoxContainer = $"VBoxContainer/Physics Properties"
@onready var ragdoll_properties: Ragdoll_Property = $"VBoxContainer/Ragdoll properties"

func _ready() -> void:
	SignalManager.object_added.connect(register_obj)
	SignalManager.object_selected.connect(on_item_selected)
	SignalManager.ragdoll_selected.connect(on_ragdoll_selected)
	physics_properties.visible = false

# add the object to item_list
func register_obj(obj: Node3D):
	var name = obj.name
	if obj.is_in_group('obj') or obj.is_in_group("Ragdoll"):
		item_list.add_item(name)


# In your outliner script
func on_item_selected(obj:Node):
	physics_properties.set_selected_object(obj)
	physics_properties.visible = true
	
func on_ragdoll_selected(ragdoll: Ragdoll):
	ragdoll_properties.set_selected_ragdoll(ragdoll)
	ragdoll_properties.visible = true


#func add_to_itemlist() -> void:
	#for i in get_tree().get_nodes_in_group("obj"):
		#register_obj(i)

	
