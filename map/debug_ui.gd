extends CanvasLayer
class_name DebugUI

@export var map: GameMap
@export var world_chat: Node  # Reference to your AI chat system

var panel: Panel
var vbox_container: VBoxContainer
var stats_container: VBoxContainer
var ai_progress_label: Label
var ai_generate_button: Button
var is_open: bool = true

# Slider configuration for DRY principle
var slider_configs = [
					 # [label, property, min, max, step]
						 ["Num Points", "num_points", 50, 300, 1],
						 ["Num Cities", "num_cities", 1, 20, 1],
						 ["Num Mountains", "num_mountains", 0, 15, 1],
						 ["Water Sources", "num_water_sources", 1, 20, 1],
						 ["Water Expansion", "water_expansion_chance", 0.0, 1.0, 0.05],
						 ["Min Distance", "min_distance", 5.0, 150.0, 5.0],
						 ["Water Range", "max_water_connection_distance", 20.0, 200.0, 5.0],
						 ["Boundary Padding", "boundary_padding", 50.0, 200.0, 10.0],
						 ["Village Deletion", "village_deletion_chance", 0.0, 1.0, 0.05],
						 ["Connection Deletion", "settlement_connection_deletion_chance", 0.0, 1.0, 0.05],
					 ]

var terrain_slider_configs = [
								 ["Num Rivers", "num_rivers", 0, 10, 1],
								 ["River Branch %", "river_branch_chance", 0.0, 1.0, 0.05],
								 ["River Continuation", "river_continuation_chance", 5, 30, 1],
								 ["Forest Coverage", "forest_coverage", 0.0, 0.5, 0.05],
								 ["Forest Clusters", "forest_clusters", 1, 15, 1],
							 ]

func _ready() -> void:
	map = get_parent().get_node("Map")
	if map == null:
		print("ERROR: Could not find Map node!")
		return
	
	

# Connect to world_chat signals if available
	if world_chat:
		world_chat.description_generation_progress.connect(_on_ai_progress)
		world_chat.description_generation_complete.connect(_on_ai_complete)

	_create_ui()
	await get_tree().process_frame
	_update_stats()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		is_open = !is_open
		panel.visible = is_open
		get_tree().root.set_input_as_handled()

# ============================================================================
# UI CREATION
# ============================================================================

func _create_ui() -> void:
	_create_main_panel()
	_create_title_section()
	_create_generation_button()
	_create_parameters_section()
	_create_terrain_section()
	_create_stats_section()
	_create_debug_section()

func _create_main_panel() -> void:
	"""Create the main panel container."""
	panel = Panel.new()
	panel.custom_minimum_size = Vector2(350, 800)
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.offset_left = -360
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = 10
	add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 10
	scroll.offset_top = 10
	scroll.offset_right = -10
	scroll.offset_bottom = -10
	panel.add_child(scroll)

	vbox_container = VBoxContainer.new()
	vbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox_container)

func _create_title_section() -> void:
	"""Create the title and first separator."""
	var title = Label.new()
	title.text = "MAP DEBUG UI (F1 to toggle)"
	title.add_theme_font_size_override("font_size", 16)
	vbox_container.add_child(title)

	_add_separator()

func _create_generation_button() -> void:
	"""Create the generate new map button."""
	var generate_btn = Button.new()
	generate_btn.text = "Generate New Map"
	generate_btn.custom_minimum_size = Vector2(0, 40)
	generate_btn.pressed.connect(_on_generate_pressed)
	vbox_container.add_child(generate_btn)

	_add_separator()

func _create_parameters_section() -> void:
	"""Create generation parameters section."""
	_add_section_label("GENERATION PARAMETERS")
	for config in slider_configs:
		_add_slider(config[0], config[1], config[2], config[3], config[4])

func _create_terrain_section() -> void:
	"""Create terrain features section."""
	_add_separator()
	_add_section_label("TERRAIN FEATURES")
	for config in terrain_slider_configs:
		_add_slider(config[0], config[1], config[2], config[3], config[4])

func _create_stats_section() -> void:
	"""Create stats section."""
	_add_separator()
	_add_section_label("GENERATION STATS")

	stats_container = VBoxContainer.new()
	stats_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.add_child(stats_container)

	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh Stats"
	refresh_btn.pressed.connect(_update_stats)
	vbox_container.add_child(refresh_btn)

func _create_debug_section() -> void:
	"""Create debug and AI generation section."""
	var voronoi_btn = Button.new()
	voronoi_btn.text = "Toggle Voronoi Debug"
	voronoi_btn.pressed.connect(_on_toggle_voronoi)
	vbox_container.add_child(voronoi_btn)

	_add_separator()
	_add_section_label("AI GENERATION (RAG)")

	ai_generate_button = Button.new()
	ai_generate_button.text = "Generate Point Descriptions"
	ai_generate_button.custom_minimum_size = Vector2(0, 40)
	ai_generate_button.pressed.connect(_on_generate_ai_descriptions)
	vbox_container.add_child(ai_generate_button)

	ai_progress_label = Label.new()
	ai_progress_label.text = "Ready"
	ai_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox_container.add_child(ai_progress_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox_container.add_child(spacer)

# ============================================================================
# UI HELPERS
# ============================================================================

func _add_separator() -> void:
	"""Add a separator line."""
	vbox_container.add_child(HSeparator.new())

func _add_section_label(text: String) -> void:
	"""Add a section label."""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	vbox_container.add_child(label)

func _add_slider(label_text: String, property: String, min_val: float, max_val: float, step: float) -> void:
	"""Create and add a slider control."""
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 30)
	vbox_container.add_child(hbox)

	# Label
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)

	# Slider
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = map.get(property)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value):
		map.set(property, value)
		_update_slider_value_label(hbox, value, step)
		)
	hbox.add_child(slider)
	
	# Value label
	var value_label = Label.new()
	value_label.text = _format_value(map.get(property), step)
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

