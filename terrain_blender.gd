extends Node
class_name TerrainBlender

static func generate_shoreline_paths(
	point_data_array: Array,
	adjacency_map: Dictionary,
	terrain_types: Dictionary
) -> Array[PathData]:
	"""
	Generate shoreline paths between water and land tiles.
	"""
	var shorelines: Array[PathData] = []
	
	for idx in range(point_data_array.size()):
		var point_data: PointData = point_data_array[idx]
		var terrain: TerrainType = terrain_types.get(point_data.terrain_type_id)
		
		if terrain == null:
			continue
		
		var neighbors: Array = adjacency_map.get(idx, [])
		
		for neighbor_idx in neighbors:
			if neighbor_idx >= point_data_array.size():
				continue
			
			var neighbor_data: PointData = point_data_array[neighbor_idx]
			var neighbor_terrain: TerrainType = terrain_types.get(neighbor_data.terrain_type_id)
			
			if neighbor_terrain == null:
				continue
			
			# Check if one is water and one is land
			var is_shoreline := (
				(terrain.category == TerrainType.Category.WATER and 
				 neighbor_terrain.category == TerrainType.Category.LAND) or
				(terrain.category == TerrainType.Category.LAND and 
				 neighbor_terrain.category == TerrainType.Category.WATER)
			)
			
			if is_shoreline:
				# Create shoreline path
				var midpoint := (point_data.position + neighbor_data.position) / 2.0
				var shoreline := PathData.new(idx, neighbor_idx, midpoint, PathData.PathType.SHORELINE)
				shoreline.auto_generated = true
				shorelines.append(shoreline)
	
	return shorelines

static func blend_colors(color1: Color, color2: Color, t: float) -> Color:
	"""Blend two colors with interpolation factor t"""
	return color1.lerp(color2, t)

static func should_create_transition(
	terrain1: TerrainType, 
	terrain2: TerrainType
) -> bool:
	"""Determine if a visual transition should be created between terrains"""
	if terrain1 == null or terrain2 == null:
		return false
	
	# Always create transitions between water and land
	if terrain1.category != terrain2.category:
		return true
	
	# Create transitions for high priority differences
	var priority_diff := abs(terrain1.blend_priority - terrain2.blend_priority)
	return priority_diff >= 2

static func get_transition_color(
	terrain1: TerrainType,
	terrain2: TerrainType,
	t: float
) -> Color:
	"""Get blended color for transition between two terrains"""
	if terrain1 == null or terrain2 == null:
		return Color.WHITE
	
	# Use blend priority to determine which color dominates
	if terrain1.blend_priority > terrain2.blend_priority:
		return blend_colors(terrain2.color, terrain1.color, t * 0.7)
	else:
		return blend_colors(terrain1.color, terrain2.color, t * 0.7)
