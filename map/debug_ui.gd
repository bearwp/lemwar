
extends CanvasLayer
class_name DebugUI

@export var map: GameMap

var panel: Panel
var vbox_container: VBoxContainer
var stats_container: VBoxContainer
var is_open: bool = true

func _ready() -> void:
	# Find the map node in the parent's parent (Game scene)
	map = get_parent().get_node("Map")
	if map == null:
		print("ERROR: Could not find Map node!")
		return
	_create_ui()
	await get_tree().process_frame
	_update_stats()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			is_open = !is_open
			panel.visible = is_open
			get_tree().root.set_input_as_handled()

func _create_ui() -> void:
	# Main panel
	panel = Panel.new()
	panel.custom_minimum_size = Vector2(350, 800)
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.offset_left = -360
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = 10
	add_child(panel)

	# Main container with scroll
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

	# Title
	var title = Label.new()
	title.text = "MAP DEBUG UI (F1 to toggle)"
	title.add_theme_font_size_override("font_size", 16)
	vbox_container.add_child(title)

	# Separator
	var sep1 = HSeparator.new()
	vbox_container.add_child(sep1)

	# Generate button
	var generate_btn = Button.new()
	generate_btn.text = "Generate New Map"
	generate_btn.custom_minimum_size = Vector2(0, 40)
	generate_btn.pressed.connect(_on_generate_pressed)
	vbox_container.add_child(generate_btn)

	# Separator
	var sep2 = HSeparator.new()
	vbox_container.add_child(sep2)

	# Parameters section
	var params_label = Label.new()
	params_label.text = "GENERATION PARAMETERS"
	params_label.add_theme_font_size_override("font_size", 12)
	vbox_container.add_child(params_label)

	# num_points slider
	_add_slider("Num Points", "num_points", 50, 300, 1)

	# num_cities slider
	_add_slider("Num Cities", "num_cities", 1, 20, 1)

	# num_mountains slider
	_add_slider("Num Mountains", "num_mountains", 0, 15, 1)

	# num_water_sources slider
	_add_slider("Water Sources", "num_water_sources", 1, 20, 1)

	# water_expansion_chance slider
	_add_slider("Water Expansion", "water_expansion_chance", 0.0, 1.0, 0.05)

	# min_distance slider
	_add_slider("Min Distance", "min_distance", 20.0, 150.0, 5.0)

	# max_water_connection_distance slider
	_add_slider("Water Range", "max_water_connection_distance", 20.0, 200.0, 5.0)

	# boundary_padding slider
	_add_slider("Boundary Padding", "boundary_padding", 50.0, 200.0, 10.0)

	# village_deletion_chance slider
	_add_slider("Village Deletion", "village_deletion_chance", 0.0, 1.0, 0.05)

	# settlement_connection_deletion_chance slider
	_add_slider("Connection Deletion", "settlement_connection_deletion_chance", 0.0, 1.0, 0.05)

	# Separator for new features
	var sep_features = HSeparator.new()
	vbox_container.add_child(sep_features)

	var features_label = Label.new()
	features_label.text = "TERRAIN FEATURES"
	features_label.add_theme_font_size_override("font_size", 12)
	vbox_container.add_child(features_label)

	# num_rivers slider
	_add_slider("Num Rivers", "num_rivers", 0, 10, 1)

	# river_branch_chance slider
	_add_slider("River Branch %", "river_branch_chance", 0.0, 1.0, 0.05)

	# river_max_length slider
	_add_slider("River Max Length", "river_max_length", 5, 30, 1)

	# forest_coverage slider
	_add_slider("Forest Coverage", "forest_coverage", 0.0, 0.5, 0.05)

	# forest_clusters slider
	_add_slider("Forest Clusters", "forest_clusters", 1, 15, 1)

	# Separator
	var sep3 = HSeparator.new()
	vbox_container.add_child(sep3)

	# Stats section
	var stats_label = Label.new()
	stats_label.text = "GENERATION STATS"
	stats_label.add_theme_font_size_override("font_size", 12)
	vbox_container.add_child(stats_label)

	# Stats container (will be updated)
	stats_container = VBoxContainer.new()
	stats_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.add_child(stats_container)

	# Add refresh button at bottom
	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh Stats"
	refresh_btn.pressed.connect(_update_stats)
	vbox_container.add_child(refresh_btn)

	# Toggle Voronoi debug
	var voronoi_btn = Button.new()
	voronoi_btn.text = "Toggle Voronoi Debug"
	voronoi_btn.pressed.connect(_on_toggle_voronoi)
	vbox_container.add_child(voronoi_btn)

	# Add spacer at end
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox_container.add_child(spacer)

