extends "res://tests/hotseat.gd"

func _run() -> void:
	await setup()
	var world: GeneratedPlanet = board.generated_planet
	var topology: PlanetGrid = board.grid
	var topology_fingerprint: String = topology.fingerprint
	var gameplay: String = TestState.snapshot(board.game_state)
	check(world != null and world.cell_world_data.size() == board.grid.get_cell_count(), "Generated world integrated")
	check(board.generation_config.world_seed == 48293617 and world.config.world_generation_version == 1, "Default seed and world version displayed")
	check(not board.world_debug_panel.visible and not board.world_debug_view.visible, "Diagnostics unobtrusive by default")
	keypress(KEY_F6)
	check(board.world_debug_panel.visible and board.world_debug_panel.seed_edit.text == "48293617", "F6 opens seed controls")
	var cell_id: int = board.game_state.units[1].cell_id
	board.select_at(_screen(cell_id))
	check(board.world_debug_panel.inspector_label.text.contains("Cell %d | Region" % cell_id), "Selected cell diagnostics")
	for field: String in ["Height", "Temperature", "Moisture", "Fertility", "Terrain Roughness", "Dominant"]:
		check(board.world_debug_panel.inspector_label.text.contains(field), "Diagnostics include " + field)
	for mode in range(1, PlanetWorldDebugView.MODE_NAMES.size()):
		var fingerprint: String = board.generated_planet.generation_fingerprint
		board.set_world_debug_mode(mode)
		check(board.world_debug_view.visible and board.world_debug_view.mesh != null and board.world_debug_panel.mode_select.selected == mode, "World debug mode renders: " + PlanetWorldDebugView.MODE_NAMES[mode])
		check(board.generated_planet.generation_fingerprint == fingerprint and TestState.snapshot(board.game_state) == gameplay, "Switching views changes no world/game data")
		var arrays: Array = board.world_debug_view.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check(not colors.is_empty(), "Debug mesh has vertex colors")
		var varied: bool = false
		for color: Color in colors:
			if not color.is_equal_approx(colors[0]):
				varied = true
				break
		check(varied, "Debug view visibly varies: " + PlanetWorldDebugView.MODE_NAMES[mode])
	board.set_world_debug_mode(PlanetWorldDebugView.Mode.NORMAL)
	check(not board.world_debug_view.visible, "Normal mode hides debug surface")
	# Restart is match-only and retains exact generated object and data.
	board.restart_match()
	check(board.generated_planet == world and board.grid == topology and board.generated_planet.generation_fingerprint == world.generation_fingerprint, "Restart retains topology, seed, and generated planet object")
	# Same-seed explicit regeneration creates an identical data object without touching gameplay.
	gameplay = TestState.snapshot(board.game_state)
	board.regenerate_world(world.config.world_seed)
	check(board.generated_planet != world and board.generated_planet.generation_fingerprint == world.generation_fingerprint, "Same seed regenerates identical fingerprint")
	check(board.grid == topology and board.grid.fingerprint == topology_fingerprint and TestState.snapshot(board.game_state) == gameplay, "Regeneration leaves topology and gameplay unchanged")
	var same: GeneratedPlanet = board.generated_planet
	board.regenerate_world(246813579)
	check(board.generated_planet.generation_fingerprint != same.generation_fingerprint and board.generation_config.world_seed == 246813579, "Explicit different seed changes world")
	check(TestState.snapshot(board.game_state) == gameplay and board.grid == topology, "New procedural data has no gameplay effects")
	# Panel input validates signed 64-bit text before regeneration.
	var current: String = board.generated_planet.generation_fingerprint
	board.world_debug_panel.seed_edit.text = "not-a-seed"
	board.world_debug_panel._submit()
	check(board.generated_planet.generation_fingerprint == current and board.world_debug_panel.summary_label.text.contains("signed"), "Invalid seed input rejected")
	board.world_debug_panel.seed_edit.text = "9223372036854775808"
	board.world_debug_panel._submit()
	check(board.generated_planet.generation_fingerprint == current and board.world_debug_panel.summary_label.text.contains("range"), "Overflow seed rejected")
	board.world_debug_panel.seed_edit.text = "-42"
	board.world_debug_panel._submit()
	check(board.generation_config.world_seed == -42 and board.generated_planet.generation_fingerprint != current, "Panel applies signed seed")
	keypress(KEY_F7)
	check(board.world_debug_view.mode == PlanetWorldDebugView.Mode.HEIGHT, "F7 cycles generated field view")
	await finish("World UI")
