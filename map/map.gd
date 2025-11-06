extends Node2D
class_name GameMap

enum PointType { CITY, VILLAGE, WATER, MOUNTAIN }

var map_points: Array[Vector2] = []
var point_types: Array[int] = []
var map_connections: Array[Array] = []
var noise: FastNoiseLite
var boundary_noise: FastNoiseLite

var city_scene: PackedScene = preload("res://city/city_scene.tscn")

# Configurable parameters
var map_size := Vector2(1024, 600)
var num_points := 60
var num_cities := 10
var num_mountains := 3 # New: Number of mountain points to generate
var min_distance := 50.0
var interior_water_chance := 0.15  # Chance for interior points to start as water
var water_spread_chance := 0.4     # Chance for water to spread to neighbors
var road_connection_chance := 1.0 # Chance to keep a road connection
# New: Max distance for a village to connect to water
var max_village_water_connection_distance := 1500.0 

var show_voronoi_borders: bool = false # New: Toggle for displaying Voronoi borders

const MAP_SIZE = Vector2(1024, 600)  # Keep for compatibility

func _ready() -> void:
	_setup_noise()
	_generate_map()
	queue_redraw()
	
	# New: Add a button to toggle Voronoi borders
	var toggle_button = Button.new()
	add_child(toggle_button)
	toggle_button.text = "Toggle Voronoi Borders"
	# Changed position to be clearly visible at the top-left
	toggle_button.position = Vector2(20, 20)
	toggle_button.pressed.connect(_on_toggle_voronoi_borders_pressed)

func _setup_noise() -> void:
	# Noise for terrain variation within cells
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.01
	noise.fractal_octaves = 3

	# Noise for breaking up Voronoi boundaries
	boundary_noise = FastNoiseLite.new()
	boundary_noise.seed = randi()
	boundary_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	boundary_noise.frequency = .01
	boundary_noise.fractal_octaves = 2

func _on_toggle_voronoi_borders_pressed() -> void:
	show_voronoi_borders = not show_voronoi_borders
	# Add a print statement to confirm the button press
	print("Toggle Voronoi Borders pressed. show_voronoi_borders is now: ", show_voronoi_borders)
	queue_redraw()

func _generate_map() -> void:
	# Generate scattered points
	map_points = _generate_poisson_points(min_distance, num_points)

	# Assign types: water on borders, random interior water, cities, villages
	_assign_point_types()

	# Build road network with Delaunay triangulation
	_build_road_network()

	# Ensure all non-water settlements are connected
	_ensure_connectivity()

