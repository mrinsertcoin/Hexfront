extends "res://tests/hotseat.gd"

var start_cell: int
var destination_cell: int

func _run() -> void:
	root.size = Vector2i(1152, 648)
	board = Main.instantiate() as PlanetBoard
	root.add_child(board)
	board._new_match("Hotseat")
	board.set_process(false)
	await process_frame
	await process_frame
	board.game_state.setup["simultaneous_combat"]=false; board.game_state.turn_state.simultaneous_combat_enabled=false; board._refresh_display()
	start_cell = board.game_state.units[2].cell_id
	destination_cell = board.rules.reachable(1, 2)[-1]
	check(board.animate_movement, "Movement presentation enabled by default")
	await _test_rig_playback()
	_test_waypoints()

	# Exercise the normal synthetic mouse route with real presentation enabled.
	click(_screen(start_cell))
	var path: Array[int] = board.rules.path_to(1, 2, destination_cell)
	var start: Vector3 = board.unit_views[2].position
	click(_screen(destination_cell), MOUSE_BUTTON_RIGHT)
	var view: EntityView = board.unit_views[2]
	check(path.size() > 2 and view.moving, "Accepted multi-hex command starts presentation")
	check(board.game_state.units[2].cell_id == destination_cell and board.game_state.units[2].moved, "Logical destination/action commits immediately")
	check(view.position == start, "Visual starts at the source instead of snapping to logical destination")
	check(board.end_turn_button.disabled and board.reachable_tiles.is_empty() and board.attack_tiles.is_empty(), "Gameplay controls wait for presentation")
	var committed: String = TestState.snapshot(board.game_state)
	board.request_end_turn()
	board.request_move_at(_screen(board.grid.get_neighbors(destination_cell)[0]))
	board.request_action_at(_screen(board.game_state.units[3].cell_id))
	board._begin_recruit("Scout", 100)
	check(TestState.snapshot(board.game_state) == committed, "Extra move, attack, recruitment, and end-turn requests cannot overlap playback")
	check(board.feedback_label.text.contains("finish"), "Busy input has readable feedback")
	board.clear_selection()
	board.select_at(_screen(board.game_state.units[2].cell_id))
	check(board.selected_unit_id == 2 and view.moving and view.position == start, "Permitted inspection and redraw preserve ongoing playback")
	view.advance_movement(0.1)
	check(view.position != start and view.position != view.destination, "Visual progresses between tiles")
	var intermediate: Vector3 = view.position
	board._refresh_display()
	check(view.position == intermediate, "HUD refresh never snaps an in-flight unit")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/movement_midway.png")
	view.advance_movement(100.0)
	check(not board.is_presenting() and not board.end_turn_button.disabled, "Finishing playback restores controls")
	check(view.position.is_equal_approx(board.terrain_surface.ground_position(board.grid.get_cell(destination_cell).up, board.SURFACE_OFFSET)), "Ground visual ends exactly on accepted destination")
	check(TestState.snapshot(board.game_state) == committed, "Presentation applies no additional gameplay changes")

	# Cancellation after state replacement/death must not leave the UI blocked.
	board._new_match("Hotseat")
	board.selected_unit_id = 2
	board.request_move_at(_screen(destination_cell))
	var old_view: EntityView = board.unit_views[2]
	board.game_state.units.erase(2)
	board._refresh_display()
	check(old_view.is_queued_for_deletion() and not board.is_presenting(), "Death removes playback and releases input lock")
	board.restart_match()
	board.selected_unit_id = 2
	board.request_move_at(_screen(destination_cell))
	old_view = board.unit_views[2]
	board.restart_match()
	await process_frame
	check(not is_instance_valid(old_view) and not board.is_presenting(), "Restart cancels obsolete view and playback")
	check(board.game_state.units[2].cell_id == start_cell and not board.end_turn_button.disabled, "Restart restores clean state and controls")

	# Real process ticks, not just manual advancement, must drive movement.
	board.selected_unit_id = 2
	board.request_move_at(_screen(destination_cell))
	view = board.unit_views[2]
	start = view.position
	await create_timer(0.05).timeout
	check(view.position != start, "Scene-tree processing advances movement automatically")
	view.advance_movement(100.0)

	# AI uses the identical presentation path and waits before its next command.
	board._new_match("Vs AI")
	board._ai_delay = 0.0
	for frame in range(40):
		await process_frame
		if board.is_presenting():
			break
	check(board.is_presenting(), "AI starts animated movement")
	committed = TestState.snapshot(board.game_state)
	await process_frame
	check(board.is_presenting() and TestState.snapshot(board.game_state) == committed, "AI issues no follow-up command during movement")
	for frame in range(100):
		for entity: EntityView in board.unit_views.values():
			entity.advance_movement(100.0)
		await process_frame
		if board.game_state.active_player == 1:
			break
	check(board.game_state.active_player == 1 and not board.is_presenting(), "Animated AI completes its turn")
	board.request_end_turn()
	for frame in range(40):
		await process_frame
		if board.is_presenting():
			break
	check(board.is_presenting(), "Second AI turn reaches movement")
	board._new_match("Hotseat")
	committed = TestState.snapshot(board.game_state)
	for frame in range(8):
		await process_frame
	check(not board._ai_running and not board.is_presenting() and TestState.snapshot(board.game_state) == committed, "New match invalidates an AI coroutine awaiting movement")
	board.queue_free()
	await process_frame
	print("Animation checks complete: waypoints, facing, rigs, input, AI, cancellation; failures=", failures)
	quit(0 if failures == 0 else 1)

