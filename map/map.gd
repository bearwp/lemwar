
extends Node2D
class_name GameMap

enum PointType { CITY, VILLAGE, WATER, MOUNTAIN }
enum EdgeType { PATH, RIVER, FOREST }

var map_points: Array[Vector2] = []
var point_types: Array[int] = []
var point_properties: Array[Dictionary] = []  # New: for shoreline flags, etc.
var boundary_point_indices: Array[int] = []  # Track which points are artificial boundary
var map_connections: Array[Dictionary] = []  # Now stores {idx1, idx2, voronoi_point, edge_type}
var voronoi_edges: Array[Dictionary] = []  # Stores all Voronoi edges for debug
var delaunay_adjacency: Dictionary = {}  # Cache of neighbor relationships
var noise: FastNoiseLite

# New parameters for new features
var num_rivers := 3
var river_branch_chance := 0.25
var river_max_length := 15
var forest_coverage := 0.15
var forest_clusters := 5

# Terrain cache for fast rendering
var terrain_cache: Image
var terrain_colors_cache: Image
var cache_scale := 4  # Cache resolution: map_size / cache_scale

# Simple configuration
var map_size := Vector2(600, 600)
var num_points := 150
var num_cities := 4
var num_mountains := 2
var num_water_sources := 4
var water_expansion_chance := 0.25
var min_distance := 60.0
var boundary_padding := 100.0
var boundary_spacing := 100.0
var show_voronoi_debug := false
var allow_coastal_connections := true
var max_water_connection_distance := 100.0  # New: Maximum range for water connections
var village_deletion_chance := 0.0  # Random chance to delete villages (0.0-1.0)
var settlement_connection_deletion_chance := 0.0  # Random chance to delete city/village connections (0.0-1.0)

func _ready() -> void:
	_setup_noise()
	_generate_map()

# No longer auto-generate - wait for trigger

func generate_new_map() -> void:
	"""Public method to trigger map generation"""
	_generate_map()

func _on_toggle_voronoi_debug() -> void:
	show_voronoi_debug = not show_voronoi_debug
	print("Voronoi debug: ", show_voronoi_debug)
	queue_redraw()

func _setup_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.01
	noise.fractal_octaves = 3

func _generate_map() -> void:
	# Clear old cache and data
	terrain_cache = null
	terrain_colors_cache = null
	point_types.clear()
	map_connections.clear()
	voronoi_edges.clear()
	delaunay_adjacency.clear()
	boundary_point_indices.clear()
	
	# 1. Generate interior points
	map_points = _generate_poisson_points(min_distance, num_points)

	# 2. Add boundary ring
	_add_boundary_ring()

	# 3. Build adjacency graph FIRST (needed for water expansion)
	_build_adjacency_graph()

	# 4. Assign terrain types in order (now water expansion will work)
	_assign_terrain_types()

	# 5. Delete random villages (AFTER water expansion in _assign_terrain_types)
	_delete_random_villages()

	# 6. Build connections with proper Voronoi edges
	_build_connections()

	# 7. Ensure all non-mountain points are connected
	_ensure_connectivity()

	# Cache terrain and redraw
	_cache_terrain()
	queue_redraw()

func _delete_random_villages() -> void:
	if village_deletion_chance <= 0.0:
		return
	
	var villages_to_delete = []
	for i in range(map_points.size()):
		if point_types[i] == PointType.VILLAGE and not boundary_point_indices.has(i):
			if randf() < village_deletion_chance:
				villages_to_delete.append(i)
	
	for village_idx in villages_to_delete:
		point_types[village_idx] = PointType.WATER
	
	if villages_to_delete.size() > 0:
		print("Deleted %d random villages" % villages_to_delete.size())