func _generate_poisson_points(min_dist: float, max_points: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts = 0
	var max_attempts = max_points * 200

	while points.size() < max_points and attempts < max_attempts:
		attempts += 1

		var new_point = Vector2(
							randf() * map_size.x,
							randf() * map_size.y
						)

		var valid = true
		for existing_point in points:
			if new_point.distance_to(existing_point) < min_dist:
				valid = false
				break

		if valid:
			points.append(new_point)

	return points

func _assign_point_types() -> void:
	point_types.resize(map_points.size())

	# First pass: all points start as villages
	for i in range(map_points.size()):
		point_types[i] = PointType.VILLAGE

	# Second pass: force border points to be water (ocean)
	var border_threshold = 60.0  # Distance from edge to be considered border
	for i in range(map_points.size()):
		var pos = map_points[i]
		if pos.x < border_threshold or pos.x > map_size.x - border_threshold or \
		pos.y < border_threshold or pos.y > map_size.y - border_threshold:
			point_types[i] = PointType.WATER

	# Third pass: create interior water clusters (lakes/rivers)
	_create_interior_water()

	# Fourth pass: assign mountains to remaining non-water points
	var available_for_mountains_or_cities = []
	for i in range(map_points.size()):
		if point_types[i] == PointType.VILLAGE: # Only assign mountains to current villages
			available_for_mountains_or_cities.append(i)
	
	available_for_mountains_or_cities.shuffle()
	var mountains_assigned = 0
	var temp_available_for_cities = [] # Points remaining after mountains
	for idx in available_for_mountains_or_cities:
		if mountains_assigned < num_mountains:
			point_types[idx] = PointType.MOUNTAIN
			mountains_assigned += 1
		else:
			temp_available_for_cities.append(idx) # These are still villages, eligible for cities

	# Fifth pass: assign cities to remaining non-water, non-mountain points
	temp_available_for_cities.shuffle()
	for i in range(min(num_cities, temp_available_for_cities.size())):
		point_types[temp_available_for_cities[i]] = PointType.CITY

func _create_interior_water() -> void:
	# Find non-border points that can become water
	var interior_points = []
	var border_threshold = 60.0

	for i in range(map_points.size()):
		if point_types[i] != PointType.WATER:  # Not already ocean
			var pos = map_points[i]
			# Check if truly interior
			if pos.x > border_threshold and pos.x < map_size.x - border_threshold and \
			pos.y > border_threshold and pos.y < map_size.y - border_threshold:
				interior_points.append(i)

	# Randomly select starting points for water clusters
	interior_points.shuffle()
	var water_seeds = []
	for idx in interior_points:
		if randf() < interior_water_chance:
			water_seeds.append(idx)

	# Spread water from seeds to create clusters
	for seed_idx in water_seeds:
		if point_types[seed_idx] == PointType.VILLAGE:  # May have been converted already
			_spread_water_from(seed_idx, interior_points)

func _spread_water_from(start_idx: int, valid_indices: Array) -> void:
	point_types[start_idx] = PointType.WATER

	var to_process = [start_idx]
	var processed = {}
	processed[start_idx] = true

	while to_process.size() > 0:
		var current_idx = to_process.pop_front()

		# Find nearby points
		var neighbors = _find_neighbors(current_idx, valid_indices)

		for neighbor_idx in neighbors:
			if processed.has(neighbor_idx):
				continue

			processed[neighbor_idx] = true

			# Chance to spread water to this neighbor
			if point_types[neighbor_idx] == PointType.VILLAGE and randf() < water_spread_chance:
				point_types[neighbor_idx] = PointType.WATER
				to_process.append(neighbor_idx)

func _find_neighbors(idx: int, valid_indices: Array, max_distance: float = 120.0) -> Array:
	var neighbors = []
	var pos = map_points[idx]

	for other_idx in valid_indices:
		if other_idx == idx:
			continue

		var dist = pos.distance_to(map_points[other_idx])
		if dist < max_distance:
			neighbors.append(other_idx)

	return neighbors

func _build_road_network() -> void:
	if map_points.size() < 3:
		return

	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2.ZERO, map_size))

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

		_add_edge(edges_dict, idx_a, idx_b)
		_add_edge(edges_dict, idx_b, idx_c)
		_add_edge(edges_dict, idx_c, idx_a)

	# Clear existing connections to rebuild based on new rules
	map_connections.clear()

	# Filter edges and categorize them
	for edge in edges_dict.values():
		var idx1 = edge[0]
		var idx2 = edge[1]
		var type1 = point_types[idx1]
		var type2 = point_types[idx2]

		# Rule: Mountains should connect to nothing
		if type1 == PointType.MOUNTAIN or type2 == PointType.MOUNTAIN:
			continue

		# Rule: Nearby water points should always connect
		if type1 == PointType.WATER and type2 == PointType.WATER:
			map_connections.append(edge)
			continue # Move to the next edge

		# Rule: Villages and cities should only connect to water when within a radius
		# This applies to connections between (CITY/VILLAGE) and WATER
		if (type1 == PointType.WATER and (type2 == PointType.CITY or type2 == PointType.VILLAGE)) or \
		   (type2 == PointType.WATER and (type1 == PointType.CITY or type1 == PointType.VILLAGE)):
			var dist = map_points[idx1].distance_to(map_points[idx2])
			if dist <= max_village_water_connection_distance:
				# Apply road_connection_chance for these "bridges"
				if randf() < road_connection_chance:
					map_connections.append(edge)
			continue # Move to the next edge

		# Rule: Nearby cities and villages should connect (with road_connection_chance)
		# This applies to connections between (CITY/VILLAGE) and (CITY/VILLAGE)
		if (type1 == PointType.CITY or type1 == PointType.VILLAGE) and \
		   (type2 == PointType.CITY or type2 == PointType.VILLAGE):
			# Apply road_connection_chance for these "roads"
			if randf() < road_connection_chance:
				map_connections.append(edge)
			continue # Move to the next edge

func _ensure_connectivity() -> void:
	# Find all non-water and non-mountain points
	var non_water_and_non_mountain_indices = []
	for i in range(map_points.size()):
		if point_types[i] != PointType.WATER and point_types[i] != PointType.MOUNTAIN:
			non_water_and_non_mountain_indices.append(i)

	if non_water_and_non_mountain_indices.size() < 2:
		return

	var visited = []
	visited.resize(map_points.size())
	visited.fill(false)

	var components = []

	for i in non_water_and_non_mountain_indices:
		if not visited[i]:
			var component = []
			_dfs(i, visited, component)
			components.append(component)

	# Connect components
	if components.size() > 1:
		for i in range(components.size() - 1):
			var comp_a = components[i]
			var comp_b = components[i + 1]

			var min_dist = INF
			var best_edge = []

			for a_idx in comp_a:
				for b_idx in comp_b:
					# New: Ensure we don't try to connect to a mountain point
					if point_types[a_idx] == PointType.MOUNTAIN or point_types[b_idx] == PointType.MOUNTAIN:
						continue
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

