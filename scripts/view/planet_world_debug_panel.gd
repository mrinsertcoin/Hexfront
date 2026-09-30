class_name PlanetWorldDebugPanel
extends PanelContainer
signal seed_requested(seed_value: int)
signal new_seed_requested
signal mode_requested(mode_value: int)
var seed_edit: LineEdit
var mode_select: OptionButton
var summary_label: Label
var inspector_label: Label
var regenerate_button: Button
var new_seed_button: Button
var _inspected: int = -2
var _world: GeneratedPlanet
var _population_line: String=""

func _init() -> void:
	position = Vector2(18, 188)
	custom_minimum_size = Vector2(285, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "World diagnostics (F6)"
	column.add_child(title)
	mode_select = OptionButton.new()
	mode_select.focus_mode = Control.FOCUS_NONE
	for label: String in PlanetWorldDebugView.MODE_NAMES:
		mode_select.add_item(label)
	mode_select.item_selected.connect(func(index: int) -> void: mode_requested.emit(index))
	column.add_child(mode_select)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Signed integer seed"
	seed_edit.text_submitted.connect(func(_value: String) -> void: _submit())
	column.add_child(seed_edit)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	regenerate_button = Button.new()
	regenerate_button.text = "Apply / regenerate"
	regenerate_button.focus_mode = Control.FOCUS_NONE
	regenerate_button.pressed.connect(_submit)
	buttons.add_child(regenerate_button)
	new_seed_button = Button.new()
	new_seed_button.text = "New planet"
	new_seed_button.focus_mode = Control.FOCUS_NONE
	new_seed_button.pressed.connect(func() -> void: new_seed_requested.emit())
	buttons.add_child(new_seed_button)
	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 13)
	column.add_child(summary_label)
	inspector_label = Label.new()
	inspector_label.add_theme_font_size_override("font_size", 13)
	column.add_child(inspector_label)

func _submit() -> void:
	var input: String = seed_edit.text.strip_edges()
	if not input.is_valid_int():
		summary_label.text = "Enter a signed 64-bit integer seed."
		return
	var value: int = input.to_int()
	# Reject overflow/saturation; allow a leading plus sign and zero padding.
	var digits: String = input.trim_prefix("+").trim_prefix("-").lstrip("0")
	if digits.is_empty():
		digits = "0"
	var canonical: String = ("-" if input.begins_with("-") and digits != "0" else "") + digits
	if str(value) != canonical:
		summary_label.text = "Seed exceeds the signed 64-bit range."
		return
	seed_edit.release_focus()
	seed_requested.emit(value)

func show_world(world: GeneratedPlanet) -> void:
	_world = world
	seed_edit.text = str(world.config.world_seed)
	summary_label.text = "Grid v%d / World v%d | %d regions\nSeed %d | %.1f ms\nWorld %s..." % [
		world.grid_reference.grid_generation_version, world.config.world_generation_version,
		world.regions.size(), world.config.world_seed, world.generation_ms, world.generation_fingerprint.left(18)]
	if world.hydrology != null:
		summary_label.text += "\n%d basins | %d lakes | %d river segments" % [world.hydrology.basins.size(), world.hydrology.lakes.size(), world.hydrology.river_segments.size()]
	if not _population_line.is_empty(): summary_label.text+="\n"+_population_line
	_inspected = -2
	inspect_cell(-1)

func show_population(result: WorldPopulationResult,preset: String) -> void:
	_population_line="Population %s v%d | %d sites | %d groups | %.1f ms\n%s..." % [preset,result.generation_version,result.site_records.size(),result.neutral_group_records.size(),result.generation_ms,result.fingerprint.left(18)]
	if _world!=null: show_world(_world)

func inspect_cell(id: int) -> void:
	if id == _inspected or _world == null:
		return
	_inspected = id
	var data: PlanetWorldCellData = _world.get_cell(id)
	if data == null:
		inspector_label.text = "Hover or select a cell to inspect."
		return
	var lines: PackedStringArray = ["Cell %d | Region %d" % [id, data.region_id], "Height: %.3f" % data.height,
		"Temperature: %.3f" % data.temperature, "Base Moisture: %.3f" % data.base_moisture,
		"Effective Moisture: %.3f" % data.effective_moisture, "Fertility: %.3f" % data.fertility,
		"Terrain Roughness: %.3f" % data.terrain_roughness]
	if data.hydrology != null:
		var h: HydrologyCellData = data.hydrology
		lines.append_array(["Runoff: %.3f | Accumulation: %.3f" % [h.runoff_input, h.flow_accumulation],
			"Downstream: %d | Basin: %d" % [h.downstream_cell_id, h.basin_id],
			"Lake: %d | River: %s | Order: %d" % [h.lake_id, HydrologyCellData.RiverClass.keys()[h.river_class], h.stream_order],
			"Hydrology moisture: %.3f | Wetland: %.3f" % [h.hydrology_moisture_bonus, h.wetland_potential]])
		if h.lake_id >= 0:
			var lake: LakeData = _world.hydrology.lakes[h.lake_id]
			lines.append("Lake %d | %d cells | Surface %.3f" % [lake.id, lake.cell_ids.size(), lake.surface_height])
			lines.append("Terminal: %s | Outlet: %d | Catchment %.3f" % ["yes" if lake.terminal else "no", lake.outflow_cell_id, lake.catchment_size])
	lines.append("Dominant: " + data.dominant_biome)
	for i in range(data.biome_weights.size()):
		lines.append("  %s: %.1f%%" % [_world.config.biomes[i].biome_id, 100 * data.biome_weights[i]])
	inspector_label.text = "\n".join(lines)