func _generate_poisson_points(min_dist: float, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts = 0

	while points.size() < count and attempts < count * 100:
		attempts += 1
		var new_point = Vector2(randf() * map_size.x, randf() * map_size.y)

		var valid = true
		for point in points:
			if new_point.distance_to(point) < min_dist:
				valid = false
				break

		if valid:
			points.append(new_point)

	return points

func _add_boundary_ring() -> void:
	boundary_point_indices.clear()
	var start_idx = map_points.size()

	# Top edge
	var x = -boundary_padding
	while x <= map_size.x + boundary_padding:
		map_points.append(Vector2(x, -boundary_padding))
		boundary_point_indices.append(map_points.size() - 1)
		x += boundary_spacing

	# Bottom edge
	x = -boundary_padding
	while x <= map_size.x + boundary_padding:
		map_points.append(Vector2(x, map_size.y + boundary_padding))
		boundary_point_indices.append(map_points.size() - 1)
		x += boundary_spacing

	# Left edge (skip corners to avoid duplicates)
	var y = 0.0
	while y <= map_size.y:
		map_points.append(Vector2(-boundary_padding, y))
		boundary_point_indices.append(map_points.size() - 1)
		y += boundary_spacing

	# Right edge (skip corners to avoid duplicates)
	y = 0.0
	while y <= map_size.y:
		map_points.append(Vector2(map_size.x + boundary_padding, y))
		boundary_point_indices.append(map_points.size() - 1)
		y += boundary_spacing

	print("Added %d boundary points" % boundary_point_indices.size())

func _assign_terrain_types() -> void:
	point_types.resize(map_points.size())

	# Mark all boundary points as water
	for idx in boundary_point_indices:
		point_types[idx] = PointType.WATER

	# Get indices of interior points only
	var interior_indices = []
	for i in range(map_points.size()):
		if not boundary_point_indices.has(i):
			interior_indices.append(i)

	interior_indices.shuffle()

	# Border water (ocean) - within map bounds
	var border_threshold = 60.0
	for i in interior_indices:
		var pos = map_points[i]
		if pos.x < border_threshold or pos.x > map_size.x - border_threshold or \
		pos.y < border_threshold or pos.y > map_size.y - border_threshold:
			point_types[i] = PointType.WATER

	# Filter out assigned water from available indices
	var available_indices = []
	for i in interior_indices:
		if point_types[i] != PointType.WATER:
			available_indices.append(i)

	available_indices.shuffle()

	# Mountains (assign first so water can't spread there)
	var idx = 0
	for i in range(min(num_mountains, available_indices.size())):
		point_types[available_indices[idx]] = PointType.MOUNTAIN
		idx += 1

	# Cities (assign second, water can't convert these)
	for i in range(min(num_cities, available_indices.size() - idx)):
		point_types[available_indices[idx]] = PointType.CITY
		idx += 1

	# Villages (everything else - these CAN become water)
	while idx < available_indices.size():
		point_types[available_indices[idx]] = PointType.VILLAGE
		idx += 1

	# Create initial water sources
	_create_water_sources()

	# Expand water recursively from sources
	_expand_water_recursive()

func _create_water_sources() -> void:
	# Find all village points to pick random sources from
	var village_indices = []
	for i in range(map_points.size()):
		if point_types[i] == PointType.VILLAGE and not boundary_point_indices.has(i):
			village_indices.append(i)

	village_indices.shuffle()

	# Convert N random villages to water sources
	for i in range(min(num_water_sources, village_indices.size())):
		point_types[village_indices[i]] = PointType.WATER

func _expand_water_recursive() -> void:
	# Find all current water points and try to expand each one
	var water_indices = []
	for i in range(map_points.size()):
		if point_types[i] == PointType.WATER and not boundary_point_indices.has(i):
			water_indices.append(i)

	# Try to expand from each water point
	for water_idx in water_indices:
		_try_expand_water_from(water_idx)

func _try_expand_water_from(water_idx: int) -> void:
	# Get neighbors of this water point
	var neighbors = delaunay_adjacency.get(water_idx, [])

	for neighbor_idx in neighbors:
		# Skip if already water or is boundary
		if point_types[neighbor_idx] == PointType.WATER or boundary_point_indices.has(neighbor_idx):
			continue

		# Only convert villages to water (never cities or mountains)
		if point_types[neighbor_idx] != PointType.VILLAGE:
			continue

		# Random chance to convert this village to water
		if randf() < water_expansion_chance:
			point_types[neighbor_idx] = PointType.WATER
			# Recursively try to expand from this new water point
			_try_expand_water_from(neighbor_idx)

func _build_adjacency_graph() -> void:
	"""Build Delaunay adjacency before terrain assignment"""
	if map_points.size() < 3:
		return

	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2(-boundary_padding, -boundary_padding),
	map_size + Vector2(boundary_padding * 2, boundary_padding * 2)))
	for point in map_points:
		delaunay.add_point(point)
	var triangles = delaunay.triangulate()
	delaunay.remove_border_triangles(triangles)

	# Initialize adjacency
	delaunay_adjacency.clear()
	for i in range(map_points.size()):
		delaunay_adjacency[i] = []

	for triangle in triangles:
		var idx_a = map_points.find(triangle.a)
		var idx_b = map_points.find(triangle.b)
		var idx_c = map_points.find(triangle.c)

		if idx_a == -1 or idx_b == -1 or idx_c == -1:
			continue

		# Build adjacency graph
		if not delaunay_adjacency[idx_a].has(idx_b):
			delaunay_adjacency[idx_a].append(idx_b)
		if not delaunay_adjacency[idx_b].has(idx_a):
			delaunay_adjacency[idx_b].append(idx_a)
		if not delaunay_adjacency[idx_b].has(idx_c):
			delaunay_adjacency[idx_b].append(idx_c)
		if not delaunay_adjacency[idx_c].has(idx_b):
			delaunay_adjacency[idx_c].append(idx_b)
		if not delaunay_adjacency[idx_c].has(idx_a):
			delaunay_adjacency[idx_c].append(idx_a)
		if not delaunay_adjacency[idx_a].has(idx_c):
			delaunay_adjacency[idx_a].append(idx_c)

	print("Built adjacency graph with %d nodes" % delaunay_adjacency.size())

