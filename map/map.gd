extends Node2D
class_name GameMap

var city_scene: PackedScene = preload("res://city/city_scene.tscn")

func _ready() -> void:
	create_city_visuals()

func create_city_visuals():
	for city in Game.cities:
		var new_city = city_scene.instantiate()
		add_child(new_city)
		new_city.position = city.location
		var city_sprite = new_city.get_node("Sprite2D")
		city_sprite.self_modulate = city.owned_by.colour