func _update_slider_value_label(hbox: HBoxContainer, value: float, step: float) -> void:
	"""Update the value label for a slider."""
	var value_label = hbox.get_child(2)
	value_label.text = _format_value(value, step)

func _format_value(value: float, step: float) -> String:
	"""Format a value based on step size."""
	return "%.2f" % value if step < 1.0 else "%d" % int(value)

func _add_stat_label(container: VBoxContainer, stat_name: String, value) -> void:
	"""Add a stat label to a container."""
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 24)
	container.add_child(hbox)

	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(name_label)

	var value_label = Label.new()
	value_label.text = str(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

# ============================================================================
# STATS UPDATE
# ============================================================================

func _update_stats() -> void:
	"""Update and display all map statistics."""
	if stats_container == null:
		print("Stats container not ready yet")
		return

	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()

	# Count terrain types
	var terrain_counts = _count_terrain_types()
	var shoreline_count = 0

	for edge in map.voronoi_edges:
		if edge.is_shoreline:
			shoreline_count += 1

	# Add stat labels
	_add_stat_label(stats_container, "Total Points", map.map_points.size())
	_add_stat_label(stats_container, "Interior Points", map.map_points.size() - terrain_counts["boundary"])
	_add_stat_label(stats_container, "Boundary Points", terrain_counts["boundary"])
	_add_stat_label(stats_container, "Cities", terrain_counts["cities"])
	_add_stat_label(stats_container, "Villages", terrain_counts["villages"])
	_add_stat_label(stats_container, "Water Tiles", terrain_counts["water"])
	_add_stat_label(stats_container, "Deep Sea Tiles", terrain_counts["deep_sea"])
	_add_stat_label(stats_container, "Mountains", terrain_counts["mountains"])
	_add_stat_label(stats_container, "Connections", map.map_connections.size())
	_add_stat_label(stats_container, "Voronoi Edges", map.voronoi_edges.size())
	_add_stat_label(stats_container, "Shorelines", shoreline_count)
	_add_stat_label(stats_container, "Map Size", "%.0fx%.0f" % [map.map_size.x, map.map_size.y])

	if map.terrain_colors_cache:
		_add_stat_label(stats_container, "Cache Size", "%dx%d" % [map.terrain_colors_cache.get_width(), map.terrain_colors_cache.get_height()])

func _count_terrain_types() -> Dictionary:
	"""Count all terrain types on the map."""
	var counts = {
					 "cities": 0,
					 "villages": 0,
					 "water": 0,
					 "mountains": 0,
					 "boundary": 0,
					 "deep_sea": 0
				 }

	for i in range(map.map_points.size()):
		if map.boundary_point_indices.has(i):
			counts["boundary"] += 1
		else:
			match map.point_types[i]:
				map.PointType.CITY:
					counts["cities"] += 1
				map.PointType.VILLAGE:
					counts["villages"] += 1
				map.PointType.WATER:
					counts["water"] += 1
					if map.point_properties[i].get("is_deep_sea", false):
						counts["deep_sea"] += 1
				map.PointType.MOUNTAIN:
					counts["mountains"] += 1

	return counts

# ============================================================================
# BUTTON CALLBACKS
# ============================================================================

func _on_generate_pressed() -> void:
	"""Generate a new map."""
	print("Generating new map...")
	map.generate_new_map()
	_update_stats()
	print("Map generation complete!")

func _on_toggle_voronoi() -> void:
	"""Toggle Voronoi debug display."""
	map._on_toggle_voronoi_debug()
	_update_stats()

func _on_generate_ai_descriptions() -> void:
	"""Trigger AI description generation."""
	if world_chat == null:
		print("ERROR: world_chat not assigned!")
		ai_progress_label.text = "ERROR: No world_chat"
		world_chat = State.world_chat
		return

	if world_chat.generation_in_progress:
		print("AI generation already in progress!")
		return

	ai_generate_button.disabled = true
	ai_progress_label.text = "Starting..."

	# Trigger the world_chat to do the work
	world_chat.generate_map_descriptions(map)

func _on_ai_progress(current: int, total: int) -> void:
	"""Called by world_chat signal as generation progresses."""
	ai_progress_label.text = "Processing %d/%d..." % [current, total]

func _on_ai_complete(points_processed: int) -> void:
	"""Called by world_chat signal when generation is complete."""
	ai_generate_button.disabled = false
	ai_progress_label.text = "Complete! %d points processed" % points_processed
	print("AI description generation finished from UI")
