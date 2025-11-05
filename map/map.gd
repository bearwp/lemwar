extends Node2D
class_name GameMap

var map_points: Array[Vector2] = []
var map_connections: Array[Array] = []
var map_cities: Array[int] = []

var city_scene: PackedScene = preload("res://city/city_scene.tscn")

func _ready() -> void:
	var map_size = Vector2(1024, 600)
	var num_points = 50
	var num_cities = 10
	var min_distance = 80.0

	# Generate points with minimum distance
	map_points = _generate_poisson_points(map_size, min_distance, num_points)

	# Use Delaunay to create connections
	var delaunay = Delaunay.new()
	delaunay.set_rectangle(Rect2(Vector2.ZERO, map_size))

	for point in map_points:
		delaunay.add_point(point)

	var triangles = delaunay.triangulate()
	delaunay.remove_border_triangles(triangles)

	# Extract edges from triangles and filter by angle
	var edges_dict = {}
	for triangle in triangles:
		var idx_a = map_points.find(triangle.a)
		var idx_b = map_points.find(triangle.b)
		var idx_c = map_points.find(triangle.c)

		if idx_a == -1 or idx_b == -1 or idx_c == -1:
			continue

		# Check angles before adding edges
		if _is_angle_good(triangle.a, triangle.b, triangle.c):
			_add_edge(edges_dict, idx_a, idx_b)
		if _is_angle_good(triangle.b, triangle.c, triangle.a):
			_add_edge(edges_dict, idx_b, idx_c)
		if _is_angle_good(triangle.c, triangle.a, triangle.b):
			_add_edge(edges_dict, idx_c, idx_a)

	# Prune long edges to make it more sparse and natural
	for edge in edges_dict.values():
		var p1 = map_points[edge[0]]
		var p2 = map_points[edge[1]]
		var distance = p1.distance_to(p2)

		# Only keep shorter roads, randomly drop some medium-length ones
		if distance < 150 or (distance < 250 and randf() > 0.5):
			map_connections.append(edge)

	# Pick random cities
	var available = range(map_points.size())
	available.shuffle()
	for i in range(min(num_cities, map_points.size())):
		map_cities.append(available[i])

	queue_redraw()

func _is_angle_good(corner: Vector2, side1: Vector2, side2: Vector2) -> bool:
	# Calculate angle at 'corner' point
	var v1 = (side1 - corner).normalized()
	var v2 = (side2 - corner).normalized()
	var dot = v1.dot(v2)
	var angle = acos(clamp(dot, -1.0, 1.0))

	# Remove edges if angle is too sharp (less than 25 degrees or ~0.44 radians)
	return angle > 0.44

func _generate_poisson_points(map_size: Vector2, min_dist: float, max_points: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts = 0
	var max_attempts = max_points * 100

	points.append(Vector2(randf() * map_size.x, randf() * map_size.y))

	while points.size() < max_points and attempts < max_attempts:
		attempts += 1

		var new_point = Vector2(randf() * map_size.x, randf() * map_size.y)
		var valid = true

		for existing_point in points:
			if new_point.distance_to(existing_point) < min_dist:
				valid = false
				break

		if valid:
			points.append(new_point)

	return points

func _add_edge(dict: Dictionary, i1: int, i2: int) -> void:
	var key = str(min(i1, i2)) + "_" + str(max(i1, i2))
	if not dict.has(key):
		dict[key] = [i1, i2]

func _draw() -> void:
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, Vector2(1024, 600)), Color(0.1, 0.15, 0.2))

	# Draw roads with varied widths based on distance (shorter = more important)
	for connection in map_connections:
		var p1 = map_points[connection[0]]
		var p2 = map_points[connection[1]]
		var distance = p1.distance_to(p2)

		# Shorter roads are thicker (main roads)
		var width = 4.0 if distance < 120 else 2.0
		var color = Color(0.6, 0.6, 0.5) if distance < 120 else Color(0.4, 0.4, 0.35)

		draw_line(p1, p2, color, width)

	# Draw all points as small villages/intersections
	for i in range(map_points.size()):
		var is_city = map_cities.has(i)
		if is_city:
			# Cities - larger with border
			draw_circle(map_points[i], 10, Color(0.8, 0.3, 0.2))
			draw_circle(map_points[i], 7, Color(0.95, 0.5, 0.3))
		else:
			# Villages - smaller
			draw_circle(map_points[i], 4, Color(0.5, 0.5, 0.45))