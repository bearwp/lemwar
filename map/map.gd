extends Node2D
class_name GameMap

enum PointType { CITY, VILLAGE, WATER, MOUNTAIN }

var map_points: Array[Vector2] = []
var point_types: Array[int] = []
var map_connections: Array[Dictionary] = []  # Stores {idx1, idx2, voronoi_point}
var voronoi_edges: Array[Dictionary] = []  # Stores all Voronoi edges for debug
var noise: FastNoiseLite

# Simple configuration
var map_size := Vector2(600, 600)
var num_points := 60
var num_cities := 8
var num_villages := 15
var num_mountains := 3
var num_water_clusters := 3
var points_per_water_cluster := 5
var min_distance := 40.0
var show_voronoi_debug := false  # Debug toggle

func _ready() -> void:
	_setup_noise()
	_generate_map()
	queue_redraw()

	# Add debug toggle button
	var toggle_button = Button.new()
	add_child(toggle_button)
	toggle_button.text = "Toggle Voronoi Debug"
	toggle_button.position = Vector2(20, 20)
	toggle_button.pressed.connect(_on_toggle_voronoi_debug)

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
	# 1. Generate points
	map_points = _generate_poisson_points(min_distance, num_points)

	# 2. Assign types (guaranteed counts)
	_assign_point_types()

	# 3. Build connections with proper Voronoi edges
	_build_connections()

	# 4. Ensure all non-mountain points are connected
	_ensure_connectivity()

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

func _assign_point_types() -> void:
	point_types.resize(map_points.size())
	var indices = range(map_points.size())
	indices.shuffle()

	var idx = 0

	# Border water (ocean)
	var border_threshold = 60.0
	for i in range(map_points.size()):
		var pos = map_points[i]
		if pos.x < border_threshold or pos.x > map_size.x - border_threshold or \
		pos.y < border_threshold or pos.y > map_size.y - border_threshold:
			point_types[i] = PointType.WATER
			indices.erase(i)

	# Interior water clusters
	var water_assigned = _assign_water_clusters(indices)
	for i in water_assigned:
		indices.erase(i)

	# Mountains
	for i in range(min(num_mountains, indices.size())):
		point_types[indices[idx]] = PointType.MOUNTAIN
		idx += 1

	# Cities
	for i in range(min(num_cities, indices.size() - idx)):
		point_types[indices[idx]] = PointType.CITY
		idx += 1

	# Villages (everything else)
	while idx < indices.size():
		point_types[indices[idx]] = PointType.VILLAGE
		idx += 1

func _assign_water_clusters(available_indices: Array) -> Array:
	var assigned = []
	var border_threshold = 60.0

	# Filter for interior points only
	var interior = []
	for i in available_indices:
		var pos = map_points[i]
		if pos.x > border_threshold and pos.x < map_size.x - border_threshold and \
		pos.y > border_threshold and pos.y < map_size.y - border_threshold:
			interior.append(i)

	interior.shuffle()

	# Create clusters
	for cluster_num in range(num_water_clusters):
		if interior.is_empty():
			break

		# Pick seed
		var seed_idx = interior.pop_front()
		point_types[seed_idx] = PointType.WATER
		assigned.append(seed_idx)

		# Find closest neighbors
		var candidates = []
		for i in interior:
			var dist = map_points[seed_idx].distance_to(map_points[i])
			candidates.append([i, dist])

		candidates.sort_custom(func(a, b): return a[1] < b[1])

		# Add neighbors to cluster
		for j in range(min(points_per_water_cluster - 1, candidates.size())):
			var idx = candidates[j][0]
			point_types[idx] = PointType.WATER
			assigned.append(idx)
			interior.erase(idx)

	return assigned

