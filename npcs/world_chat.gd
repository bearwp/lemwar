
extends NobodyWhoChat
class_name WorldChat

@onready var map_node: GameMap = null

# Signals for map description generation
signal description_generation_progress(current: int, total: int)
signal description_generation_complete(points_processed: int)
signal response_received(response: String)

var generation_in_progress: bool = false
var pending_description_data: Dictionary = {}

func _ready() -> void:
	self.system_prompt = "/no_think You are the world chat. You know everything about the world"
	add_tool(get_map_info, "Retrieves various pieces of information about the game map, such as the number of cities, villages, mountains, forests, water sources, and the overall map size. If the information is not explicitly provided in this tool, then it is not available.")
	add_tool(get_point_info, "Provides detailed information about a specific map point, including its type (City, Village, Water Source, Mountain, Forest), its name, and its connections to other points with cardinal directions. Requires a point_id (integer) as input.")
	add_tool(rename_point, "Renames a specific map point. Requires a point_id (integer) and the new_name (string) as input.")

	# Connect to the response_finished signal from NobodyWhoChat
	response_finished.connect(_on_response_received)

	say("Hi there! Who are you?")

func _on_response_received(response: String) -> void:
	"""Handle response from the AI"""
	response_received.emit(response)

	
# ============================================================================
# PRIVATE UTILITY METHODS
# ============================================================================

func _ensure_map_loaded() -> bool:
	"""Ensure map_node is loaded. Returns true if successful."""
	if is_instance_valid(map_node):
		return true

	# Try multiple methods to find the map
	map_node = get_tree().get_first_node_in_group("game_map")
	if is_instance_valid(map_node):
		return true

	map_node = get_parent().find_child("Map", true, false)
	if is_instance_valid(map_node):
		return true

	return false

func _get_type_name(type: int) -> String:
	"""Convert PointType enum to readable string."""
	match type:
		map_node.PointType.CITY:
			return "city"
		map_node.PointType.VILLAGE:
			return "village"
		map_node.PointType.WATER:
			return "water"
		map_node.PointType.MOUNTAIN:
			return "mountain"
		map_node.PointType.FOREST:
			return "forest"
	return "unknown"

func _get_type_display_name(type: int) -> String:
	"""Convert PointType enum to display string for user-facing text."""
	match type:
		map_node.PointType.CITY:
			return "City"
		map_node.PointType.VILLAGE:
			return "Village"
		map_node.PointType.WATER:
			return "Water Source"
		map_node.PointType.MOUNTAIN:
			return "Mountain"
		map_node.PointType.FOREST:
			return "Forest"
	return "Unknown Type"

func _get_direction_string(from_pos: Vector2, to_pos: Vector2) -> String:
	"""Calculate cardinal direction between two positions."""
	var direction_vec = (to_pos - from_pos).normalized()
	var angle = direction_vec.angle()

	if angle < 0:
		angle += 2 * PI

	if angle >= (7 * PI / 4) or angle < (PI / 4):
		return "East"
	elif angle >= (PI / 4) and angle < (3 * PI / 4):
		return "South"
	elif angle >= (3 * PI / 4) and angle < (5 * PI / 4):
		return "West"
	else:
		return "North"

func _count_point_type(point_type: int) -> int:
	"""Count how many points of a given type exist (excluding boundary)."""
	var count = 0
	for i in range(map_node.map_points.size()):
		if map_node.point_types[i] == point_type and not map_node.boundary_point_indices.has(i):
			count += 1
	return count

# ============================================================================
# MAP TOOLS (Called by NPC AI)
# ============================================================================

func get_map_info(query: String) -> String:
	"""Retrieves map information based on query."""
	if not _ensure_map_loaded():
		return "Map information is not available. The map node could not be found."

	var query_lower = query.to_lower()

	if query_lower.contains("number of cities"):
		return "There are %d cities on the map." % map_node.num_cities
	elif query_lower.contains("map size"):
		return "The map size is %s." % str(map_node.map_size)
	elif query_lower.contains("number of villages"):
		return "There are %d villages on the map." % _count_point_type(map_node.PointType.VILLAGE)
	elif query_lower.contains("number of mountains"):
		return "There are %d mountains on the map." % _count_point_type(map_node.PointType.MOUNTAIN)
	elif query_lower.contains("number of forests"):
		return "There are %d forests on the map." % _count_point_type(map_node.PointType.FOREST)
	elif query_lower.contains("number of water sources"):
		return "There are %d water sources initially placed on the map." % map_node.num_water_sources
	elif query_lower.contains("number of points"):
		return "There are %d total points on the map, including boundary points." % map_node.map_points.size()

	return "I can provide information about the number of cities, villages, mountains, forests, water sources, and the overall map size."

