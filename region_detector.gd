extends RefCounted
class_name Region

## Region types
enum RegionType { 
	MOUNTAIN_RANGE, 
	ISLAND, 
	CONTINENT,
	WOODLAND, 
	DESERT,
	TUNDRA,
	SWAMP,
	PLAINS,
	OCEAN,
	SEA
}

## Unique ID
var id: int = -1

## Voronoi cell indices belonging to this region
var voronoi_indices: Array[int] = []

## Type of region
var region_type: RegionType = RegionType.PLAINS

## Dominant terrain type ID
var terrain_type_id: String = ""

## Bounding box
var bounds: Rect2 = Rect2()

## Center point
var center: Vector2 = Vector2.ZERO

## Generated or custom name
var region_name: String = ""

## Additional properties
var properties: Dictionary = {}

func _init(p_id: int = -1, p_terrain_id: String = "") -> void:
	id = p_id
	terrain_type_id = p_terrain_id

func calculate_bounds(point_positions: Array) -> void:
	"""Calculate bounding box from voronoi cell positions"""
	if voronoi_indices.is_empty():
		return
	
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	
	for idx in voronoi_indices:
		if idx >= 0 and idx < point_positions.size():
			var pos: Vector2 = point_positions[idx]
			min_x = min(min_x, pos.x)
			min_y = min(min_y, pos.y)
			max_x = max(max_x, pos.x)
			max_y = max(max_y, pos.y)
	
	bounds = Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
	center = bounds.get_center()

func size() -> int:
	"""Return number of cells in this region"""
	return voronoi_indices.size()

static func detect_regions(point_data_array: Array, terrain_types: Dictionary) -> Array[Region]:
	"""
	Auto-detect regions by clustering adjacent cells with same terrain type.
	Uses flood fill algorithm.
	"""
	var regions: Array[Region] = []
	var visited: Array[bool] = []
	visited.resize(point_data_array.size())
	visited.fill(false)
	
	var region_id := 0
	
	for i in range(point_data_array.size()):
		if visited[i]:
			continue
		
		var point_data: PointData = point_data_array[i]
		var terrain_id := point_data.terrain_type_id
		
		# Start flood fill
		var cluster := _flood_fill_terrain(i, terrain_id, point_data_array, visited)
		
		# Only create region if cluster is large enough (3+ cells)
		if cluster.size() >= 3:
			var region := Region.new(region_id, terrain_id)
			region.voronoi_indices = cluster
			region.region_type = _determine_region_type(terrain_id, terrain_types)
			region.region_name = _generate_region_name(region.region_type, region_id)
			regions.append(region)
			region_id += 1
	
	# Calculate bounds for all regions
	var positions: Array = []
	for pd in point_data_array:
		positions.append(pd.position)
	
	for region in regions:
		region.calculate_bounds(positions)
	
	return regions

static func _flood_fill_terrain(
	start_idx: int, 
	terrain_id: String, 
	point_data_array: Array,
	visited: Array[bool]
) -> Array[int]:
	"""Flood fill to find all connected cells with same terrain"""
	var cluster: Array[int] = []
	var queue: Array[int] = [start_idx]
	visited[start_idx] = true
	
	while not queue.is_empty():
		var current_idx: int = queue.pop_front()
		cluster.append(current_idx)
		
		# Check neighbors (this needs access to adjacency data)
		# For now, we'll use a simple distance check
		var current_pos: Vector2 = point_data_array[current_idx].position
		
		for i in range(point_data_array.size()):
			if visited[i]:
				continue
			
			var neighbor_data: PointData = point_data_array[i]
			if neighbor_data.terrain_type_id != terrain_id:
				continue
			
			# Check if neighbor is adjacent (within reasonable distance)
			var dist := current_pos.distance_to(neighbor_data.position)
			if dist < 150.0:  # Adjust based on your voronoi cell size
				visited[i] = true
				queue.append(i)
	
	return cluster

static func _determine_region_type(terrain_id: String, terrain_types: Dictionary) -> RegionType:
	"""Determine region type based on terrain"""
	match terrain_id:
		"mountains":
			return RegionType.MOUNTAIN_RANGE
		"forest":
			return RegionType.WOODLAND
		"desert":
			return RegionType.DESERT
		"tundra":
			return RegionType.TUNDRA
		"swamp":
			return RegionType.SWAMP
		"plains", "fields", "hills":
			return RegionType.PLAINS
		"water_shallow":
			return RegionType.SEA
		"water_deep":
			return RegionType.OCEAN
	
	return RegionType.PLAINS

static func _generate_region_name(type: RegionType, id: int) -> String:
	"""Generate a name for the region"""
	var prefixes := {
		RegionType.MOUNTAIN_RANGE: ["Ironpeak", "Stormcrest", "Frostspine"],
		RegionType.ISLAND: ["Emerald Isle", "Coral", "Misty"],
		RegionType.CONTINENT: ["Greater", "New", "Ancient"],
		RegionType.WOODLAND: ["Greenwood", "Darkforest", "Eldergrove"],
		RegionType.DESERT: ["Sunscorch", "Golden Sands", "Dustwind"],
		RegionType.TUNDRA: ["Frostlands", "Icereach", "Snowpeak"],
		RegionType.SWAMP: ["Mistmarsh", "Blackwater", "Rotfen"],
		RegionType.PLAINS: ["Goldenfields", "Meadowlands", "Windplains"],
		RegionType.OCEAN: ["Azure", "Sapphire", "Deep Blue"],
		RegionType.SEA: ["Crystal", "Tranquil", "Bay of"]
	}
	
	var suffixes := {
		RegionType.MOUNTAIN_RANGE: [" Mountains", " Range", " Peaks"],
		RegionType.ISLAND: [" Island", " Atoll", " Key"],
		RegionType.CONTINENT: [" Lands", " Territories", " Realm"],
		RegionType.WOODLAND: [" Forest", " Woods", " Grove"],
		RegionType.DESERT: [" Desert", " Wastes", " Dunes"],
		RegionType.TUNDRA: [" Tundra", " Wastes", " Expanse"],
		RegionType.SWAMP: [" Swamp", " Marsh", " Bog"],
		RegionType.PLAINS: [" Plains", " Fields", " Prairies"],
		RegionType.OCEAN: [" Ocean", " Deep", " Depths"],
		RegionType.SEA: [" Sea", " Waters", " Bay"]
	}
	
	var prefix_list = prefixes.get(type, ["Region"])
	var suffix_list = suffixes.get(type, [" %d" % id])
	
	var prefix = prefix_list[id % prefix_list.size()]
	var suffix = suffix_list[id % suffix_list.size()]
	
	return prefix + suffix
