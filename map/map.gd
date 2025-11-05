
extends Node2D
class_name GameMap

enum PointType { CITY, VILLAGE, WATER }

var map_points: Array[Vector2] = []
var point_types: Array[int] = []
var map_connections: Array[Array] = []
var highway_connections: Array[Array] = []
var noise: FastNoiseLite
var elevation_noise: FastNoiseLite

var city_scene: PackedScene = preload("res://city/city_scene.tscn")

const MAP_SIZE = Vector2(1024, 600)

func _ready() -> void:
	var num_points = 60
	var num_cities = 10
	var num_water = randi_range(10, 30)
	var min_distance = 50.0

	_setup_terrain_noise()
	map_points = _generate_poisson_points(min_distance, num_points)
	_assign_point_types_clustered(num_cities, num_water)
	_remove_isolated_water()
	_build_road_network()
	_ensure_connectivity()

	queue_redraw()

func _setup_terrain_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	noise.fractal_octaves = 2

	# Separate noise for elevation
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = randi()
	elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	elevation_noise.frequency = 0.005  # Larger features
	elevation_noise.fractal_octaves = 3

func _generate_poisson_points(min_dist: float, max_points: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts = 0
	var max_attempts = max_points * 200

	while points.size() < max_points and attempts < max_attempts:
		attempts += 1

		var new_point = Vector2(
							randf() * MAP_SIZE.x,
							randf() * MAP_SIZE.y
						)

		var valid = true
		for existing_point in points:
			if new_point.distance_to(existing_point) < min_dist:
				valid = false
				break

		if valid:
			points.append(new_point)

	return points

func _assign_point_types_clustered(num_cities: int, num_water: int) -> void:
	point_types.resize(map_points.size())

	for i in range(map_points.size()):
		point_types[i] = PointType.VILLAGE

	var available_indices = range(map_points.size())
	available_indices.shuffle()

	for i in range(min(num_cities, available_indices.size())):
		point_types[available_indices[i]] = PointType.CITY

	var water_assigned = 0
	var cluster_distance = 120.0
	var new_cluster_chance = 0.1
	var current_cluster_size = 0
	var max_cluster_size = randi_range(2, 4)

	while water_assigned < num_water and available_indices.size() > num_cities:
		var start_new_cluster = (water_assigned == 0 or
		current_cluster_size >= max_cluster_size or
		randf() < new_cluster_chance)

		if start_new_cluster:
			var found = false
			for i in range(map_points.size()):
				if point_types[i] == PointType.VILLAGE:
					point_types[i] = PointType.WATER
					water_assigned += 1
					current_cluster_size = 1
					max_cluster_size = randi_range(2, 4)
					found = true
					break

			if not found:
				break
		else:
			var existing_water = []
			for i in range(map_points.size()):
				if point_types[i] == PointType.WATER:
					existing_water.append(i)

			if existing_water.size() > 0:
				var recent_waters = existing_water.slice(max(0, existing_water.size() - max_cluster_size))
				var target_water_idx = recent_waters[randi() % recent_waters.size()]
				var target_pos = map_points[target_water_idx]

				var best_idx = -1
				var best_dist = INF

				for i in range(map_points.size()):
					if point_types[i] == PointType.VILLAGE:
						var dist = map_points[i].distance_to(target_pos)
						if dist < cluster_distance and dist < best_dist:
							best_dist = dist
							best_idx = i

				if best_idx != -1:
					point_types[best_idx] = PointType.WATER
					water_assigned += 1
					current_cluster_size += 1
				else:
					current_cluster_size = max_cluster_size

func _remove_isolated_water() -> void:
	for i in range(map_points.size()):
		if point_types[i] != PointType.WATER:
			continue

		var has_water_neighbor = false
		var my_pos = map_points[i]

		for j in range(map_points.size()):
			if i == j or point_types[j] != PointType.WATER:
				continue

			var dist = my_pos.distance_to(map_points[j])
			if dist < 150.0:
				has_water_neighbor = true
				break

		if not has_water_neighbor:
			point_types[i] = PointType.VILLAGE

func _build_road_network() -> void:
	if map_points.size() < 3:
		return

	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2.ZERO, MAP_SIZE))

	for point in map_points:
		delaunay.add_point(point)

	var triangles = delaunay.triangulate()
	delaunay.remove_border_triangles(triangles)

	var edges_dict = {}
	for triangle in triangles:
		var idx_a = map_points.find(triangle.a)
		var idx_b = map_points.find(triangle.b)
		var idx_c = map_points.find(triangle.c)

		if idx_a == -1 or idx_b == -1 or idx_c == -1:
			continue

		if _is_angle_good(triangle.a, triangle.b, triangle.c):
			_add_edge(edges_dict, idx_a, idx_b)
		if _is_angle_good(triangle.b, triangle.c, triangle.a):
			_add_edge(edges_dict, idx_b, idx_c)
		if _is_angle_good(triangle.c, triangle.a, triangle.b):
			_add_edge(edges_dict, idx_c, idx_a)

	# Apply Gabriel Graph filter
	var gabriel_edges = _filter_gabriel_graph(edges_dict.values())

	for edge in gabriel_edges:
		var p1 = map_points[edge[0]]
		var p2 = map_points[edge[1]]
		var distance = p1.distance_to(p2)

		if distance > 140:  # Slightly reduced
			continue

		var type1 = point_types[edge[0]]
		var type2 = point_types[edge[1]]

		var is_highway = (type1 == PointType.CITY and type2 == PointType.CITY)

		if is_highway:
			highway_connections.append(edge)
		else:
			map_connections.append(edge)