func _add_edge(dict: Dictionary, i1: int, i2: int) -> void:
	var key = str(min(i1, i2)) + "_" + str(max(i1, i2))
	if not dict.has(key):
		dict[key] = [i1, i2]

func _draw() -> void:
	_draw_voronoi_terrain()
	_draw_roads()
	_draw_points()

func _draw_voronoi_terrain() -> void:
	var cell_size = 8  # Smaller cells for better resolution

	for x in range(0, int(map_size.x), cell_size):
		for y in range(0, int(map_size.y), cell_size):
			var pos = Vector2(x, y)

			# Find nearest point (Voronoi cell)
			var nearest_idx = _find_nearest_point(pos)
			var nearest_type = point_types[nearest_idx]

			# Find second nearest for boundary detection
			var distances = []
			for i in range(map_points.size()):
				distances.append([i, pos.distance_to(map_points[i])])
			distances.sort_custom(func(a, b): return a[1] < b[1])

			var nearest_dist = distances[0][1]
			var second_nearest_dist = distances[1][1] if distances.size() > 1 else nearest_dist + 100
			var second_nearest_idx = distances[1][0] if distances.size() > 1 else nearest_idx
			var second_nearest_type = point_types[second_nearest_idx]

			# Calculate how close we are to the boundary
			var boundary_distance = second_nearest_dist - nearest_dist
			var is_near_boundary = boundary_distance < 15.0

			# Add noise to break up boundaries
			var boundary_breakup = boundary_noise.get_noise_2d(pos.x, pos.y)
			if is_near_boundary and boundary_breakup > 0.3:
				# Switch to second nearest sometimes for irregular borders
				nearest_type = second_nearest_type

			# Get base color for this cell
			var color = _get_terrain_color(pos, nearest_type)

			# Add per-cell variation with noise
			var variation = noise.get_noise_2d(pos.x, pos.y) * 0.15
			color = color.lerp(Color.WHITE, variation * 0.5)
			color = color.lerp(Color.BLACK, -variation * 0.5)

			# Blend at boundaries
			if is_near_boundary:
				var other_color = _get_terrain_color(pos, second_nearest_type)
				var blend_factor = clamp(boundary_distance / 15.0, 0.0, 1.0)
				color = color.lerp(other_color, 1.0 - blend_factor)

			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), color)
			
			# New: Draw Voronoi border if toggled and near boundary
			if show_voronoi_borders and is_near_boundary:
				# Changed color to RED and line width to 2.0 for better visibility
				draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color.RED, false, 2.0)


# Instead of just a midpoint, sample multiple points along the connection
func _get_voronoi_edge_path(p1: Vector2, p2: Vector2, num_samples: int = 3) -> PackedVector2Array:
	var path = PackedVector2Array()
	path.append(p1)
	
	for i in range(1, num_samples):
		var t = float(i) / float(num_samples)
		var point = p1.lerp(p2, t)
		path.append(point)
	
	path.append(p2)
	return path

func _find_nearest_point(pos: Vector2) -> int:
	var nearest_idx = 0
	var min_dist = INF

	for i in range(map_points.size()):
		var dist = pos.distance_to(map_points[i])
		if dist < min_dist:
			min_dist = dist
			nearest_idx = i

	return nearest_idx

func _get_terrain_color(pos: Vector2, type: int) -> Color:
	match type:
		PointType.WATER:
			# Blue water with depth variation
			var base_water = Color(0.25, 0.42, 0.62)
			var deep_water = Color(0.15, 0.28, 0.45)
			var noise_val = noise.get_noise_2d(pos.x * 0.5, pos.y * 0.5)
			return base_water.lerp(deep_water, (noise_val + 1.0) * 0.25)

		PointType.CITY, PointType.VILLAGE:
			# Green land with variation
			var base_green = Color(0.48, 0.67, 0.29)
			var dark_green = Color(0.36, 0.51, 0.25)
			var light_green = Color(0.58, 0.75, 0.35)

			var noise_val = noise.get_noise_2d(pos.x, pos.y)
			if noise_val > 0.3:
				return base_green.lerp(light_green, noise_val * 0.4)
			else:
				return base_green.lerp(dark_green, -noise_val * 0.3)

		PointType.MOUNTAIN:
			# Grey/brown rocky texture for mountains
			var base_mountain = Color(0.45, 0.4, 0.35)
			var snowy_peak = Color(0.85, 0.9, 0.95)
			var dark_rock = Color(0.3, 0.25, 0.2)

			var noise_val = noise.get_noise_2d(pos.x * 0.5, pos.y * 0.5)
			if noise_val > 0.4: # Higher noise values for "snowy" peaks
				return base_mountain.lerp(snowy_peak, (noise_val - 0.4) * 1.5)
			elif noise_val < -0.3: # Lower noise values for darker crevices
				return base_mountain.lerp(dark_rock, (-noise_val - 0.3) * 1.5)
			else:
				return base_mountain

	return Color.WHITE  # Fallback

