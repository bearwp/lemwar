extends Node2D
class_name GameMap

# ============================================================================
# SIGNALS
# ============================================================================

signal map_generated()
signal region_detected(region: Region)
signal point_clicked(point_index: int)

# ============================================================================
# EXPORTS - Generation Parameters
# ============================================================================

@export_group("Map Size")
@export var map_size: Vector2 = Vector2(1920, 1080)
@export var boundary_padding: float = 100.0

@export_group("Point Generation")
@export var num_points: int = 200
@export var min_distance: float = 30.0

@export_group("Settlements")
@export var num_cities: int = 5
@export var num_villages: int = 15

@export_group("Terrain Features")
@export var num_mountains: int = 3
@export var num_water_sources: int = 5
@export_range(0.0, 1.0) var water_expansion_chance: float = 0.4
@export_range(0.0, 0.5) var forest_coverage: float = 0.15
@export var forest_clusters: int = 8

@export_group("Growth")
@export var terrain_growth_iterations: int = 3
@export var mountain_growth_direction: Vector2 = Vector2(1, 0.3)

@export_group("Debug")
@export var show_voronoi_edges: bool = false
@export var show_region_names: bool = false
@export var auto_generate: bool = true

# ============================================================================
# DATA STRUCTURES
# ============================================================================

## Core systems
var terrain_manager: TerrainManager

## Map data
var point_data_array: Array[PointData] = []
var path_data_array: Array[PathData] = []
var regions: Array[Region] = []

## Delaunay/Voronoi data
var delaunay_triangles: Array = []
var voronoi_cells: Array = []
var adjacency_map: Dictionary = {}

## Interactive elements (for UI interaction)
var interactive_points: Array[InteractivePoint] = []
var interactive_paths: Array[InteractivePath] = []

## Rendering
var terrain_image: Image
var terrain_texture: ImageTexture

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	print("=== Initializing GameMap System ===")
	terrain_manager = TerrainManager.new()
	
	if auto_generate:
		call_deferred("generate_new_map")

# ============================================================================
# MAP GENERATION - Main Flow
# ============================================================================

func generate_new_map() -> void:
	"""Generate a complete new map from scratch"""
	print("\n=== Starting Map Generation ===")
	
	# Clear old data
	_clear_map()
	
	# Step 1: Generate points with Poisson disk sampling
	print("Step 1: Generating points...")
	_generate_points()
	
	# Step 2: Calculate Delaunay triangulation
	print("Step 2: Calculating Delaunay triangulation...")
	_calculate_delaunay()
	
	# Step 3: Calculate Voronoi diagram
	print("Step 3: Calculating Voronoi cells...")
	_calculate_voronoi()
	
	# Step 4: Build adjacency map
	print("Step 4: Building adjacency map...")
	_build_adjacency_map()
	
	# Step 5: Assign initial terrain types
	print("Step 5: Assigning terrain types...")
	_assign_initial_terrain()
	
	# Step 6: Place settlements
	print("Step 6: Placing settlements...")
	_place_settlements()
	
	# Step 7: Apply terrain growth
	print("Step 7: Applying terrain growth...")
	_apply_terrain_growth()
	
	# Step 8: Detect regions
	print("Step 8: Detecting regions...")
	_detect_regions()
	
	# Step 9: Generate paths
	print("Step 9: Generating paths...")
	_generate_paths()
	
	# Step 10: Generate shorelines
	print("Step 10: Generating shorelines...")
	_generate_shorelines()
	
	# Step 11: Render terrain
	print("Step 11: Rendering terrain...")
	_render_terrain()
	
	# Step 12: Create interactive elements
	print("Step 12: Creating interactive elements...")
	_create_interactive_elements()
	
	print("=== Map Generation Complete! ===")
	print("Points: %d | Paths: %d | Regions: %d" % [
		point_data_array.size(),
		path_data_array.size(),
		regions.size()
	])
	
	queue_redraw()
	map_generated.emit()

# ============================================================================
# STEP 1: Point Generation
# ============================================================================