func _build_connections() -> void:
	if map_points.size() < 3:
		return

	# Get Delaunay triangulation (includes boundary points)
	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2(-boundary_padding, -boundary_padding),
	map_size + Vector2(boundary_padding * 2, boundary_padding * 2)))
	for point in map_points:
		delaunay.add_point(point)
	var triangles = delaunay.triangulate()
	delaunay.remove_border_triangles(triangles)

	# Build edge-to-triangles mapping and calculate circumcenters
	var edge_triangles = {}
	var triangle_circumcenters = {}

	for triangle in triangles:
		var idx_a = map_points.find(triangle.a)
		var idx_b = map_points.find(triangle.b)
		var idx_c = map_points.find(triangle.c)

		if idx_a == -1 or idx_b == -1 or idx_c == -1:
			continue

		# Calculate circumcenter for this triangle
		var circumcenter = _calculate_circumcenter(triangle.a, triangle.b, triangle.c)
		triangle_circumcenters[triangle] = circumcenter

		# Map each edge to this triangle
		_add_triangle_to_edge(edge_triangles, idx_a, idx_b, triangle)
		_add_triangle_to_edge(edge_triangles, idx_b, idx_c, triangle)
		_add_triangle_to_edge(edge_triangles, idx_c, idx_a, triangle)

	# Build Voronoi edges from circumcenters
	voronoi_edges.clear()
	map_connections.clear()

	for edge_key in edge_triangles.keys():
		var parts = edge_key.split("_")
		var idx1 = int(parts[0])
		var idx2 = int(parts[1])
		var triangles_list = edge_triangles[edge_key]

		# Skip if both points are boundary points (off-map connection)
		var idx1_is_boundary = boundary_point_indices.has(idx1)
		var idx2_is_boundary = boundary_point_indices.has(idx2)

		if idx1_is_boundary and idx2_is_boundary:
			continue

		var type1 = point_types[idx1]
		var type2 = point_types[idx2]

		# Calculate Voronoi edge
		var voronoi_segment = PackedVector2Array()
		var voronoi_midpoint = Vector2.ZERO

		if triangles_list.size() >= 2:
			# Connect circumcenters
			var c1 = triangle_circumcenters[triangles_list[0]]
			var c2 = triangle_circumcenters[triangles_list[1]]

			# Clip to map bounds
			var clipped = _clip_line_to_rect(c1, c2, Rect2(Vector2.ZERO, map_size))
			if clipped.size() >= 2:
				voronoi_segment.append(clipped[0])
				voronoi_segment.append(clipped[1])
				voronoi_midpoint = (clipped[0] + clipped[1]) * 0.5
		elif triangles_list.size() == 1:
			# Single triangle edge
			var c1 = triangle_circumcenters[triangles_list[0]]
			var edge_dir = (map_points[idx2] - map_points[idx1]).normalized()
			var perpendicular = Vector2(-edge_dir.y, edge_dir.x)
			var c2 = c1 + perpendicular * 500.0

			var clipped = _clip_line_to_rect(c1, c2, Rect2(Vector2.ZERO, map_size))
			if clipped.size() >= 2:
				voronoi_segment.append(clipped[0])
				voronoi_segment.append(clipped[1])
				voronoi_midpoint = (clipped[0] + clipped[1]) * 0.5

		# Store Voronoi edge for debug visualization (including mountains)
		if voronoi_segment.size() >= 2:
			voronoi_edges.append({
				"idx1": idx1,
				"idx2": idx2,
				"segment": voronoi_segment,
				"type1": type1,
				"type2": type2
			})

		# Decision: Should we connect these two points?
		var should_connect = false

		# Rule 1: Mountains never connect to anything
		if type1 == PointType.MOUNTAIN or type2 == PointType.MOUNTAIN:
			should_connect = false

			# Rule 2: Settlements (cities/villages) always connect to each other
		elif (type1 == PointType.CITY or type1 == PointType.VILLAGE) and \
		(type2 == PointType.CITY or type2 == PointType.VILLAGE):
			should_connect = true

		# Rule 3: Water to water connects (without distance restriction)
		elif type1 == PointType.WATER and type2 == PointType.WATER:
			should_connect = true

		# Rule 4: Coastal connections (water touching land) - with distance limit
		elif allow_coastal_connections:
			if (type1 == PointType.WATER and (type2 == PointType.CITY or type2 == PointType.VILLAGE)) or \
			   (type2 == PointType.WATER and (type1 == PointType.CITY or type1 == PointType.VILLAGE)):
				var distance = map_points[idx1].distance_to(map_points[idx2])
				print("Water connection distance: %.1f (limit: %.1f)" % [distance, max_water_connection_distance])
				if distance <= max_water_connection_distance:
					should_connect = true
					print("  -> ALLOWED")
				else:
					print("  -> REJECTED")

		# Add connection if valid and we have a valid voronoi midpoint
		if should_connect and voronoi_segment.size() >= 2:
			map_connections.append({
				"idx1": idx1,
				"idx2": idx2,
				"voronoi_point": voronoi_midpoint
			})

	# Delete random settlement connections
	_delete_random_settlement_connections()