func _build_connections() -> void:
	if map_points.size() < 3:
		return

	# Get Delaunay triangulation
	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2.ZERO, map_size))
	for point in map_points:
		delaunay.add_point(point)
	var triangles = delaunay.triangulate()
	delaunay.remove_border_triangles(triangles)

	# Build edge-to-triangles mapping and calculate circumcenters
	var edge_triangles = {}  # Maps edge_key -> [triangle1, triangle2, ...]
	var triangle_circumcenters = {}  # Maps triangle -> circumcenter

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

		var type1 = point_types[idx1]
		var type2 = point_types[idx2]

		# Skip mountains
		if type1 == PointType.MOUNTAIN or type2 == PointType.MOUNTAIN:
			continue

		# Calculate Voronoi edge
		var voronoi_segment = PackedVector2Array()
		var voronoi_midpoint = Vector2.ZERO

		if triangles_list.size() == 2:
			# Internal edge - connect two circumcenters
			var c1 = triangle_circumcenters[triangles_list[0]]
			var c2 = triangle_circumcenters[triangles_list[1]]
			voronoi_segment.append(c1)
			voronoi_segment.append(c2)
			voronoi_midpoint = (c1 + c2) * 0.5
		elif triangles_list.size() == 1:
			# Border edge - extend from circumcenter perpendicular to edge
			var c1 = triangle_circumcenters[triangles_list[0]]
			var edge_midpoint = (map_points[idx1] + map_points[idx2]) * 0.5
			var edge_dir = (map_points[idx2] - map_points[idx1]).normalized()
			var perpendicular = Vector2(-edge_dir.y, edge_dir.x)

			# Extend outward from circumcenter
			var extension = perpendicular * 1000.0  # Large value
			var far_point = c1 + extension

			# Clip to map bounds
			far_point = _clip_to_bounds(far_point)

			voronoi_segment.append(c1)
			voronoi_segment.append(far_point)
			voronoi_midpoint = (c1 + far_point) * 0.5

		# Store Voronoi edge for debug visualization
		voronoi_edges.append({
			"idx1": idx1,
			"idx2": idx2,
			"segment": voronoi_segment
		})

		# Validate and store connection
		if voronoi_segment.size() >= 2:
			if _is_path_valid(idx1, idx2, voronoi_midpoint):
				map_connections.append({
					"idx1": idx1,
					"idx2": idx2,
					"voronoi_point": voronoi_midpoint
				})

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

func _clip_to_bounds(point: Vector2) -> Vector2:
	return Vector2(
		clamp(point.x, 0, map_size.x),
		clamp(point.y, 0, map_size.y)
	)

func _add_triangle_to_edge(dict: Dictionary, i1: int, i2: int, triangle) -> void:
	var key = "%d_%d" % [min(i1, i2), max(i1, i2)]
	if not dict.has(key):
		dict[key] = []
	dict[key].append(triangle)

func _is_path_valid(idx1: int, idx2: int, voronoi_point: Vector2) -> bool:
	# Check both segments: point1->voronoi_point and voronoi_point->point2
	var p1 = map_points[idx1]
	var p2 = map_points[idx2]
	var type1 = point_types[idx1]
	var type2 = point_types[idx2]

	# Sample along the path to check terrain
	var segments = [
					   [p1, voronoi_point],
					   [voronoi_point, p2]
				   ]

	for segment in segments:
		var start = segment[0]
		var end = segment[1]
		var dist = start.distance_to(end)
		var num_samples = max(3, int(dist / 15.0))

		for i in range(1, num_samples):
			var t = float(i) / float(num_samples)
			var sample_pos = start.lerp(end, t)
			var nearest_idx = _find_nearest_point(sample_pos)
			var terrain_type = point_types[nearest_idx]

			# Path is invalid if it crosses through wrong terrain type
			if type1 == PointType.WATER:
				if terrain_type != PointType.WATER:
					return false
			else:  # Land (CITY or VILLAGE)
				if terrain_type == PointType.WATER or terrain_type == PointType.MOUNTAIN:
					return false

	return true

func _ensure_connectivity() -> void:
	# Get all non-mountain points
	var all_points = []
	for i in range(map_points.size()):
		if point_types[i] != PointType.MOUNTAIN:
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

		if neighbor != -1 and not visited.has(neighbor):
			_dfs(neighbor, visited, component)

func _draw() -> void:
	_draw_terrain()
	if show_voronoi_debug:
		_draw_voronoi_borders()
	_draw_connections()
	_draw_points()

func _draw_terrain() -> void:
	var cell_size = 8
	for x in range(0, int(map_size.x), cell_size):
		for y in range(0, int(map_size.y), cell_size):
			var pos = Vector2(x, y)
			var nearest_idx = _find_nearest_point(pos)
			var color = _get_terrain_color(pos, point_types[nearest_idx])

			# Add noise variation
			var noise_val = noise.get_noise_2d(pos.x, pos.y) * 0.15
			color = color.lerp(Color.WHITE if noise_val > 0 else Color.BLACK, abs(noise_val) * 0.5)

			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), color)

func _draw_voronoi_borders() -> void:
	# Draw all calculated Voronoi edges
	for edge_data in voronoi_edges:
		var segment = edge_data.segment
		if segment.size() >= 2:
			draw_line(segment[0], segment[1], Color.RED, 2.0)

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
	for i in range(map_points.size()):
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