func _draw_roads() -> void:
	# Draw roads between settlements
	for connection in map_connections:
		var p1 = map_points[connection[0]]
		var p2 = map_points[connection[1]]
		var type1 = point_types[connection[0]]
		var type2 = point_types[connection[1]]
		
		# Calculate midpoint of Voronoi edge
		var edge_midpoint = (p1 + p2) * 0.5
		
		# Water-to-water connections (dotted lines)
		if type1 == PointType.WATER or type2 == PointType.WATER:
			_draw_dashed_line(p1, edge_midpoint, Color(0.35, 0.5, 0.65, 0.6), 2.5, 8.0, 6.0)
			_draw_dashed_line(edge_midpoint, p2, Color(0.35, 0.5, 0.65, 0.6), 2.5, 8.0, 6.0)
		# Land connections (roads) or mixed connections (bridges)
		else:
			# Determine road style
			var is_highway = (type1 == PointType.CITY and type2 == PointType.CITY)
			if is_highway:
				# Highway: thicker, orange/brown
				draw_line(p1, edge_midpoint, Color(0.4, 0.25, 0.15, 0.5), 5.5, false)
				draw_line(edge_midpoint, p2, Color(0.4, 0.25, 0.15, 0.5), 5.5, false)
			else:
				# Regular road: thinner, light brown
				draw_line(p1, edge_midpoint, Color(0.6313726, 0.38431373, 0.15294118, 0.5019608), 3.5, false)
				draw_line(edge_midpoint, p2, Color(0.6313726, 0.38431373, 0.15294118, 0.5019608), 3.5, false)
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

func _draw_points() -> void:
	# Draw settlement markers
	for i in range(map_points.size()):
		var pos = map_points[i]
		var type = point_types[i]
		
		match type:
			PointType.CITY:
				draw_circle(pos, 11, Color(0.25, 0.2, 0.2))
				draw_circle(pos, 9, Color(0.8, 0.35, 0.3))
				draw_circle(pos, 6, Color(0.95, 0.55, 0.45))
			
			PointType.VILLAGE:
				draw_circle(pos, 5, Color(0.4, 0.35, 0.3))
				draw_circle(pos, 3, Color(0.65, 0.6, 0.55))
			
			PointType.WATER:
				# Draw water points with distinct visual
				draw_circle(pos, 7, Color(0.15, 0.28, 0.45))
				draw_circle(pos, 5, Color(0.25, 0.42, 0.62))
				draw_circle(pos, 3, Color(0.45, 0.60, 0.78))
			
			PointType.MOUNTAIN:
				# Draw a triangular-like shape for mountains
				var p1 = pos + Vector2(0, -9)
				var p2 = pos + Vector2(-8, 5)
				var p3 = pos + Vector2(8, 5)
				var color_base = Color(0.4, 0.35, 0.3)
				var color_highlight = Color(0.6, 0.55, 0.5)
				
				# Darker base
				draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color_base)
				# Lighter highlight for a snowy/rocky peak effect
				var p1_light = pos + Vector2(0, -7)
				var p2_light = pos + Vector2(-4, 2)
				var p3_light = pos + Vector2(4, 2)
				draw_colored_polygon(PackedVector2Array([p1_light, p2_light, p3_light]), color_highlight)

func _draw_voronoi_borders() -> void:
	if not show_voronoi_borders:
		return
		
	var cell_size = 8
	for x in range(0, int(map_size.x), cell_size):
		for y in range(0, int(map_size.y), cell_size):
			var pos = Vector2(x, y)
			
			# Find nearest and second nearest points
			var distances = []
			for i in range(map_points.size()):
				distances.append([i, pos.distance_to(map_points[i])])
			distances.sort_custom(func(a, b): return a[1] < b[1])
			
			if distances.size() < 2:
				continue
				
			var nearest_dist = distances[0][1]
			var second_nearest_dist = distances[1][1]
			var boundary_distance = second_nearest_dist - nearest_dist
			
			# Draw border where cells meet
			if boundary_distance < 2.0:
				draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color(0, 0, 0, 0.3))