func _add_slider(label_text: String, property: String, min_val: float, max_val: float, step: float) -> void:
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 30)
	vbox_container.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = map.get(property)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value):
		map.set(property, value)
		_update_value_label(hbox, value, step)
		)
	hbox.add_child(slider)
	
	var value_label = Label.new()
	value_label.text = _format_value(map.get(property), step)
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

func _update_value_label(hbox: HBoxContainer, value: float, step: float) -> void:
	var value_label = hbox.get_child(2)
	value_label.text = _format_value(value, step)

func _format_value(value: float, step: float) -> String:
	if step < 1.0:
		return "%.2f" % value
	else:
		return "%d" % int(value)

func _on_generate_pressed() -> void:
	print("Generating new map...")
	map.generate_new_map()
	_update_stats()
	print("Map generation complete!")

func _update_stats() -> void:
	if stats_container == null:
		print("Stats container not ready yet")
		return

	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()

	# Count terrain types
	var city_count = 0
	var village_count = 0
	var water_count = 0
	var mountain_count = 0
	var boundary_count = 0
	var deep_sea_count = 0

	for i in range(map.map_points.size()):
		if map.boundary_point_indices.has(i):
			boundary_count += 1
		else:
			match map.point_types[i]:
				map.PointType.CITY:
					city_count += 1
				map.PointType.VILLAGE:
					village_count += 1
				map.PointType.WATER:
					water_count += 1
					if map.point_properties[i].get("is_deep_sea", false):
						deep_sea_count += 1
				map.PointType.MOUNTAIN:
					mountain_count += 1

	# Count edge features
	var shoreline_count = 0
	var river_count = 0
	var forest_count = 0

	for edge in map.voronoi_edges:
		if edge.is_shoreline:
			shoreline_count += 1
		if edge.edge_type == map.EdgeType.RIVER:
			river_count += 1
		if edge.edge_type == map.EdgeType.FOREST:
			forest_count += 1

	# Add stat labels
	_add_stat_label(stats_container, "Total Points", map.map_points.size())
	_add_stat_label(stats_container, "Interior Points", map.map_points.size() - boundary_count)
	_add_stat_label(stats_container, "Boundary Points", boundary_count)
	_add_stat_label(stats_container, "Cities", city_count)
	_add_stat_label(stats_container, "Villages", village_count)
	_add_stat_label(stats_container, "Water Tiles", water_count)
	_add_stat_label(stats_container, "Deep Sea Tiles", deep_sea_count)
	_add_stat_label(stats_container, "Mountains", mountain_count)
	_add_stat_label(stats_container, "Connections", map.map_connections.size())
	_add_stat_label(stats_container, "Voronoi Edges", map.voronoi_edges.size())
	_add_stat_label(stats_container, "Shorelines", shoreline_count)
	_add_stat_label(stats_container, "River Edges", river_count)
	_add_stat_label(stats_container, "Forest Edges", forest_count)

	# Map size
	_add_stat_label(stats_container, "Map Size", "%.0fx%.0f" % [map.map_size.x, map.map_size.y])

	# Cache info
	if map.terrain_colors_cache:
		_add_stat_label(stats_container, "Cache Size", "%dx%d" % [map.terrain_colors_cache.get_width(), map.terrain_colors_cache.get_height()])

func _add_stat_label(container: VBoxContainer, stat_name: String, value) -> void:
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 24)
	container.add_child(hbox)

	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(name_label)

	var value_label = Label.new()
	if value is String:
		value_label.text = value
	else:
		value_label.text = str(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

func _on_toggle_voronoi() -> void:
	map._on_toggle_voronoi_debug()
	_update_stats()
