extends RefCounted
class_name PointData

## Enums for point types
enum PointType { CITY, VILLAGE, NATURE }

## Position in world space
var position: Vector2 = Vector2.ZERO

## Type of point (settlement or nature)
var point_type: PointType = PointType.NATURE

## Reference to the terrain type ID for this voronoi cell
var terrain_type_id: String = "plains"

## Population density (0.0 = uninhabited, 1.0 = dense city)
var population_density: float = 0.0

## Loyalty values per player {player_id: loyalty_value (0.0-1.0)}
var loyalty: Dictionary = {}

## Custom name for this point
var custom_name: String = ""

## AI-generated description
var description: String = ""

## Additional extensible properties
var properties: Dictionary = {}

## Optional sprite override
var sprite_override: Texture2D = null

func _init(
	p_position: Vector2 = Vector2.ZERO,
	p_type: PointType = PointType.NATURE,
	p_terrain_id: String = "plains"
) -> void:
	position = p_position
	point_type = p_type
	terrain_type_id = p_terrain_id

func set_loyalty(player_id: int, value: float) -> void:
	"""Set loyalty value for a specific player"""
	loyalty[player_id] = clamp(value, 0.0, 1.0)

func get_loyalty(player_id: int) -> float:
	"""Get loyalty value for a specific player"""
	return loyalty.get(player_id, 0.0)

func get_dominant_player() -> int:
	"""Returns the player ID with the highest loyalty, or -1 if none"""
	if loyalty.is_empty():
		return -1
	
	var max_loyalty := 0.0
	var dominant_player := -1
	
	for player_id in loyalty:
		if loyalty[player_id] > max_loyalty:
			max_loyalty = loyalty[player_id]
			dominant_player = player_id
	
	return dominant_player if max_loyalty > 0.5 else -1

func to_dict() -> Dictionary:
	"""Serialize to dictionary for saving"""
	return {
		"position": position,
		"point_type": point_type,
		"terrain_type_id": terrain_type_id,
		"population_density": population_density,
		"loyalty": loyalty.duplicate(),
		"custom_name": custom_name,
		"description": description,
		"properties": properties.duplicate()
	}

static func from_dict(data: Dictionary) -> PointData:
	"""Deserialize from dictionary"""
	var point = PointData.new(
		data.get("position", Vector2.ZERO),
		data.get("point_type", PointType.NATURE),
		data.get("terrain_type_id", "plains")
	)
	point.population_density = data.get("population_density", 0.0)
	point.loyalty = data.get("loyalty", {}).duplicate()
	point.custom_name = data.get("custom_name", "")
	point.description = data.get("description", "")
	point.properties = data.get("properties", {}).duplicate()
	return point