func get_point_info(point_id: int) -> String:
	"""Retrieves detailed information about a specific map point."""
	if not _ensure_map_loaded():
		return "Map information is not available. The map node could not be found."

	if point_id < 0 or point_id >= map_node.map_points.size():
		return "Invalid point ID. Please provide a valid point ID within the map's range (0 to %d)." % (map_node.map_points.size() - 1)

	var point_pos = map_node.map_points[point_id]
	var point_type_enum = map_node.point_types[point_id]
	var point_properties = map_node.point_properties[point_id]
	var point_name = map_node.point_names[point_id]
	var type_string = _get_type_display_name(point_type_enum)

	var info_string = "Point ID %d, named '%s', at position (%s) is a %s." % [point_id, point_name, str(point_pos), type_string]

	if point_type_enum == map_node.PointType.WATER and point_properties.get("is_deep_sea", false):
		info_string += " It is also classified as deep sea."

	# Build connections list
	var connections_info = []
	for connection in map_node.map_connections:
		var connected_idx = -1
		if connection.idx1 == point_id:
			connected_idx = connection.idx2
		elif connection.idx2 == point_id:
			connected_idx = connection.idx1

		if connected_idx != -1:
			var connected_type_string = _get_type_display_name(map_node.point_types[connected_idx])
			var connected_pos = map_node.map_points[connected_idx]
			var direction = _get_direction_string(point_pos, connected_pos)
			connections_info.append("Connected to Point ID %d (%s) to the %s via a path." % [connected_idx, connected_type_string, direction])

	if connections_info.size() > 0:
		info_string += "\nConnections:\n- " + "\n- ".join(connections_info)
	else:
		info_string += " It has no connections to other points."

	return info_string

func rename_point(point_id: int, new_name: String) -> String:
	"""Renames a specific map point."""
	if not _ensure_map_loaded():
		return "Map information is not available. The map node could not be found."

	if point_id < 0 or point_id >= map_node.map_points.size():
		return "Invalid point ID. Please provide a valid point ID within the map's range (0 to %d)." % (map_node.map_points.size() - 1)

	if map_node.set_point_name(point_id, new_name):
		return "Point ID %d has been renamed to '%s'." % [point_id, new_name]
	else:
		return "Failed to rename point ID %d." % point_id

# ============================================================================
# MAP DESCRIPTION GENERATION (RAG System)
# ============================================================================

func generate_map_descriptions(game_map: GameMap) -> void:
	"""Generate AI descriptions for all interesting points on the map."""
	if generation_in_progress:
		print("Description generation already in progress!")
		return

	generation_in_progress = true
	map_node = game_map

	# Get points to process (skip boundary and generic tiles)
	var points_to_process = []
	for i in range(game_map.map_points.size()):
		if game_map.boundary_point_indices.has(i):
			continue

		var point_type = game_map.point_types[i]
		# Only process interesting points
		if point_type == game_map.PointType.CITY or \
		point_type == game_map.PointType.VILLAGE or \
		point_type == game_map.PointType.MOUNTAIN:
			points_to_process.append(i)

	print("Starting AI description generation for %d points..." % points_to_process.size())
	_process_points_batch(game_map, points_to_process, 0)


func _process_points_batch(game_map: GameMap, points: Array, current_index: int) -> void:
	"""Process points sequentially with rate limiting."""
	if current_index >= points.size():
		generation_in_progress = false
		description_generation_complete.emit(points.size())
		print("AI description generation complete!")
		return

	var point_id = points[current_index]
	description_generation_progress.emit(current_index + 1, points.size())

	var context = _build_point_context(game_map, point_id)
	var prompt = _build_description_prompt(point_id, context)

	# Generate description using say() and await the response signal
	say(prompt)
	var response = await response_received

	if response and response.length() > 0:
		game_map.point_properties[point_id]["ai_description"] = response
		_add_to_rag_system(game_map, point_id, response, context)
		print("Generated description for point %d (%s): %s..." % [point_id, context["name"], response.substr(0, 50)])

	# Rate limiting delay
	await get_tree().create_timer(0.5).timeout
	_process_points_batch(game_map, points, current_index + 1)

