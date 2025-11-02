@tool
extends Node
class_name Setup

signal setup_finished	


@export var player_no: int = 6
@export var city_no: int = 10


@export var generate_map: bool = false:	
	set(value):
		if value and Engine.is_editor_hint():
			_setup()
		generate_map = false
		
func _ready() -> void:
	_setup()		
		
func _setup():
	await _setup_players()
	await _setup_cities()
	setup_finished.emit()
			
func _setup_players():
	Game.players.clear()
	for i in player_no:
		var new_player = PlayerData.new()
		new_player.player_name = "Player " + str(i)
		new_player.colour = Color(randf(), randf(), randf(), 1)
		Game.players.append(new_player)
		
	
	print(Game.players.size(), " players set up")
	pass		
		
func _setup_cities():
	Game.cities.clear()
	for i in city_no:
		var new_city = CityData.new()
		new_city.city_name = "City " + str(i)
		new_city.owned_by = Game.players[randi_range(0, Game.players.size()-1)]
		new_city.location = Vector2(randf_range(0,500), randf_range(0,300))
		print(new_city.city_name)
		print(new_city.owned_by.player_name)
		Game.cities.append(new_city)
		
		
	print(Game.cities.size(), " cities set up")

	pass
