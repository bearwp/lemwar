extends Area2D
class_name InteractivePath

const PATH_COLLISION_WIDTH = 5.0 # Adjust this value as needed for hover accuracy

signal path_hovered(from_idx: int, to_idx: int)
signal path_unhovered()

var from_point: InteractivePoint
var to_point: InteractivePoint
var voronoi_point: Vector2
var connection_data: Dictionary

var is_hovered := false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	

func setup(from: InteractivePoint, to: InteractivePoint, voronoi_pos: Vector2, conn_data: Dictionary) -> void:
	from_point = from
	to_point = to
	voronoi_point = voronoi_pos
	connection_data = conn_data
	
	global_position = voronoi_point # Position the node at the voronoi point
	
	# Defer collision creation until after the scene tree is ready
	# This ensures parent transforms are properly set
	call_deferred("_create_path_collision")
	queue_redraw()



func _create_path_collision() -> void:
	"""Create two CapsuleShape2D nodes to accurately represent the bent path with thickness and rounded ends."""
	if from_point == null or to_point == null:
		return

	# Clear existing collision shapes
	for child in get_children():
		if child is CollisionShape2D:
			child.queue_free()

	var from_pos_local = to_local(from_point.global_position)
	var to_pos_local = to_local(to_point.global_position)
	var voronoi_pos_local = Vector2.ZERO # This node's global_position is voronoi_point

	var half_width = PATH_COLLISION_WIDTH / 2.0

	# Create first capsule from from_point to voronoi_point
	_add_capsule_segment_collision(from_pos_local, voronoi_pos_local, half_width)

	# Create second capsule from voronoi_point to to_point
	_add_capsule_segment_collision(voronoi_pos_local, to_pos_local, half_width)

func _add_capsule_segment_collision(start_point_local: Vector2, end_point_local: Vector2, half_width: float) -> void:
	var collision_shape = CollisionShape2D.new()
	var capsule_shape = CapsuleShape2D.new()

	var segment_vector = end_point_local - start_point_local
	var segment_length = segment_vector.length()

	# Ensure segment has length to avoid errors with normalization or zero-height capsules
	if segment_length == 0:
		return

	capsule_shape.radius = half_width
	capsule_shape.height = segment_length + PATH_COLLISION_WIDTH # Add width for rounded caps overlap
	collision_shape.shape = capsule_shape

	# Position the capsule at the midpoint of the segment
	collision_shape.position = (start_point_local + end_point_local) / 2.0

	# Rotate the capsule to align with the segment
	collision_shape.rotation = segment_vector.angle() + PI / 2.0 # Capsules are vertical by default

	add_child(collision_shape)


func _draw() -> void:
	"""Draw the path connection"""
	if from_point == null or to_point == null:
		return
	
	# Convert global positions to local space of this node
	var from_pos = to_local(from_point.global_position)
	var to_pos = to_local(to_point.global_position)
	var voronoi_pos_local = Vector2.ZERO # Since this node is at voronoi_point global_position
	
	var type1 = from_point.point_type
	var type2 = to_point.point_type
	
	# Forest connections are green
	if type1 == GameMap.PointType.FOREST or type2 == GameMap.PointType.FOREST:
		var color = Color(0.2, 0.7, 0.3, 0.3 if not is_hovered else 0.6)
		draw_line(from_pos, voronoi_pos_local, color, 3.0)
		draw_line(voronoi_pos_local, to_pos, color, 3.0)
	elif type1 == GameMap.PointType.WATER or type2 == GameMap.PointType.WATER:
		# Draw two-segment dashed line through Voronoi point
		var color1 = Color(0.5803922, 0.7372549, 0.9019608, 0.6 if not is_hovered else 0.9)
		var color2 = Color(0.65882355, 0.80784315, 0.9529412, 0.6 if not is_hovered else 0.9)
		_draw_dashed_line(from_pos, voronoi_pos_local, color1, 2.5, 8.0, 6.0)
		_draw_dashed_line(voronoi_pos_local, to_pos, color2, 2.5, 8.0, 6.0)
	elif type1 == GameMap.PointType.CITY and type2 == GameMap.PointType.CITY:
		# Highway through Voronoi point
		var width = 5.5 if not is_hovered else 7.0
		var color = Color(0.4, 0.25, 0.15, 0.7 if not is_hovered else 1.0)
		draw_line(from_pos, voronoi_pos_local, color, width)
		draw_line(voronoi_pos_local, to_pos, color, width)
	else:
		# Regular road through Voronoi point
		var width = 3.5 if not is_hovered else 5.0
		var color = Color(0.63, 0.38, 0.15, 0.7 if not is_hovered else 1.0)
		draw_line(from_pos, voronoi_pos_local, color, width)
		draw_line(voronoi_pos_local, to_pos, color, width)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var dir = (to - from).normalized()
	var dist = from.distance_to(to)
	var current = 0.0
	while current < dist:
		var start = from + dir * current
		var end = from + dir * min(current + dash, dist)
		draw_line(start, end, color, width)
		current += dash + gap

func _on_mouse_entered() -> void:
	is_hovered = true
	if from_point and to_point:
		path_hovered.emit(from_point.point_index, to_point.point_index)
		queue_redraw()
		_show_tooltip()

func _on_mouse_exited() -> void:
	is_hovered = false
	path_unhovered.emit()
	queue_redraw()
	_hide_tooltip()

func _show_tooltip() -> void:
	if from_point == null or to_point == null:
		return
	
	var tooltip_text = "%s → %s" % [from_point.get_point_name(), to_point.get_point_name()]
	
	# Add edge type info
	var edge_type = connection_data.get("edge_type", GameMap.EdgeType.PATH)
	
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
