extends Resource
class_name CityData

var icon: Texture2D = preload("res://art/city_icon.svg")

@export var city_name: String = "Base City"
@export var connections: Array[CityData] = []
@export var buildings: Array = []
@export var owned_by: PlayerData
@export var location: Vector2
