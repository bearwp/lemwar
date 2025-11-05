extends Node2D

var city_data: CityData

func _on_area_2d_mouse_entered() -> void:
	print("hello")
	pass # Replace with function body.


func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("HI") 
			_handle_menu()


func _handle_menu():
	if $Menu.visible == true:
		$Menu.visible = false
	elif $Menu.visible == false:
		$Menu.visible = true
		