func _delete_random_settlement_connections() -> void:
	if settlement_connection_deletion_chance <= 0.0:
		return
	
	var connections_to_remove = []
	
	for i in range(map_connections.size()):
		var connection = map_connections[i]
		var idx1 = connection.idx1
		var idx2 = connection.idx2
		var type1 = point_types[idx1]
		var type2 = point_types[idx2]
		
		# Only delete connections between settlements (cities/villages)
		var is_settlement_connection = (type1 == PointType.CITY or type1 == PointType.VILLAGE) and \
										(type2 == PointType.CITY or type2 == PointType.VILLAGE)
		
		if is_settlement_connection and randf() < settlement_connection_deletion_chance:
			connections_to_remove.append(i)
	
	# Remove in reverse order to maintain correct indices
	for i in range(connections_to_remove.size() - 1, -1, -1):
		map_connections.remove_at(connections_to_remove[i])
	
	if connections_to_remove.size() > 0:
		print("Deleted %d random settlement connections" % connections_to_remove.size())

func _cache_terrain() -> void:
	print("Caching terrain...")
	var start_time = Time.get_ticks_msec()

	var cache_width = int(map_size.x / cache_scale)
	var cache_height = int(map_size.y / cache_scale)

	# Create images for caching
	terrain_cache = Image.create(cache_width, cache_height, false, Image.FORMAT_RGB8)
	terrain_colors_cache = Image.create(cache_width, cache_height, false, Image.FORMAT_RGBA8)

	# Pre-calculate nearest point and color for each cache cell
	for cy in range(cache_height):
		for cx in range(cache_width):
			var world_pos = Vector2(cx * cache_scale, cy * cache_scale)
			var nearest_idx = _find_nearest_point(world_pos)
			var base_color = _get_terrain_color(world_pos, point_types[nearest_idx])

			# Add noise variation
			var noise_val = noise.get_noise_2d(world_pos.x, world_pos.y) * 0.15
			var final_color = base_color.lerp(Color.WHITE if noise_val > 0 else Color.BLACK, abs(noise_val) * 0.5)

			terrain_colors_cache.set_pixel(cx, cy, final_color)

	var end_time = Time.get_ticks_msec()
	print("Terrain cached in %d ms" % (end_time - start_time))