func _generate_points() -> void:
	"""Generate points using Poisson disk sampling"""
	point_data_array.clear()
	
	var attempts := 30
	var cell_size := min_distance / sqrt(2.0)
	var grid_width := int(map_size.x / cell_size) + 1
	var grid_height := int(map_size.y / cell_size) + 1
	var grid: Array = []
	grid.resize(grid_width * grid_height)
	grid.fill(-1)
	
	var active_list: Array[Vector2] = []
	
	# Start with random point
	var first_point := Vector2(
		randf_range(boundary_padding, map_size.x - boundary_padding),
		randf_range(boundary_padding, map_size.y - boundary_padding)
	)
	
	var first_data := PointData.new(first_point, PointData.PointType.NATURE, "plains")
	point_data_array.append(first_data)
	active_list.append(first_point)
	
	var grid_x := int(first_point.x / cell_size)
	var grid_y := int(first_point.y / cell_size)
	grid[grid_y * grid_width + grid_x] = 0
	
	# Generate points
	while not active_list.is_empty() and point_data_array.size() < num_points:
		var random_index := randi() % active_list.size()
		var point := active_list[random_index]
		var found := false
		
		for _i in range(attempts):
			var angle := randf() * TAU
			var radius := randf_range(min_distance, min_distance * 2.0)
			var new_point := point + Vector2(cos(angle), sin(angle)) * radius
			
			if _is_valid_point(new_point, grid, grid_width, grid_height, cell_size):
				var new_data := PointData.new(new_point, PointData.PointType.NATURE, "plains")
				point_data_array.append(new_data)
				active_list.append(new_point)
				
				var gx := int(new_point.x / cell_size)
				var gy := int(new_point.y / cell_size)
				grid[gy * grid_width + gx] = point_data_array.size() - 1
				
				found = true
				break
		
		if not found:
			active_list.remove_at(random_index)
	
	print("  Generated %d points" % point_data_array.size())

func _is_valid_point(point: Vector2, grid: Array, grid_width: int, grid_height: int, cell_size: float) -> bool:
	"""Check if point is valid (within bounds and min distance from others)"""
	if point.x < boundary_padding or point.x >= map_size.x - boundary_padding:
		return false
	if point.y < boundary_padding or point.y >= map_size.y - boundary_padding:
		return false
	
	var grid_x := int(point.x / cell_size)
	var grid_y := int(point.y / cell_size)
	
	var search_start_x := max(0, grid_x - 2)
	var search_end_x := min(grid_width - 1, grid_x + 2)
	var search_start_y := max(0, grid_y - 2)
	var search_end_y := min(grid_height - 1, grid_y + 2)
	
	for y in range(search_start_y, search_end_y + 1):
		for x in range(search_start_x, search_end_x + 1):
			var grid_index := y * grid_width + x
			var point_index: int = grid[grid_index]
			
			if point_index != -1:
				var other_point := point_data_array[point_index].position
				if point.distance_to(other_point) < min_distance:
					return false
	
	return true

# ============================================================================
# STEP 2 & 3: Delaunay & Voronoi
# ============================================================================

func _calculate_delaunay() -> void:
	"""Calculate Delaunay triangulation"""
	var points_2d: PackedVector2Array = PackedVector2Array()
	for point_data in point_data_array:
		points_2d.append(point_data.position)
	
	delaunay_triangles = Geometry2D.triangulate_delaunay(points_2d)
	print("  Generated %d triangles" % (delaunay_triangles.size() / 3))

func _calculate_voronoi() -> void:
	"""Calculate Voronoi cells from Delaunay triangulation"""
	voronoi_cells.clear()
	voronoi_cells.resize(point_data_array.size())
	
	# Simple voronoi: each cell is the region closest to that point
	for i in range(point_data_array.size()):
		voronoi_cells[i] = {
			"point_index": i,
			"center": point_data_array[i].position,
			"edges": []
		}
	
	print("  Generated %d voronoi cells" % voronoi_cells.size())

# ============================================================================
# STEP 4: Adjacency Map
# ============================================================================