func _filter_gabriel_graph(edges: Array) -> Array:
	# Gabriel Graph: Keep edge only if circle with edge as diameter contains no other points
	var gabriel_edges = []

	for edge in edges:
		var p1 = map_points[edge[0]]
		var p2 = map_points[edge[1]]
		var center = (p1 + p2) * 0.5
		var radius = p1.distance_to(p2) * 0.5

		var is_gabriel = true
		for i in range(map_points.size()):
			if i == edge[0] or i == edge[1]:
				continue

			var dist = map_points[i].distance_to(center)
			if dist < radius - 0.1:  # Small epsilon for floating point
				is_gabriel = false
				break

		if is_gabriel:
			gabriel_edges.append(edge)

	return gabriel_edges

func _ensure_connectivity() -> void:
	var visited = []
	visited.resize(map_points.size())
	visited.fill(false)

	var components = []

	for i in range(map_points.size()):
		if not visited[i]:
			var component = []
			_dfs(i, visited, component)
			components.append(component)

	if components.size() > 1:
		for i in range(components.size() - 1):
			var comp_a = components[i]
			var comp_b = components[i + 1]

			var min_dist = INF
			var best_edge = []

			for a_idx in comp_a:
				for b_idx in comp_b:
					var dist = map_points[a_idx].distance_to(map_points[b_idx])
					if dist < min_dist:
						min_dist = dist
						best_edge = [a_idx, b_idx]

			if best_edge.size() > 0:
				map_connections.append(best_edge)

func _dfs(node: int, visited: Array, component: Array) -> void:
	visited[node] = true
	component.append(node)

	for edge in map_connections:
		if edge[0] == node and not visited[edge[1]]:
			_dfs(edge[1], visited, component)
		elif edge[1] == node and not visited[edge[0]]:
			_dfs(edge[0], visited, component)

	for edge in highway_connections:
		if edge[0] == node and not visited[edge[1]]:
			_dfs(edge[1], visited, component)
		elif edge[1] == node and not visited[edge[0]]:
			_dfs(edge[0], visited, component)

func _is_angle_good(corner: Vector2, side1: Vector2, side2: Vector2) -> bool:
	var v1 = (side1 - corner).normalized()
	var v2 = (side2 - corner).normalized()
	var dot = v1.dot(v2)
	var angle = acos(clamp(dot, -1.0, 1.0))
	return angle > 0.4  # Slightly stricter

func _add_edge(dict: Dictionary, i1: int, i2: int) -> void:
	var key = str(min(i1, i2)) + "_" + str(max(i1, i2))
	if not dict.has(key):
		dict[key] = [i1, i2]

func _connection_has_water(edge: Array) -> bool:
	return point_types[edge[0]] == PointType.WATER or point_types[edge[1]] == PointType.WATER

func _both_are_water(edge: Array) -> bool:
	return point_types[edge[0]] == PointType.WATER and point_types[edge[1]] == PointType.WATER

func _get_water_influence(pos: Vector2) -> float:
	# Smooth distance field to nearest water
	var min_dist = INF
	for i in range(map_points.size()):
		if point_types[i] == PointType.WATER:
			var dist = pos.distance_to(map_points[i])
			if dist < min_dist:
				min_dist = dist

	# Check water paths too
	for connection in map_connections:
		if _both_are_water(connection):
			var p1 = map_points[connection[0]]
			var p2 = map_points[connection[1]]
			var dist_to_line = _distance_to_line_segment(pos, p1, p2)
			if dist_to_line < min_dist:
				min_dist = dist_to_line

	for connection in highway_connections:
		if _both_are_water(connection):
			var p1 = map_points[connection[0]]
			var p2 = map_points[connection[1]]
			var dist_to_line = _distance_to_line_segment(pos, p1, p2)
			if dist_to_line < min_dist:
				min_dist = dist_to_line

	# Convert to 0-1 influence (smooth falloff)
	var water_radius = 80.0
	return 1.0 - clamp(min_dist / water_radius, 0.0, 1.0)

