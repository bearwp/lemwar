extends RefCounted
class_name PathData

## Path types
enum PathType { ROAD, HIGHWAY, TRAIL, BRIDGE, SHORELINE, RIVER }

## Indices of connected points
var from_point_idx: int = -1
var to_point_idx: int = -1

## Bend point for curved paths (Voronoi point)
var voronoi_point: Vector2 = Vector2.ZERO

## Type of path
var path_type: PathType = PathType.ROAD

## Quality/condition (0.0 = dirt, 1.0 = paved)
var quality: float = 0.5

## Whether this was auto-generated or player-built
var auto_generated: bool = true

## Additional properties
var properties: Dictionary = {}

func _init(
	p_from: int = -1,
	p_to: int = -1,
	p_voronoi: Vector2 = Vector2.ZERO,
	p_type: PathType = PathType.ROAD
) -> void:
	from_point_idx = p_from
	to_point_idx = p_to
	voronoi_point = p_voronoi
	path_type = p_type

func get_width() -> float:
	"""Calculate visual width based on path type and quality"""
	var base_width := 3.0
	match path_type:
		PathType.HIGHWAY:
			base_width = 5.5
		PathType.ROAD:
			base_width = 3.5
		PathType.TRAIL:
			base_width = 2.0
		PathType.BRIDGE:
			base_width = 4.0
		PathType.SHORELINE:
			base_width = 2.5
		PathType.RIVER:
			base_width = 3.0
	
	return base_width * (0.7 + quality * 0.3)

func get_color() -> Color:
	"""Get color based on path type"""
	match path_type:
		PathType.HIGHWAY:
			return Color(0.4, 0.25, 0.15, 0.7)
		PathType.ROAD:
			return Color(0.63, 0.38, 0.15, 0.7)
		PathType.TRAIL:
			return Color(0.5, 0.45, 0.3, 0.5)
		PathType.BRIDGE:
			return Color(0.5, 0.4, 0.3, 0.8)
		PathType.SHORELINE:
			return Color(0.9, 0.85, 0.6, 0.6)
		PathType.RIVER:
			return Color(0.4, 0.6, 0.85, 0.7)
	
	return Color.WHITE

func to_dict() -> Dictionary:
	"""Serialize to dictionary"""
	return {
		"from_point_idx": from_point_idx,
		"to_point_idx": to_point_idx,
		"voronoi_point": voronoi_point,
		"path_type": path_type,
		"quality": quality,
		"auto_generated": auto_generated,
		"properties": properties.duplicate()
	}

static func from_dict(data: Dictionary) -> PathData:
	"""Deserialize from dictionary"""
	var path = PathData.new(
		data.get("from_point_idx", -1),
		data.get("to_point_idx", -1),
		data.get("voronoi_point", Vector2.ZERO),
		data.get("path_type", PathType.ROAD)
	)
	path.quality = data.get("quality", 0.5)
	path.auto_generated = data.get("auto_generated", true)
	path.properties = data.get("properties", {}).duplicate()
	return path