func _build_adjacency_map() -> void:
	"""Build adjacency map from Delaunay triangulation"""
	adjacency_map.clear()
	
	# Initialize empty arrays
	for i in range(point_data_array.size()):
		adjacency_map[i] = []
	
	# Build from Delaunay triangles
	for i in range(0, delaunay_triangles.size(), 3):
		var idx1: int = delaunay_triangles[i]
		var idx2: int = delaunay_triangles[i + 1]
		var idx3: int = delaunay_triangles[i + 2]
		
		# Add bidirectional edges
		var neighbors1: Array = adjacency_map[idx1]
		var neighbors2: Array = adjacency_map[idx2]
		var neighbors3: Array = adjacency_map[idx3]
		
		if not neighbors1.has(idx2):
			neighbors1.append(idx2)
		if not neighbors2.has(idx1):
			neighbors2.append(idx1)
		
		if not neighbors2.has(idx3):
			neighbors2.append(idx3)
		if not neighbors3.has(idx2):
			neighbors3.append(idx2)
		
		if not neighbors3.has(idx1):
			neighbors3.append(idx1)
		if not neighbors1.has(idx3):
			neighbors1.append(idx3)
	
	var total_edges := 0
	for neighbors in adjacency_map.values():
		total_edges += (neighbors as Array).size()
	print("  Built adjacency map with %d edges" % (total_edges / 2))

# ============================================================================
# STEP 5: Initial Terrain Assignment
# ============================================================================

func _assign_initial_terrain() -> void:
	"""Assign initial terrain types to all points"""
	# Start with all plains
	for point_data in point_data_array:
		point_data.terrain_type_id = "plains"
	
	# Place water sources
	for i in range(num_water_sources):
		var random_idx := randi() % point_data_array.size()
		point_data_array[random_idx].terrain_type_id = "water_shallow"
	
	# Place mountain seeds
	for i in range(num_mountains):
		var random_idx := randi() % point_data_array.size()
		point_data_array[random_idx].terrain_type_id = "mountains"
	
	# Place forest clusters
	for i in range(forest_clusters):
		var random_idx := randi() % point_data_array.size()
		point_data_array[random_idx].terrain_type_id = "forest"
	
	print("  Placed %d water sources, %d mountains, %d forests" % [
		num_water_sources, num_mountains, forest_clusters
	])

# ============================================================================
# STEP 6: Settlement Placement
# ============================================================================

func _place_settlements() -> void:
	"""Place cities and villages on the map"""
	var available_indices: Array[int] = []
	
	# Find valid land locations (not water or mountains)
	for i in range(point_data_array.size()):
		var terrain_id := point_data_array[i].terrain_type_id
		if terrain_id != "water_shallow" and terrain_id != "water_deep" and terrain_id != "mountains":
			available_indices.append(i)
	
	if available_indices.is_empty():
		print("WARNING: No valid locations for settlements!")
		return
	
	available_indices.shuffle()
	
	# Place cities
	var cities_placed := 0
	for i in range(min(num_cities, available_indices.size())):
		var idx := available_indices[i]
		var point_data := point_data_array[idx]
		point_data.point_type = PointData.PointType.CITY
		point_data.population_density = randf_range(0.7, 1.0)
		point_data.custom_name = _generate_city_name()
		point_data.terrain_type_id = "plains"
		cities_placed += 1
	
	# Remove used indices
	for i in range(cities_placed):
		available_indices.remove_at(0)
	
	# Place villages
	var villages_placed := 0
	for i in range(min(num_villages, available_indices.size())):
		var idx := available_indices[i]
		var point_data := point_data_array[idx]
		point_data.point_type = PointData.PointType.VILLAGE
		point_data.population_density = randf_range(0.3, 0.6)
		point_data.custom_name = _generate_village_name()
		point_data.terrain_type_id = "fields"
		villages_placed += 1
	
	print("  Placed %d cities and %d villages" % [cities_placed, villages_placed])

func _generate_city_name() -> String:
	"""Generate a random city name"""
	var prefixes := ["New", "Old", "North", "South", "East", "West", "Grand"]
	var roots := ["haven", "port", "burg", "ford", "ton", "ville", "city", "stead"]
	return prefixes[randi() % prefixes.size()] + roots[randi() % roots.size()]

func _generate_village_name() -> String:
	"""Generate a random village name"""
	var prefixes := ["Green", "Oak", "Stone", "River", "Hill", "Meadow", "Brook", "Elm"]
	var suffixes := ["ford", "shire", "dale", "wood", "field", "brook", "ham", "worth"]
	return prefixes[randi() % prefixes.size()] + suffixes[randi() % suffixes.size()]

