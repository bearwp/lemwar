extends Area2D
class_name InteractivePoint

signal point_hovered(point_index: int)
signal point_unhovered(point_index: int)

var point_index: int = -1
var point_type: GameMap.PointType
var neighbors: Array[InteractivePoint] = []
var map_reference: GameMap # Reference to the GameMap node
var collision_shape_node: CollisionShape2D # Reference to the collision shape node

var is_hovered := false
var point_description: String = "Default Description" # Description for the point
var base_radius := 9.0 # Base radius for drawing
var hover_radius := 14.0 # Larger radius for hover

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Create collision shape for interaction
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = base_radius  # Match visual base radius
	collision.shape = shape
	collision_shape_node = collision # Store reference
	collision_layer = 3
	add_child(collision)

func setup(idx: int, type: GameMap.PointType, map: GameMap) -> void:
	point_index = idx
	point_type = type
	map_reference = map
	queue_redraw()

func has_path_to(other: InteractivePoint) -> bool:
	"""Check if there's a valid connection to another point"""
	if map_reference == null or other == null:
		return false
	
	for connection in map_reference.map_connections:
		if (connection.idx1 == point_index and connection.idx2 == other.point_index) or \
		   (connection.idx2 == point_index and connection.idx1 == other.point_index):
			return true
	
	return false

func get_point_name() -> String:
	"""Return the custom name for this point, or a default if not set."""
	if map_reference and point_index != -1 and point_index < map_reference.point_names.size():
		var custom_name = map_reference.point_names[point_index]
		if not custom_name.is_empty() and custom_name != ("Point %d" % point_index): # Check if it's not the default generated name
			return custom_name
		
	# Fallback to generic name if no custom name is set or it's the default
	var type_name := ""
	match point_type:
		GameMap.PointType.CITY: type_name = "City"
		GameMap.PointType.VILLAGE: type_name = "Village"
		GameMap.PointType.WATER: type_name = "Water"
		GameMap.PointType.MOUNTAIN: type_name = "Mountain"
		GameMap.PointType.FOREST: type_name = "Forest"
	
	return "%s #%d" % [type_name, point_index]

func _draw() -> void:
	"""Draw the point visual representation"""
	# Draw at local origin since node is already positioned
	var pos = Vector2.ZERO
	var current_radius = base_radius if not is_hovered else hover_radius
	
	match point_type:
		GameMap.PointType.CITY:
			draw_circle(pos, current_radius + 2, Color(0.25, 0.2, 0.2))
			draw_circle(pos, current_radius, Color(0.8, 0.35, 0.3))
			draw_circle(pos, current_radius - 3, Color(0.95, 0.55, 0.45))
		GameMap.PointType.VILLAGE:
			draw_circle(pos, current_radius - 4, Color(0.4, 0.35, 0.3))
			draw_circle(pos, current_radius - 6, Color(0.65, 0.6, 0.55))
		GameMap.PointType.FOREST:
			# Draw tree-like icon, scaled with radius
			var scale_factor = current_radius / base_radius
			var pts = PackedVector2Array([
				pos + Vector2(0, -7) * scale_factor, 
				pos + Vector2(-6, 3) * scale_factor, 
				pos + Vector2(6, 3) * scale_factor
			])
			draw_colored_polygon(pts, Color(0.15, 0.4, 0.15))
			draw_circle(pos + Vector2(0, -3) * scale_factor, 5 * scale_factor, Color(0.2, 0.55, 0.2))
			draw_circle(pos + Vector2(0, -3) * scale_factor, 3 * scale_factor, Color(0.3, 0.65, 0.25))
		GameMap.PointType.WATER:
			draw_circle(pos, current_radius - 2, Color(0.15, 0.28, 0.45))
			draw_circle(pos, current_radius - 4, Color(0.25, 0.42, 0.62))
			draw_circle(pos, current_radius - 6, Color(0.45, 0.60, 0.78))
		GameMap.PointType.MOUNTAIN:
			var scale_factor = current_radius / base_radius
			var pts = PackedVector2Array([
				pos + Vector2(0, -9) * scale_factor, 
				pos + Vector2(-8, 5) * scale_factor, 
				pos + Vector2(8, 5) * scale_factor
			])
			draw_colored_polygon(pts, Color(0.4, 0.35, 0.3))
			pts = PackedVector2Array([
				pos + Vector2(0, -7) * scale_factor, 
				pos + Vector2(-4, 2) * scale_factor, 
				pos + Vector2(4, 2) * scale_factor
			])
			draw_colored_polygon(pts, Color(0.6, 0.55, 0.5))
	
	# No separate highlight; the scaling implicitly highlights
	# if is_hovered:
	#	draw_circle(pos, current_radius, Color(1.0, 1.0, 0.0, 0.3))

func _on_mouse_entered() -> void:
	is_hovered = true
	# Dynamically resize collision shape
	if collision_shape_node:
		(collision_shape_node.shape as CircleShape2D).radius = hover_radius
	point_hovered.emit(point_index)
	queue_redraw()
	_show_tooltip()

func _on_mouse_exited() -> void:
	is_hovered = false
	# Dynamically resize collision shape back to base
	if collision_shape_node:
		(collision_shape_node.shape as CircleShape2D).radius = base_radius
	point_unhovered.emit(point_index)
	queue_redraw()

	_hide_tooltip()

func _show_tooltip() -> void:
	var tooltip_text = get_point_name()
	
	# Add neighbor count
	var connected_neighbors = 0
	for neighbor in neighbors:
		if has_path_to(neighbor):
			connected_neighbors += 1
	
	if connected_neighbors > 0:
		tooltip_text += "\n" + str(connected_neighbors) + " connections\n" + str(point_description)

	
	# Show tooltip at mouse position
	var tooltip = _get_or_create_tooltip()
	tooltip.text = tooltip_text
	tooltip.global_position = get_global_mouse_position() + Vector2(15, 15)
	tooltip.visible = true

func _hide_tooltip() -> void:
	var tooltip = _get_or_create_tooltip()
	tooltip.visible = false

func _get_or_create_tooltip() -> Label:
	var root = get_tree().root
	var tooltip = root.get_node_or_null("Tooltip")
	
	if tooltip == null:
		tooltip = Label.new()
		tooltip.name = "Tooltip"
		tooltip.z_index = 1000
		tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Style the tooltip
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		style.border_color = Color(0.8, 0.8, 0.8, 1.0)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		
		tooltip.add_theme_stylebox_override("normal", style)
		tooltip.add_theme_color_override("font_color", Color.WHITE)
		tooltip.visible = false
		
		root.add_child(tooltip)
	
	return tooltip
