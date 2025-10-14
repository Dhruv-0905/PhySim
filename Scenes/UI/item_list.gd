extends ItemList

func _on_item_selected(index: int) -> void:
	var obj_list = get_tree().get_nodes_in_group("obj")
	var obj = obj_list[index]
	SignalManager.on_object_selected(obj)

func _ready() -> void:
	SignalManager.camera_obj_selected.connect(select)
