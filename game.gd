extends Node
class_name LemWar

@export var players: Array[PlayerData]
@export var cities: Array[CityData]
@export var map: GameMap

var setup: Setup



func _ready() -> void:
	setup = Setup.new()
	setup.setup_finished.connect(_on_setup_finished)

	add_child(setup)	
	

func _on_setup_finished():	
	print("Setup finished")
	create_visuals()
	
	
func create_visuals():
	map.create_city_visuals()
