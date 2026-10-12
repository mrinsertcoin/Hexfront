extends "res://tests/hotseat.gd"

func capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png("res://.godot/8d_" + label + ".png") == OK, "Graphical capture saved")
	return image

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run graphical_smoke without --headless")
		quit(1)
		return
	await setup(true, 4 if "--dense" in OS.get_cmdline_user_args() else 3)
	await capture("initial")
	# Inspect every generated-data view on real Compatibility rendering.
	for mode in range(PlanetWorldDebugView.Mode.HEIGHT, PlanetWorldDebugView.Mode.WETLAND_POTENTIAL + 1):
		board.set_world_debug_mode(mode)
		await capture("world_" + PlanetWorldDebugView.MODE_NAMES[mode].to_lower().replace(" ", "_"))
	check(board.generated_planet.validation_errors.is_empty(), "Displayed world remains valid")
	board.set_world_debug_mode(PlanetWorldDebugView.Mode.HEIGHT)
	# The panel reports nondeterministic generation duration; exclude it from the
	# pixel identity check so the comparison covers the generated rendering.
	board.world_debug_panel.visible = false
	var seed: int = board.generated_planet.config.world_seed
	var fingerprint: String = board.generated_planet.generation_fingerprint
	var same_before: Image = await capture("same_seed_before")
	board.regenerate_world(seed)
	board.feedback_label.text = ""
	board.feedback_seconds = 0.0
	var same_after: Image = await capture("same_seed_after")
	check(board.generated_planet.generation_fingerprint == fingerprint and same_before.get_data() == same_after.get_data(), "Same-seed regeneration is visually and logically identical")
	board.regenerate_world(seed + 1)
	board.feedback_label.text = ""
	board.feedback_seconds = 0.0
	var different: Image = await capture("different_seed")
	check(board.generated_planet.generation_fingerprint != fingerprint and same_after.get_data() != different.get_data(), "Different seed visibly changes generated world")
	for quality_seed: int in [seed, 246813579, -42]:
		board.regenerate_world(quality_seed)
		check(board.generated_planet.hydrology.lakes.size() > 0 and board.generated_planet.hydrology.river_segments.size() > 0, "Representative seed has lakes and rivers")
		board.set_world_debug_mode(PlanetWorldDebugView.Mode.RIVERS)
		await capture("rivers_seed_" + str(quality_seed).replace("-", "negative_"))
		board.set_world_debug_mode(PlanetWorldDebugView.Mode.LAKES)
		await capture("lakes_seed_" + str(quality_seed).replace("-", "negative_"))
	board.focus_cell(board.grid.breadth_first(0).order[-1], true)
	board.set_world_debug_mode(PlanetWorldDebugView.Mode.HEIGHT)
	await capture("height_opposite_hemisphere")
	board.regenerate_world(seed)
	board.set_world_debug_mode(PlanetWorldDebugView.Mode.NORMAL)
	board._reset_camera()
	board.navigation.distance = 5.0
	board.navigation.target_distance = 5.0
	click(_screen(board.game_state.units[2].cell_id))
	var destination: int = board.rules.reachable(1, 2)[-1]
	board.update_hover_at(_screen(destination, false))
	check(not board.preview_path.is_empty(), "Graphical hover path")
	await capture("path")
	click(_screen(destination, false), MOUSE_BUTTON_RIGHT)
	var view: EntityView = board.unit_views[2]
	view.set_process(false)
	view.advance_movement(0.35)
	check(view.moving and view.position.length() > board.planet_radius, "Graphical surface movement")
	await capture("movement")
	view.advance_movement(100)
	board.restart_match()
	# Pixel comparison verifies actual depth occlusion, including bars and overlays.
	var rear: int = board.game_state.structures[101].cell_id
	board.selected = rear
	board._refresh_tile_materials()
	var visible_rear: Image = await capture("occlusion_before")
	for id: int in [3, 4, 6, 101]:
		board.unit_views[id].visible = false
	board.tiles[rear].visible = false
	var hidden_rear: Image = await capture("occlusion_after")
	check(visible_rear.get_data() == hidden_rear.get_data(), "Far-side units, HQ, bars and overlay contribute no visible pixels")
	for id: int in [3, 4, 6, 101]:
		board.unit_views[id].visible = true
	board.clear_selection()
	board.focus_cell(rear, true)
	board.navigation.distance = 5.0
	board._update_camera_transform(0)
	await capture("opposite_close")
	board.navigation.distance = 36.0
	board._update_camera_transform(0)
	keypress(KEY_F2)
	await capture("overview_pentagons")
	board.navigation.distance = 16.0
	board.navigation.target_distance = 16.0
	board.set_process(true)
	var samples: Array[float] = []
	for frame in range(180):
		var start: int = Time.get_ticks_usec()
		board.navigation.target_yaw += 2.0
		await process_frame
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("Graphical performance cells=", board.grid.get_cell_count(), " median_frame_ms=", samples[90], " p95_frame_ms=", samples[171], " scene_nodes=", get_node_count())
	board.set_process(false)
	board._new_match("Vs AI")
	board._ai_delay = 0.0
	for frame in range(300):
		for entity: EntityView in board.unit_views.values():
			entity.advance_movement(100)
		await process_frame
		if board.game_state.active_player == 1 and not board._ai_running:
			break
	check(board.game_state.active_player == 1 and not board._ai_running, "Graphical AI returns control")
	board._new_match("Hotseat")
	check(board.unit_views.size() == 8 and board.game_state.materials == {1: 11, 2: 8}, "Graphical restart")
	await finish("Graphical globe")