func _build_point_context(game_map: GameMap, point_id: int) -> Dictionary:
	"""Build context information about a point for AI analysis."""
	var context = {
					  "id": point_id,
					  "type": _get_type_name(game_map.point_types[point_id]),
					  "position": game_map.map_points[point_id],
					  "name": game_map.point_names[point_id],
					  "neighbors": [],
					  "nearby_features": {
						  "cities": 0,
						  "villages": 0,
						  "mountains": 0,
						  "water": 0,
						  "forests": 0
					  }
				  }

	# Build neighbor and feature information
	for connection in game_map.map_connections:
		var neighbor_id = -1
		if connection.idx1 == point_id:
			neighbor_id = connection.idx2
		elif connection.idx2 == point_id:
			neighbor_id = connection.idx1

		if neighbor_id >= 0 and not game_map.boundary_point_indices.has(neighbor_id):
			var neighbor_type = _get_type_name(game_map.point_types[neighbor_id])
			var distance = game_map.map_points[point_id].distance_to(game_map.map_points[neighbor_id])

			context["neighbors"].append({
				"id": neighbor_id,
				"type": neighbor_type,
				"name": game_map.point_names[neighbor_id],
				"distance": distance
			})

			# Count nearby features
			if context["nearby_features"].has(neighbor_type):
				context["nearby_features"][neighbor_type] += 1

	# Add special properties
	if game_map.point_types[point_id] == game_map.PointType.VILLAGE:
		context["population_density"] = game_map.village_densities[point_id]
	elif game_map.point_types[point_id] == game_map.PointType.WATER:
		context["is_deep_sea"] = game_map.point_properties[point_id].get("is_deep_sea", false)

	return context

func _build_description_prompt(point_id: int, context: Dictionary) -> String:
	"""Build a prompt for the AI to generate a location description."""
	var type_name = context["type"]
	var location_name = context["name"]

	var prompt = "Generate a brief, evocative 2-3 sentence description for '%s', a %s in a fantasy world. " % [location_name, type_name]

	# Add geographical context
	var nearby = context["nearby_features"]
	var geographical_notes = []

	if nearby["water"] > 0:
		geographical_notes.append("near water")
	if nearby["mountains"] > 0:
		geographical_notes.append("near mountains")
	if nearby["forests"] > 0:
		geographical_notes.append("surrounded by forests")

	if geographical_notes.size() > 0:
		prompt += "It is located %s. " % ", ".join(geographical_notes)

	# Add settlement-specific context
	if context.has("population_density"):
		if context["population_density"] > 0.7:
			prompt += "This is a thriving, densely populated settlement. "
		elif context["population_density"] < 0.4:
			prompt += "This is a quiet, sparsely populated settlement. "
		else:
			prompt += "This is a modest settlement. "

	# Add connectivity context
	if context["neighbors"].size() > 3:
		prompt += "It is a well-connected location with many trade routes. "
	elif context["neighbors"].size() <= 1:
		prompt += "It is an isolated, remote location. "

	prompt += "Focus on atmosphere, key features, and what makes it unique. Keep it concise for a RAG retrieval system."

	return prompt

func _add_to_rag_system(game_map: GameMap, point_id: int, description: String, context: Dictionary) -> void:
	"""Add the generated description to the RAG system for retrieval."""
	var metadata = {
					   "point_id": point_id,
					   "location_name": context["name"],
					   "type": context["type"],
					   "position": context["position"],
					   "neighbors": context["neighbors"].map(func(n): return n["name"])
				   }

	var tags = [context["type"], "location", "map_point"]

	# TODO: Integrate with your actual RAG system
	# Example: add_document(description, metadata, tags)

	print("Added to RAG: %s - %s" % [context["name"], description.substr(0, 50) + "..."])