func _clip_line_to_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> PackedVector2Array:
	# Liang-Barsky line clipping algorithm
	var result = PackedVector2Array()

	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y

	var dx = x2 - x1
	var dy = y2 - y1

	var t_min = 0.0
	var t_max = 1.0

	# Check against all four edges
	var p = [-dx, dx, -dy, dy]
	var q = [x1 - rect.position.x,
			rect.position.x + rect.size.x - x1,
			y1 - rect.position.y,
			rect.position.y + rect.size.y - y1]

	for i in range(4):
		if abs(p[i]) < 0.0001:
			# Line is parallel to this edge
			if q[i] < 0:
				return result  # Line is outside
		else:
			var t = q[i] / p[i]
			if p[i] < 0:
				t_min = max(t_min, t)
			else:
				t_max = min(t_max, t)

	if t_min > t_max:
		return result  # No intersection

	# Calculate clipped points
	result.append(Vector2(x1 + t_min * dx, y1 + t_min * dy))
	result.append(Vector2(x1 + t_max * dx, y1 + t_max * dy))

	return result

func _calculate_circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	# Calculate circumcenter of triangle ABC
	var d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if abs(d) < 0.0001:
		# Degenerate triangle, return centroid
		return (a + b + c) / 3.0

	var ux = ((a.x * a.x + a.y * a.y) * (b.y - c.y) +
	(b.x * b.x + b.y * b.y) * (c.y - a.y) +
	(c.x * c.x + c.y * c.y) * (a.y - b.y)) / d

	var uy = ((a.x * a.x + a.y * a.y) * (c.x - b.x) +
	(b.x * b.x + b.y * b.y) * (a.x - c.x) +
	(c.x * c.x + c.y * c.y) * (b.x - a.x)) / d

	return Vector2(ux, uy)

func _add_triangle_to_edge(dict: Dictionary, i1: int, i2: int, triangle) -> void:
	var key = "%d_%d" % [min(i1, i2), max(i1, i2)]
	if not dict.has(key):
		dict[key] = []
	dict[key].append(triangle)

