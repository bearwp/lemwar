extends Node
class_name GrowthSystem

## Apply terrain growth for specified iterations
static func apply_terrain_growth(
	point_data_array: Array,
	terrain_types: Dictionary,
	adjacency_map: Dictionary,
	iterations: int = 3
) -> void:
	"""
	Apply terrain growth algorithm.
	adjacency_map format: {point_idx: [neighbor_idx1, neighbor_idx2, ...]}
	"""
	for iteration in range(iterations):
		var growth_queue: Array[Dictionary] = []
		
		# Collect all potential growth actions
		for idx in range(point_data_array.size()):
			var point_data: PointData = point_data_array[idx]
			var terrain_type: TerrainType = terrain_types.get(point_data.terrain_type_id)
			
			if terrain_type == null or terrain_type.growth_rate == 0.0:
				continue
			
			# Get neighbors
			var neighbors: Array = adjacency_map.get(idx, [])
			
			for neighbor_idx in neighbors:
				if neighbor_idx < 0 or neighbor_idx >= point_data_array.size():
					continue
				
				var neighbor_data: PointData = point_data_array[neighbor_idx]
				
				# Check if can grow into this terrain
				if not terrain_type.can_grow_into.has(neighbor_data.terrain_type_id):
					continue
				
				# Calculate growth chance
				var chance := _calculate_growth_chance(
					point_data, 
					neighbor_data, 
					terrain_type,
					adjacency_map
				)
				
				if randf() < chance:
					growth_queue.append({
						"target_idx": neighbor_idx,
						"new_terrain_id": terrain_type.id
					})
		
		# Apply all growth actions
		for action in growth_queue:
			point_data_array[action.target_idx].terrain_type_id = action.new_terrain_id

static func _calculate_growth_chance(
	from_point: PointData,
	to_point: PointData,
	terrain_type: TerrainType,
	adjacency_map: Dictionary
) -> float:
	"""Calculate the chance of growth based on terrain type and pattern"""
	var base_chance := terrain_type.growth_rate
	
	# Directional growth (mountains, water)
	if terrain_type.growth_pattern == TerrainType.GrowthPattern.DIRECTIONAL:
		var direction := (to_point.position - from_point.position).normalized()
		var alignment := direction.dot(terrain_type.growth_direction_preference.normalized())
		# Boost chance if aligned with preferred direction
		base_chance *= (0.5 + alignment * 0.5)
	
	# Omnidirectional growth (forests)
	elif terrain_type.growth_pattern == TerrainType.GrowthPattern.OMNIDIRECTIONAL:
		# Check how many neighbors already have this terrain (clustering)
		var neighbor_count := 0
		var same_terrain_count := 0
		
		var to_neighbors: Array = adjacency_map.get(to_point.position, [])
		for neighbor_idx in to_neighbors:
			neighbor_count += 1
			# This would need actual neighbor data, simplified for now
			
		# Boost if surrounded by same terrain
		if neighbor_count > 0:
			var surrounded_ratio := float(same_terrain_count) / float(neighbor_count)
			base_chance *= (1.0 + surrounded_ratio)
	
	return clamp(base_chance, 0.0, 1.0)

static func apply_loyalty_spread(
	point_data_array: Array,
	adjacency_map: Dictionary,
	player_id: int,
	source_indices: Array[int],
	iterations: int = 1,
	decay_rate: float = 0.8
) -> void:
	"""
	Spread loyalty from source points outward.
	decay_rate: how much loyalty decreases per hop (0.8 = 20% loss)
	"""
	var current_wave: Dictionary = {}  # {idx: loyalty_value}
	
	# Initialize with source points
	for idx in source_indices:
		if idx >= 0 and idx < point_data_array.size():
			current_wave[idx] = 1.0
			point_data_array[idx].set_loyalty(player_id, 1.0)
	
	# Spread outward for each iteration
	for iteration in range(iterations):
		var next_wave: Dictionary = {}
		
		for source_idx in current_wave:
			var loyalty_value: float = current_wave[source_idx] * decay_rate
			
			if loyalty_value < 0.1:  # Too weak to spread further
				continue
			
			var neighbors: Array = adjacency_map.get(source_idx, [])
			
			for neighbor_idx in neighbors:
				if neighbor_idx < 0 or neighbor_idx >= point_data_array.size():
					continue
				
				var neighbor_data: PointData = point_data_array[neighbor_idx]
				var current_loyalty := neighbor_data.get_loyalty(player_id)
				
				# Only spread if new loyalty is stronger
				if loyalty_value > current_loyalty:
					neighbor_data.set_loyalty(player_id, loyalty_value)
					next_wave[neighbor_idx] = loyalty_value
		
		current_wave = next_wave

static func calculate_adjacency_map(point_data_array: Array, max_distance: float = 150.0) -> Dictionary:
	"""
	Calculate which points are adjacent based on distance.
	Returns: {point_idx: [neighbor_idx1, neighbor_idx2, ...]}
	"""
	var adjacency_map: Dictionary = {}
	
	for i in range(point_data_array.size()):
		var neighbors: Array[int] = []
		var pos_i: Vector2 = point_data_array[i].position
		
		for j in range(point_data_array.size()):
			if i == j:
				continue
			
			var pos_j: Vector2 = point_data_array[j].position
			var dist := pos_i.distance_to(pos_j)
			
			if dist <= max_distance:
				neighbors.append(j)
		
		adjacency_map[i] = neighbors
	
	return adjacency_map