func _distance_to_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()

	if line_len == 0:
		return point.distance_to(line_start)

	var t = clamp(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	var projection = line_start + t * line_vec
	return point.distance_to(projection)

func _draw() -> void:
	_draw_terrain()

	# Draw local roads
	for connection in map_connections:
		var p1 = map_points[connection[0]]
		var p2 = map_points[connection[1]]
		var distance = p1.distance_to(p2)
		var has_water = _connection_has_water(connection)

		if has_water:
			_draw_dashed_line(p1, p2, Color(0.3, 0.45, 0.6), 3.0, 12.0, 8.0)
		else:
			var width = 3.5 if distance < 70 else 2.5
			draw_line(p1, p2, Color(0.35, 0.3, 0.25), width + 1.5, true)
			draw_line(p1, p2, Color(0.75, 0.7, 0.65), width, true)

	# Draw highways
	for connection in highway_connections:
		var p1 = map_points[connection[0]]
		var p2 = map_points[connection[1]]
		var has_water = _connection_has_water(connection)

		if has_water:
			_draw_dashed_line(p1, p2, Color(0.4, 0.55, 0.7), 4.5, 15.0, 10.0)
		else:
			draw_line(p1, p2, Color(0.5, 0.25, 0.2), 5.5, true)
			draw_line(p1, p2, Color(0.85, 0.6, 0.4), 4.0, true)

	# Draw all points
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
				draw_circle(pos, 8, Color(0.15, 0.28, 0.45))
				draw_circle(pos, 6, Color(0.25, 0.42, 0.62))
				draw_circle(pos, 3, Color(0.45, 0.60, 0.78))

func _draw_terrain() -> void:
	var cell_size = 16

	for x in range(0, int(MAP_SIZE.x), cell_size):
		for y in range(0, int(MAP_SIZE.y), cell_size):
			var pos = Vector2(x, y)

			# Get water influence (0 = land, 1 = deep water)
			var water_influence = _get_water_influence(pos)

			# Get elevation
			var elevation = elevation_noise.get_noise_2d(pos.x, pos.y)

			var color: Color
			if water_influence > 0.3:  # In water
				# Deep to shallow water based on influence
				var deep_water = Color(0.18, 0.30, 0.48)
				var shallow_water = Color(0.28, 0.45, 0.62)
				color = deep_water.lerp(shallow_water, 1.0 - water_influence)
			else:
				# Land with elevation-based coloring
				var base_land = Color(0.36078432, 0.40784314, 0.24705882)  # Light tan
				var low_land = Color(0.48235294, 0.6666667, 0.09411765)   # Greenish lowlands
				var high_land = Color(0.70, 0.68, 0.60)  # Brown highlands

				if elevation < -0.2:
					# Lowlands (valleys, plains)
					color = base_land.lerp(low_land, 0.5)
				elif elevation > 0.3:
					# Highlands (hills, mountains)
					color = base_land.lerp(high_land, 0.6)
				else:
					# Regular land
					color = base_land

				# Add subtle texture variation
				var detail = noise.get_noise_2d(pos.x, pos.y) * 0.08
				color = color.lerp(Color(0.82, 0.79, 0.72), detail)

				# Blend to water at edges
				if water_influence > 0:
					var shore_color = Color(0.65, 0.70, 0.60)  # Sandy shore
					color = color.lerp(shore_color, water_influence * 3.0)

			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), color)

	# Draw coastlines (darker water edges)
	for x in range(0, int(MAP_SIZE.x), cell_size):
		for y in range(0, int(MAP_SIZE.y), cell_size):
			var pos = Vector2(x, y)
			var water_influence = _get_water_influence(pos)

			if water_influence > 0.5:
				# Check if near land
				var near_land = false
				for dx in [-cell_size, cell_size]:
					for dy in [-cell_size, cell_size]:
						var check_pos = pos + Vector2(dx, dy)
						var check_influence = _get_water_influence(check_pos)
						if check_influence < 0.5:
							near_land = true
							break
					if near_land:
						break

				if near_land:
					draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color(0.14, 0.24, 0.38, 0.6))

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_length: float, gap_length: float) -> void:
	var direction = (to - from).normalized()
	var distance = from.distance_to(to)
	var current_distance = 0.0

	while current_distance < distance:
		var start = from + direction * current_distance
		var end_distance = min(current_distance + dash_length, distance)
		var end = from + direction * end_distance

		draw_line(start, end, color, width, true)
		current_distance += dash_length + gap_length