# ============================================================================
# STEP 7: Terrain Growth
# ============================================================================

func _apply_terrain_growth() -> void:
	"""Apply terrain growth using the growth system"""
	# Update mountain growth direction in terrain
	var mountain_terrain := terrain_manager.get_terrain("mountains")
	if mountain_terrain:
		mountain_terrain.growth_direction_preference = mountain_growth_direction.normalized()
	
	# Apply growth
	GrowthSystem.apply_terrain_growth(
		point_data_array,
		terrain_manager.terrain_types,
		adjacency_map,
		terrain_growth_iterations
	)
	
	print("  Applied %d growth iterations" % terrain_growth_iterations)

# ============================================================================
# STEP 8: Region Detection
# ============================================================================

func _detect_regions() -> void:
	"""Detect and name regions"""
	regions = Region.detect_regions(point_data_array, terrain_manager.terrain_types)
	
	print("  Detected %d regions:" % regions.size())
	for region in regions:
		if region.size() >= 3:
			print("    - %s (%d cells)" % [region.region_name, region.size()])
			region_detected.emit(region)

# ============================================================================
# STEP 9: Path Generation
# ============================================================================

func _generate_paths() -> void:
	"""Generate paths between settlements"""
	path_data_array.clear()

	# Get all settlement indices
	var cities: Array[int] = []
	var villages: Array[int] = []

	for i in range(point_data_array.size()):
		match point_data_array[i].point_type:
			PointData.PointType.CITY:
				cities.append(i)
			PointData.PointType.VILLAGE:
				villages.append(i)

	# City to city highways
	for i in range(cities.size()):
		for j in range(i + 1, cities.size()):
			var path := _create_path_between(cities[i], cities[j], PathData.PathType.HIGHWAY)
			if path:
				path_data_array.append(path)

	# Villages to nearest city
	for village_idx in villages:
		var nearest_city := _find_nearest_settlement(village_idx, cities)
		if nearest_city != -1:
			var path := _create_path_between(village_idx, nearest_city, PathData.PathType.ROAD)
			if path:
				path_data_array.append(path)

	# Some village to village roads
	for village_idx in villages:
		if randf() < 0.3:  # 30% chance
			var nearest_village := _find_nearest_settlement(village_idx, villages)
			if nearest_village != -1 and nearest_village != village_idx:
				var path := _create_path_between(village_idx, nearest_village, PathData.PathType.ROAD)
				if path and not _path_exists(path):
					path_data_array.append(path)

	print("  Generated %d paths" % path_data_array.size())

func _create_path_between(from_idx: int, to_idx: int, path_type: PathData.PathType) -> PathData:
	"""Create a path between two points"""
	if from_idx < 0 or to_idx < 0:
		return null
	if from_idx >= point_data_array.size() or to_idx >= point_data_array.size():
		return null
	
	var from_pos := point_data_array[from_idx].position
	var to_pos := point_data_array[to_idx].position
	var voronoi_point := (from_pos + to_pos) / 2.0
	
	var path := PathData.new(from_idx, to_idx, voronoi_point, path_type)
	path.quality = randf_range(0.4, 0.8)
	return path

func _path_exists(new_path: PathData) -> bool:
	"""Check if a path already exists between two points"""
	for path in path_data_array:
		if (path.from_point_idx == new_path.from_point_idx and path.to_point_idx == new_path.to_point_idx) or \
		   (path.from_point_idx == new_path.to_point_idx and path.to_point_idx == new_path.from_point_idx):
			return true
	return false

