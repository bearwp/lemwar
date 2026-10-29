extends Resource
class_name TerrainType

## Unique identifier for this terrain type
@export var id: String = ""

## Display name shown to players
@export var display_name: String = ""

## Category: LAND or WATER
enum Category { LAND, WATER }
@export var category: Category = Category.LAND

## Visual representation color
@export var color: Color = Color.WHITE

## Optional texture for this terrain (can be null for solid colors)
@export var texture: Texture2D = null

## How likely this terrain is to spread (0.0 = never, 1.0 = always tries)
@export_range(0.0, 1.0) var growth_rate: float = 0.0

## How this terrain grows
enum GrowthPattern { NONE, OMNIDIRECTIONAL, DIRECTIONAL }
@export var growth_pattern: GrowthPattern = GrowthPattern.NONE

## For DIRECTIONAL growth, preferred direction (e.g., Vector2.RIGHT for east)
@export var growth_direction_preference: Vector2 = Vector2.ZERO

## Array of terrain IDs this can grow into (empty = can't grow)
@export var can_grow_into: Array[String] = []

## Movement cost multiplier for gameplay (1.0 = normal, 2.0 = twice as slow)
@export var movement_cost: float = 1.0

## Higher priority terrains blend over lower priority at edges
@export var blend_priority: int = 0

## Whether this terrain blocks paths
@export var blocks_paths: bool = false

## Whether this terrain is navigable by ships
@export var navigable_by_ship: bool = false

func _init(
	p_id: String = "",
	p_display_name: String = "",
	p_category: Category = Category.LAND,
	p_color: Color = Color.WHITE
) -> void:
	id = p_id
	display_name = p_display_name
	category = p_category
	color = p_color