func _test_waypoints() -> void:
	var entity := EntityView.new()
	var wrapper := UnitVisual.new()
	entity.add_child(wrapper)
	root.add_child(entity)
	entity.configure(wrapper)
	wrapper.move_speed = 1.0
	var path: Array[int] = board.grid.find_path(0, board.grid.breadth_first(0).order[-1])
	path.resize(3)
	var source: Vector3 = board.grid.get_cell(path[0]).up
	var corner: Vector3 = board.grid.get_cell(path[1]).up
	var goal: Vector3 = board.grid.get_cell(path[2]).up
	var radius: float = board.planet_radius + board.SURFACE_OFFSET
	entity.sync_position(source * radius)
	entity.play_path(path, board.grid, board.SURFACE_OFFSET)
	var leg: float = source.angle_to(corner) * radius
	var next_length: float = corner.angle_to(goal) * radius
	var expected: Vector3 = corner.slerp(goal, 0.25 / next_length) * radius
	entity.advance_movement(leg + 0.25)
	check(entity.position.is_equal_approx(expected), "Frame overshoot follows spherical corner without cutting through globe")
	check(entity.basis.y.dot(entity.position.normalized()) > 0.99999, "Local up follows sphere during motion")
	entity.advance_movement(100.0)
	check(entity.position.is_equal_approx(goal * radius) and not entity.moving, "Long frame finishes cleanly")
	entity.play_path(path, board.grid, board.SURFACE_OFFSET)
	var previous: Basis = entity.basis
	for step in range(100):
		entity.advance_movement((leg + 0.25) / 100.0)
		check(absf(entity.position.length() - radius) < 0.0001, "Every movement sample stays above sphere")
		check(entity.basis.y.dot(entity.position.normalized()) > 0.99999 and entity.basis.determinant() > 0.999, "Every movement frame remains radial and right handed")
		var rotation_dot: float = absf(previous.get_rotation_quaternion().dot(entity.basis.get_rotation_quaternion()))
		check(rotation_dot > cos(0.5 / 2.0), "No orientation flips between samples")
		previous = entity.basis
	check(entity.position.is_equal_approx(expected), "Frame-size independent spherical movement")
	entity.sync_position(Vector3.DOWN * radius)
	check(not entity.moving and entity.basis.y.is_equal_approx(Vector3.DOWN), "External relocation cancels movement and aligns bottom hemisphere")
	entity.free()

func _test_rig_playback() -> void:
	var wrapper := UnitVisual.new()
	var model := Node3D.new()
	model.name = "ModelRoot"
	model.scale = Vector3.ONE * 0.5
	wrapper.add_child(model)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("Body")
	model.add_child(skeleton)
	var player := AnimationPlayer.new()
	model.add_child(player)
	var library := AnimationLibrary.new()
	var walk := Animation.new()
	walk.length = 1.0
	var track: int = walk.add_track(Animation.TYPE_ROTATION_3D)
	walk.track_set_path(track, NodePath("Skeleton3D:Body"))
	walk.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	walk.rotation_track_insert_key(track, 1.0, Quaternion(Vector3.UP, PI / 2.0))
	library.add_animation(&"Walk", walk)
	library.add_animation(&"Idle", Animation.new())
	player.add_animation_library(&"Creature", library)
	root.add_child(wrapper)
	wrapper.initialize_animation()
	check(player.current_animation == "Creature/Idle", "Namespaced Idle automatically starts")
	wrapper.set_moving(true)
	check(player.current_animation == "Creature/Walk", "Namespaced Walk resolves to locomotion")
	player.advance(0.0)
	player.advance(0.5)
	# Skeleton pose updates are applied during scene-tree processing.
	await process_frame
	check(not skeleton.get_bone_pose_rotation(0).is_equal_approx(Quaternion.IDENTITY), "Imported-style bone animation track still resolves through the wrapper")
	check(walk.loop_mode == Animation.LOOP_NONE and player.get_animation(&"Creature/Walk").loop_mode == Animation.LOOP_LINEAR, "Loop configuration is isolated from shared imported resources")
	wrapper.set_moving(false)
	check(player.current_animation == "Creature/Idle" and model.scale == Vector3.ONE * 0.5, "Idle transition preserves authored ModelRoot transform")
	wrapper.free()
	# Explicit names and missing idle fallback.
	wrapper = UnitVisual.new()
	player = AnimationPlayer.new()
	wrapper.add_child(player)
	library = AnimationLibrary.new()
	library.add_animation(&"FrogJumpCycle", Animation.new())
	player.add_animation_library(&"", library)
	wrapper.move_clip = &"FrogJumpCycle"
	root.add_child(wrapper)
	wrapper.initialize_animation()
	wrapper.set_moving(true)
	check(player.current_animation == "FrogJumpCycle", "Explicit per-model clip mapping works")
	wrapper.set_moving(false)
	check(not player.is_playing(), "Missing idle stops locomotion safely")
	wrapper.free()