func _find_nearest_settlement(from_idx: int, settlement_indices: Array[int]) -> int:
	"""Find nearest settlement from a point"""
	if settlement_indices.is_empty():
		return -1
	
	var from_pos := point_data_array[from_idx].position
	var nearest_idx := -1
	var nearest_dist := INF
	
	for idx in settlement_indices:
		if idx == from_idx:
			continue
		
		var dist := from_pos.distance_to(point_data_array[idx].position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_idx = idx
	
	return nearest_idx

# ============================================================================
# STEP 10: Shoreline Generation
# ============================================================================

func _generate_shorelines() -> void:
	"""Generate shoreline paths between water and land"""
	var shorelines := TerrainBlender.generate_shoreline_paths(
		point_data_array,
		adjacency_map,
		terrain_manager.terrain_types
	)
	
	print("  Generated %d shorelines" % shorelines.size())
	# Optionally add shorelines to path array for rendering
	# path_data_array.append_array(shorelines)

# ============================================================================
# STEP 11: Terrain Rendering
# ============================================================================

func _render_terrain() -> void:
	"""Render terrain to texture"""
	var width := int(map_size.x)
	var height := int(map_size.y)
	
	terrain_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	# Fill with base color
	terrain_image.fill(Color(0.6, 0.75, 0.45, 1.0))  # Default plains color
	
	print("  Rendering terrain texture %dx%d..." % [width, height])
	
	# Color each pixel based on nearest point (Voronoi coloring)
	for y in range(height):
		for x in range(width):
			var pos := Vector2(x, y)
			var nearest_idx := _find_nearest_point_index(pos)
			
			if nearest_idx != -1:
				var terrain_id := point_data_array[nearest_idx].terrain_type_id
				var color := terrain_manager.get_terrain_color(terrain_id)
				terrain_image.set_pixel(x, y, color)
	
	terrain_texture = ImageTexture.create_from_image(terrain_image)
	print("  Terrain texture rendered")

func _find_nearest_point_index(pos: Vector2) -> int:
	"""Find the nearest point index to a position"""
	var nearest_idx := -1
	var nearest_dist := INF
	
	for i in range(point_data_array.size()):
		var dist := pos.distance_squared_to(point_data_array[i].position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_idx = i
	
	return nearest_idx

# ============================================================================
# STEP 12: Interactive Elements
# ============================================================================

func _create_interactive_elements() -> void:
	"""Create interactive points and paths"""
	# Clear old interactive elements
	for point in interactive_points:
		if is_instance_valid(point):
			point.queue_free()
	for path in interactive_paths:
		if is_instance_valid(path):
			path.queue_free()
	
	interactive_points.clear()
	interactive_paths.clear()
	
	# Create interactive points
	for i in range(point_data_array.size()):
		var point_data := point_data_array[i]
		var interactive_point := InteractivePoint.new()
		interactive_point.global_position = point_data.position
		
		# Convert to legacy PointType for compatibility with InteractivePoint
		var legacy_type := _convert_to_legacy_type(point_data)
		interactive_point.setup(i, legacy_type, self)
		interactive_point.point_description = point_data.description
		
		# Connect signals
		interactive_point.point_hovered.connect(_on_point_hovered)
		interactive_point.point_unhovered.connect(_on_point_unhovered)
		
		add_child(interactive_point)
		interactive_points.append(interactive_point)
	
	# Create interactive paths
	for path_data in path_data_array:
		_create_interactive_path(path_data)
	
	print("  Created %d interactive points and %d paths" % [
		interactive_points.size(),
		interactive_paths.size()
	])

func _create_interactive_path(path_data: PathData) -> void:
	"""Create an InteractivePath from PathData"""
	var from_idx := path_data.from_point_idx
	var to_idx := path_data.to_point_idx
	
	if from_idx < 0 or to_idx < 0:
		return
	if from_idx >= interactive_points.size() or to_idx >= interactive_points.size():
		return
	
	var from_point := interactive_points[from_idx]
	var to_point := interactive_points[to_idx]
	
	if from_point == null or to_point == null:
		return
	
	var interactive_path := InteractivePath.new()
	
	# Create connection data for compatibility
	var conn_data := {
		"idx1": from_idx,
		"idx2": to_idx,
		"edge_type": path_data.path_type,
		"path_data": path_data
	}
	
	interactive_path.setup(from_point, to_point, path_data.voronoi_point, conn_data)
	add_child(interactive_path)
	interactive_paths.append(interactive_path)

func _convert_to_legacy_type(point_data: PointData) -> int:
	"""Convert PointData type to legacy enum for InteractivePoint"""
	match point_data.point_type:
		PointData.PointType.CITY:
			return PointType.CITY
		PointData.PointType.VILLAGE:
			return PointType.VILLAGE
		PointData.PointType.NATURE:
			# Determine from terrain
			match point_data.terrain_type_id:
				"water_shallow", "water_deep":
					return PointType.WATER
				"mountains":
					return PointType.MOUNTAIN
				"forest":
					return PointType.FOREST
				_:
					return PointType.VILLAGE  # Default appearance
	
	return PointType.VILLAGE

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_point_hovered(point_index: int) -> void:
	"""Handle point hover"""
	pass

func _on_point_unhovered(point_index: int) -> void:
	"""Handle point unhover"""
	pass

# ============================================================================
# RENDERING
# ============================================================================

func _draw() -> void:
	"""Draw the map"""
	# Draw terrain texture
	if terrain_texture:
		draw_texture(terrain_texture, Vector2.ZERO)
	
	# Draw voronoi edges if debug enabled
	if show_voronoi_edges:
		_draw_voronoi_debug()
	
	# Draw region names
	if show_region_names:
		_draw_region_names()

func _draw_voronoi_debug() -> void:
	"""Draw voronoi cell edges for debugging"""
	for i in range(point_data_array.size()):
		var neighbors: Array = adjacency_map.get(i, []) as Array
		for neighbor_idx in neighbors:
			if neighbor_idx > i:  # Draw each edge only once
				var from := point_data_array[i].position
				var to := point_data_array[neighbor_idx].position
				draw_line(from, to, Color(0.3, 0.3, 0.3, 0.5), 1.0)

func _draw_region_names() -> void:
	"""Draw region names at their centers"""
	for region in regions:
		if region.size() >= 5:  # Only show larger regions
			# Draw a circle marker at region center
			draw_circle(region.center, 8.0, Color(1, 1, 1, 0.7))
			draw_circle(region.center, 6.0, Color(0, 0, 0, 0.5))

# ============================================================================
# UTILITY
# ============================================================================

func _clear_map() -> void:
	"""Clear all map data"""
	point_data_array.clear()
	path_data_array.clear()
	regions.clear()
	delaunay_triangles.clear()
	voronoi_cells.clear()
	adjacency_map.clear()
	
	for point in interactive_points:
		if is_instance_valid(point):
			point.queue_free()
	for path in interactive_paths:
		if is_instance_valid(path):
			path.queue_free()
	
	interactive_points.clear()
	interactive_paths.clear()
	
	if terrain_texture:
		terrain_texture = null
	if terrain_image:
		terrain_image = null

# ============================================================================
# PUBLIC API
# ============================================================================

func get_point_data(index: int) -> PointData:
	"""Get point data by index"""
	if index >= 0 and index < point_data_array.size():
		return point_data_array[index]
	return null

func get_region_at_point(point_index: int) -> Region:
	"""Get the region containing a point"""
	for region in regions:
		if region.voronoi_indices.has(point_index):
			return region
	return null

func set_point_loyalty(point_index: int, player_id: int, loyalty_value: float) -> void:
	"""Set loyalty for a point"""
	var point_data := get_point_data(point_index)
	if point_data:
		point_data.set_loyalty(player_id, loyalty_value)
		queue_redraw()

func get_all_cities() -> Array[int]:
	"""Get indices of all cities"""
	var cities: Array[int] = []
	for i in range(point_data_array.size()):
		if point_data_array[i].point_type == PointData.PointType.CITY:
			cities.append(i)
	return cities

func get_all_villages() -> Array[int]:
	"""Get indices of all villages"""
	var villages: Array[int] = []
	for i in range(point_data_array.size()):
		if point_data_array[i].point_type == PointData.PointType.VILLAGE:
			villages.append(i)
	return villages

# ============================================================================
# LEGACY COMPATIBILITY
# ============================================================================

# Define legacy PointType enum for compatibility with InteractivePoint
enum PointType { CITY, VILLAGE, WATER, MOUNTAIN, FOREST }

# Legacy property accessors for backward compatibility
var map_points: Array:
	get:
		var points: Array = []
		for pd in point_data_array:
			points.append(pd.position)
		return points

var point_names: Array:
	get:
		var names: Array = []
		for pd in point_data_array:
			names.append(pd.custom_name)
		return names

var map_connections: Array:
	get:
		var connections: Array = []
		for path in path_data_array:
			connections.append({
				"idx1": path.from_point_idx,
				"idx2": path.to_point_idx,
				"edge_type": path.path_type
			})
		return connections