func _ensure_connectivity() -> void:
	# Get all non-mountain, non-boundary points
	var all_points = []
	for i in range(map_points.size()):
		if point_types[i] != PointType.MOUNTAIN and not boundary_point_indices.has(i):
			all_points.append(i)

	if all_points.size() < 2:
		return

	# Find connected components
	var visited = {}
	var components = []

	for idx in all_points:
		if not visited.has(idx):
			var component = []
			_dfs(idx, visited, component)
			components.append(component)

	print("Found %d components" % components.size())

	# Connect all components
	if components.size() > 1:
		for i in range(components.size() - 1):
			var comp_a = components[i]
			var comp_b = components[i + 1]

			# Find closest pair between components
			var best_dist = INF
			var best_pair = []

			for a_idx in comp_a:
				for b_idx in comp_b:
					var dist = map_points[a_idx].distance_to(map_points[b_idx])
					if dist < best_dist:
						best_dist = dist
						best_pair = [a_idx, b_idx]

			if best_pair.size() == 2:
				var midpoint = (map_points[best_pair[0]] + map_points[best_pair[1]]) * 0.5
				map_connections.append({
					"idx1": best_pair[0],
					"idx2": best_pair[1],
					"voronoi_point": midpoint
				})
				print("Connected component %d to %d (dist: %.1f)" % [i, i+1, best_dist])

func _dfs(node: int, visited: Dictionary, component: Array) -> void:
	visited[node] = true
	component.append(node)

	for connection in map_connections:
		var neighbor = -1
		if connection.idx1 == node:
			neighbor = connection.idx2
		elif connection.idx2 == node:
			neighbor = connection.idx1

		if neighbor != -1 and not visited.has(neighbor) and not boundary_point_indices.has(neighbor):
			_dfs(neighbor, visited, component)

func _draw() -> void:
	_draw_terrain_cached()
	if show_voronoi_debug:
		_draw_voronoi_borders()
	_draw_connections()
	_draw_points()

func _draw_terrain_cached() -> void:
	# Draw using pre-calculated cache - much faster!
	if terrain_colors_cache == null:
		return

	var cache_width = terrain_colors_cache.get_width()
	var cache_height = terrain_colors_cache.get_height()

	for cy in range(cache_height):
		for cx in range(cache_width):
			var color = terrain_colors_cache.get_pixel(cx, cy)
			var world_x = cx * cache_scale
			var world_y = cy * cache_scale
			draw_rect(Rect2(world_x, world_y, cache_scale, cache_scale), color)

func _draw_voronoi_borders() -> void:
	# Draw all calculated Voronoi edges with color coding
	for edge_data in voronoi_edges:
		var segment = edge_data.segment
		if segment.size() >= 2:
			var type1 = edge_data.type1
			var type2 = edge_data.type2

			# Color code based on what the edge separates
			var color = Color.RED
			if type1 == PointType.MOUNTAIN or type2 == PointType.MOUNTAIN:
				color = Color.DARK_GRAY  # Mountain borders
			elif type1 == type2:
				color = Color.YELLOW  # Same terrain (these connect)
			else:
				color = Color.RED  # Different terrains

			draw_line(segment[0], segment[1], color, 2.0)

func _find_nearest_point(pos: Vector2) -> int:
	var nearest = 0
	var min_dist = INF
	for i in range(map_points.size()):
		var dist = pos.distance_to(map_points[i])
		if dist < min_dist:
			min_dist = dist
			nearest = i
	return nearest

