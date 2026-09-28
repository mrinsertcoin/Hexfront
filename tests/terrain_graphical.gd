extends "res://tests/hotseat.gd"

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/8d_"+label+".png")==OK,"Capture saved")

func _run() -> void:
	await setup(true,4 if "--dense" in OS.get_cmdline_user_args() else 3)
	for seed_value: int in [48293617,246813579,-42]:
		if board.generated_planet.config.world_seed != seed_value: board.regenerate_world(seed_value)
		board._reset_camera()
		board.feedback_label.text=""
		board.navigation.distance=16; board.navigation.target_distance=16; board._update_camera_transform(0)
		await capture("terrain_%d_overview" % seed_value)
		board.navigation.distance=4; board.navigation.target_distance=4; board._update_camera_transform(0)
		await capture("terrain_%d_close" % seed_value)
		for lake: LakeData in board.generated_planet.hydrology.lakes:
			board.focus_cell(lake.cell_ids[0],true)
			await capture("terrain_%d_lake" % seed_value)
			break
		for pole: float in [-89.9,89.9]:
			_globe_pose(0, pole, 4)
			await capture("terrain_%d_pole_%d" % [seed_value,int(pole)])
	board._reset_camera()
	board.navigation.distance=6; board.navigation.target_distance=6
	board._update_camera_transform(0)
	board.select_at(_screen(board.game_state.units[2].cell_id))
	await capture("terrain_overlays")
	board.clear_selection()
	# Production materials/geometry are deterministic as well as debug colors.
	board.feedback_label.text=""
	await capture("production_identity_before")
	var before: Image=root.get_texture().get_image()
	board.regenerate_world(board.generated_planet.config.world_seed)
	board.feedback_label.text=""
	await capture("production_identity_after")
	check(before.get_data()==root.get_texture().get_image().get_data(),"Same seed production rendering is pixel-identical")
	var material: ShaderMaterial=board.terrain_renderer.chunks[0].material_override
	material.set_shader_parameter("wet_strength",0.0)
	await capture("wetness_disabled")
	check(before.get_data()!=root.get_texture().get_image().get_data(),"Hydrology wetness changes rendered ground")
	material.set_shader_parameter("wet_strength",board.terrain_config.wetness_strength)
	material.set_shader_parameter("rock_strength",0.0)
	await capture("slope_rock_disabled")
	check(before.get_data()!=root.get_texture().get_image().get_data(),"Slope exposure changes rendered rock contribution")
	material.set_shader_parameter("rock_strength",board.terrain_config.slope_rock_strength)
	var frames: Array[float]=[]
	for i in range(180):
		var started: int=Time.get_ticks_usec()
		board.navigation.yaw+=0.5; board._update_camera_transform(0)
		await process_frame
		frames.append((Time.get_ticks_usec()-started)/1000.0)
	frames.sort()
	print("8D renderer profile cells=",board.grid.cells.size()," triangles=",board.terrain_renderer.triangle_count," median_ms=",frames[90]," p95_ms=",frames[171]," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	await finish("Terrain graphical")
