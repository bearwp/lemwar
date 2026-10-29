extends Node
class_name TerrainManager

## Dictionary of loaded terrain types {terrain_id: TerrainType}
var terrain_types: Dictionary = {}

## Preloaded terrain paths
const TERRAIN_PATHS = [
	"res://terrain/types/water_shallow.tres",
	"res://terrain/types/water_deep.tres",
	"res://terrain/types/land_plains.tres",
	"res://terrain/types/land_fields.tres",
	"res://terrain/types/land_forest.tres",
	"res://terrain/types/land_desert.tres",
	"res://terrain/types/land_swamp.tres",
	"res://terrain/types/land_tundra.tres",
	"res://terrain/types/land_hills.tres",
	"res://terrain/types/land_mountains.tres"
]

func _init() -> void:
	load_all_terrains()

func load_all_terrains() -> void:
	"""Load all terrain type resources"""
	terrain_types.clear()
	
	for path in TERRAIN_PATHS:
		if ResourceLoader.exists(path):
			var terrain: TerrainType = load(path)
			if terrain:
				terrain_types[terrain.id] = terrain
				print("Loaded terrain: ", terrain.id)
		else:
			print("WARNING: Terrain resource not found: ", path)
	
	print("TerrainManager: Loaded %d terrain types" % terrain_types.size())

func get_terrain(terrain_id: String) -> TerrainType:
	"""Get a terrain type by ID"""
	return terrain_types.get(terrain_id)

func get_all_terrain_ids() -> Array[String]:
	"""Get all available terrain IDs"""
	var ids: Array[String] = []
	for id in terrain_types.keys():
		ids.append(id)
	return ids

func get_random_land_terrain() -> String:
	"""Get a random land terrain ID"""
	var land_terrains: Array[String] = []
	for id in terrain_types:
		var terrain: TerrainType = terrain_types[id]
		if terrain.category == TerrainType.Category.LAND:
			land_terrains.append(id)
	
	if land_terrains.is_empty():
		return "plains"
	
	return land_terrains[randi() % land_terrains.size()]

func get_terrain_color(terrain_id: String) -> Color:
	"""Get color for a terrain ID"""
	var terrain := get_terrain(terrain_id)
	if terrain:
		return terrain.color
	return Color.GRAY

func is_water_terrain(terrain_id: String) -> bool:
	"""Check if terrain is water"""
	var terrain := get_terrain(terrain_id)
	if terrain:
		return terrain.category == TerrainType.Category.WATER
	return false

func is_land_terrain(terrain_id: String) -> bool:
	"""Check if terrain is land"""
	var terrain := get_terrain(terrain_id)
	if terrain:
		return terrain.category == TerrainType.Category.LAND
	return true