func _get_terrain_color(pos: Vector2, type: int) -> Color:
	match type:
		PointType.WATER:
			return Color(0.25, 0.42, 0.62).lerp(Color(0.15, 0.28, 0.45),
			(noise.get_noise_2d(pos.x * 0.5, pos.y * 0.5) + 1.0) * 0.25)
		PointType.CITY, PointType.VILLAGE:
			var base = Color(0.48, 0.67, 0.29)
			var noise_val = noise.get_noise_2d(pos.x, pos.y)
			return base.lerp(Color(0.58, 0.75, 0.35) if noise_val > 0 else Color(0.36, 0.51, 0.25),
			abs(noise_val) * 0.4)
		PointType.MOUNTAIN:
			var base = Color(0.45, 0.4, 0.35)
			var noise_val = noise.get_noise_2d(pos.x * 0.5, pos.y * 0.5)
			if noise_val > 0.4:
				return base.lerp(Color(0.85, 0.9, 0.95), (noise_val - 0.4) * 1.5)
			elif noise_val < -0.3:
				return base.lerp(Color(0.3, 0.25, 0.2), (-noise_val - 0.3) * 1.5)
			return base
	return Color.WHITE

func _draw_connections() -> void:
	for connection in map_connections:
		var idx1 = connection.idx1
		var idx2 = connection.idx2
		var voronoi_point = connection.voronoi_point
		var p1 = map_points[idx1]
		var p2 = map_points[idx2]
		var type1 = point_types[idx1]
		var type2 = point_types[idx2]

		if type1 == PointType.WATER or type2 == PointType.WATER:
			# Draw two-segment dashed line through Voronoi point
			_draw_dashed_line(p1, voronoi_point, Color(0.35, 0.5, 0.65, 0.6), 2.5, 8.0, 6.0)
			_draw_dashed_line(voronoi_point, p2, Color(0.35, 0.5, 0.65, 0.6), 2.5, 8.0, 6.0)
		elif type1 == PointType.CITY and type2 == PointType.CITY:
			# Highway through Voronoi point
			draw_line(p1, voronoi_point, Color(0.4, 0.25, 0.15, 0.7), 5.5)
			draw_line(voronoi_point, p2, Color(0.4, 0.25, 0.15, 0.7), 5.5)
		else:
			# Regular road through Voronoi point
			draw_line(p1, voronoi_point, Color(0.63, 0.38, 0.15, 0.7), 3.5)
			draw_line(voronoi_point, p2, Color(0.63, 0.38, 0.15, 0.7), 3.5)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var dir = (to - from).normalized()
	var dist = from.distance_to(to)
	var current = 0.0
	while current < dist:
		var start = from + dir * current
		var end = from + dir * min(current + dash, dist)
		draw_line(start, end, color, width)
		current += dash + gap

func _draw_points() -> void:
	# Only draw non-boundary points
	for i in range(map_points.size()):
		if boundary_point_indices.has(i):
			continue

		var pos = map_points[i]
		match point_types[i]:
			PointType.CITY:
				draw_circle(pos, 11, Color(0.25, 0.2, 0.2))
				draw_circle(pos, 9, Color(0.8, 0.35, 0.3))
				draw_circle(pos, 6, Color(0.95, 0.55, 0.45))
			PointType.VILLAGE:
				draw_circle(pos, 5, Color(0.4, 0.35, 0.3))
				draw_circle(pos, 3, Color(0.65, 0.6, 0.55))
			PointType.WATER:
				draw_circle(pos, 7, Color(0.15, 0.28, 0.45))
				draw_circle(pos, 5, Color(0.25, 0.42, 0.62))
				draw_circle(pos, 3, Color(0.45, 0.60, 0.78))
			PointType.MOUNTAIN:
				var pts = PackedVector2Array([
				pos + Vector2(0, -9), pos + Vector2(-8, 5), pos + Vector2(8, 5)])
				draw_colored_polygon(pts, Color(0.4, 0.35, 0.3))
				pts = PackedVector2Array([
				pos + Vector2(0, -7), pos + Vector2(-4, 2), pos + Vector2(4, 2)])
				draw_colored_polygon(pts, Color(0.6, 0.55, 0.5))
