@tool
extends Node2D

## Configuration
@export_group("Map Generation")
@export var num_cities: int = 10:
	set(value):
		num_cities = value
		if Engine.is_editor_hint():
			_clear_map()

@export var map_width: float = 1000.0:
	set(value):
		map_width = value
		if Engine.is_editor_hint():
			_clear_map()

@export var map_height: float = 600.0:
	set(value):
		map_height = value
		if Engine.is_editor_hint():
			_clear_map()

@export var min_city_distance: float = 100.0:
	set(value):
		min_city_distance = value
		if Engine.is_editor_hint():
			_clear_map()

@export var road_probability: float = 0.3:
	set(value):
		road_probability = clamp(value, 0.0, 1.0)
		if Engine.is_editor_hint():
			_clear_map()

@export var max_road_distance: float = 300.0:
	set(value):
		max_road_distance = value
		if Engine.is_editor_hint():
			_clear_map()

@export var random_seed: int = 0:
	set(value):
		random_seed = value
		if Engine.is_editor_hint():
			_clear_map()

@export_group("Visuals")
@export var city_color: Color = Color.BLUE
@export var city_radius: float = 10.0
@export var road_color: Color = Color.WHITE
@export var road_width: float = 3.0

@export_group("Actions")
@export var generate_map: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_generate_map()
		generate_map = false

@export var clear_map: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_clear_map()
		clear_map = false

## Data
var city_positions: Array[Vector2] = []
var roads: Array[Array] = []  # Array of [city_index_a, city_index_b]

## City scene reference
@export var city_scene: PackedScene

func _ready() -> void:
	if not Engine.is_editor_hint():
		_generate_map()

func _generate_map() -> void:
	_clear_map()
	
	# Set random seed if specified
	if random_seed != 0:
		seed(random_seed)
	
	# Generate city positions
	_generate_cities()
	
	# Generate roads between cities
	_generate_roads()
	
	# Create visual representation
	_create_visuals()
	
	print("Map generated with %d cities and %d roads" % [city_positions.size(), roads.size()])

func _generate_cities() -> void:
	city_positions.clear()
	var attempts = 0
	var max_attempts = num_cities * 100
	
	while city_positions.size() < num_cities and attempts < max_attempts:
		attempts += 1
		
		var pos = Vector2(
			randf_range(0, map_width),
			randf_range(0, map_height)
		)
		
		# Check if position is far enough from other cities
		var valid = true
		for existing_pos in city_positions:
			if pos.distance_to(existing_pos) < min_city_distance:
				valid = false
				break
		
		if valid:
			city_positions.append(pos)

func _generate_roads() -> void:
	roads.clear()
	
	# Check each pair of cities
	for i in range(city_positions.size()):
		for j in range(i + 1, city_positions.size()):
			var distance = city_positions[i].distance_to(city_positions[j])
			
			# Only create roads if cities are close enough
			if distance <= max_road_distance:
				# Randomly decide if a road should connect these cities
				if randf() < road_probability:
					roads.append([i, j])

func _add_edge_to_set(edge_set: Dictionary, v1: int, v2: int) -> void:
	# Create a consistent key for the edge (sorted)
	var key = ""
	if v1 < v2:
		key = "%d,%d" % [v1, v2]
	else:
		key = "%d,%d" % [v2, v1]
	
	# Add the edge if not already present
	if not key in edge_set:
		edge_set[key] = [v1, v2]

func _generate_roads_delaunay() -> void:
	roads.clear()
	
	# Need at least 3 cities for triangulation
	if city_positions.size() < 3:
		print("Not enough cities for Delaunay triangulation (need at least 3)")
		return
	
	# Create Delaunay instance and add points
	var delaunay = Delaunay.new()
	for pos in city_positions:
		delaunay.add_point(pos)
	
	# Perform Delaunay triangulation
	var triangles = delaunay.triangulate()
	
	# Extract unique edges from triangles
	var edge_set: Dictionary = {}
	
	for triangle in triangles:
		# Each triangle has 3 vertices (indices into city_positions)
		var v0 = triangle.vertices[0]
		var v1 = triangle.vertices[1]
		var v2 = triangle.vertices[2]
		
		# Add the 3 edges of the triangle
		_add_edge_to_set(edge_set, v0, v1)
		_add_edge_to_set(edge_set, v1, v2)
		_add_edge_to_set(edge_set, v2, v0)
	
	# Convert edge set to roads array
	for edge_key in edge_set.keys():
		roads.append(edge_set[edge_key])

func _create_visuals() -> void:
	# Create roads (draw using Line2D or direct drawing)
	for road in roads:
		var line = Line2D.new()
		line.add_point(city_positions[road[0]])
		line.add_point(city_positions[road[1]])
		line.default_color = road_color
		line.width = road_width
		line.z_index = -1
		add_child(line)
		if Engine.is_editor_hint():
			line.owner = get_tree().edited_scene_root
	
	# Create cities
	for i in range(city_positions.size()):
		var city_node: Node2D
		
		if city_scene:
			# Use the city scene if provided
			city_node = city_scene.instantiate()
		else:
			# Create a simple visual representation
			city_node = Node2D.new()
			var sprite = _create_city_sprite()
			city_node.add_child(sprite)
			if Engine.is_editor_hint():
				sprite.owner = get_tree().edited_scene_root
		
		city_node.name = "City_%d" % i
		city_node.position = city_positions[i]
		add_child(city_node)
		
		if Engine.is_editor_hint():
			city_node.owner = get_tree().edited_scene_root

func _create_city_sprite() -> Node2D:
	# Create a simple circle to represent a city
	var marker = Marker2D.new()
	marker.gizmo_extents = city_radius
	return marker

func _clear_map() -> void:
	# Remove all children
	for child in get_children():
		child.queue_free()
	
	city_positions.clear()
	roads.clear()

## Public API for accessing map data
func get_city_positions() -> Array[Vector2]:
	return city_positions

func get_roads() -> Array[Array]:
	return roads

func get_city_count() -> int:
	return city_positions.size()

func get_road_count() -> int:
	return roads.size()
