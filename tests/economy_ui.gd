extends "res://tests/hotseat.gd"
const Snapshot = preload("res://tests/test_state.gd")

func _run() -> void:
	root.size = Vector2i(1152, 648)
	board = Main.instantiate() as PlanetBoard
	# Instant presentation keeps this rules/input regression suite synchronous.
	board.animate_movement = false
	root.add_child(board)
	board._new_match("Hotseat")
	board.set_process(false)
	await process_frame
	await process_frame
	var initial: String = Snapshot.snapshot(board.game_state)
	for repeat in range(3):
		board._refresh_display()
	check(Snapshot.snapshot(board.game_state) == initial, "Redraw grants no income")
	check(board.materials_label.text.contains("P1 11 | P2 8"), "Both material balances displayed")
	click(_screen(board.game_state.structures[100].cell_id))
	await process_frame
	check(board.selected_structure_id == 100, "HQ selectable")
	var button: Button = board.recruit_box.get_node("RecruitScout") as Button
	click(button.get_global_rect().get_center())
	check(board.placement_mode and board.recruit_hq_id == 100 and board.recruit_choice == "Scout", "Recruit button enters placement")
	click(_screen(board.grid.get_neighbors(0)[3]), MOUSE_BUTTON_RIGHT)
	check(not board.placement_mode and Snapshot.snapshot(board.game_state) == initial, "Right-click press/release cancels without attack or charge")
	check(not board.tiles[board.grid.get_neighbors(0)[3]].visible, "Cancel removes placement highlight")
	board._begin_recruit("Scout", 100)
	keypress(KEY_ESCAPE)
	check(not board.placement_mode and board.recruit_highlights.is_empty(), "Escape cancels placement")
	board._begin_recruit("Scout", 100)
	var count_before: int = board.game_state.units.size()
	click(_screen(board.grid.get_neighbors(0)[3]))
	check(board.game_state.units.size() == count_before + 1 and board.game_state.materials[1] == 8, "One press/release recruits and charges once")
	check(board.selected_structure_id == 100 and board.selected_unit_id == -1 and not board.placement_mode, "Release does not reselect newly recruited unit")
	var recruit: GameState.Unit = board.game_state.unit_at(board.grid.get_neighbors(0)[3])
	click(_screen(board.grid.get_neighbors(0)[3]))
	check(board.selected_unit_id == recruit.id and board.unit_label.text.contains("Ready next turn"), "Recruit readiness label")
	check(board.recruit_box.get_child_count() == 0, "Switching from HQ to unit clears recruit buttons")
	click(_screen(board.game_state.structures[100].cell_id))
	keypress(KEY_ESCAPE)
	check(board.selected_structure_id == -1 and board.selected == board.NONE, "Escape clears HQ selection")
	board.restart_match()
	click(_screen(board.game_state.structures[100].cell_id))
	board._begin_recruit("Scout", 100)
	click(board.end_turn_button.get_global_rect().get_center())
	check(not board.placement_mode and board.selected_structure_id == -1 and board.game_state.active_player == 2, "End turn cancels HQ placement")
	board.restart_match()
	click(_screen(board.game_state.structures[100].cell_id))
	board._begin_recruit("Scout", 100)
	board.navigation.target_yaw = 95.0
	board.navigation.target_pitch = 35.0
	board.navigation.target_distance = 13.0
	board.restart_match()
	check(not board.placement_mode and board.selected_structure_id == -1 and Snapshot.snapshot(board.game_state) == initial, "Restart clears pending recruitment")
	check(board.navigation.target_yaw == 0.0 and board.navigation.target_distance == board.camera_config.default_distance, "Restart resets complete surface rig")
	var camera_before: Transform3D = board.camera.transform
	board._process(0.05)
	check(board.camera.transform.is_equal_approx(camera_before), "Camera does not drift back after reset")
	board.navigation.yaw = 0
	board.navigation.target_yaw = 90
	board._process(0.01)
	check(board.navigation.yaw > 5.0 and board.navigation.yaw < 20.0, "Yaw interpolation uses radians correctly")
	keypress(KEY_HOME)
	check(board.navigation.target_yaw == 0.0 and board.camera.transform.is_equal_approx(camera_before), "Home restores surface state and transform")
	board.select_at(_screen(board.game_state.units[1].cell_id))
	var destination: int = board.reachable_tiles[0]
	board.update_hover_at(_screen(destination))
	check(board.tiles[destination].material_override == board.path_material, "Path color takes precedence over reachable color")

	# Rendering/inspection must never trigger AI actions.
	board._new_match("Vs AI")
	board.rules.try_end_turn(1)
	var before: String = Snapshot.snapshot(board.game_state)
	board._refresh_display()
	await process_frame
	check(Snapshot.snapshot(board.game_state) == before and not board._ai_running, "Redraw is side-effect free during AI turn")
	board.request_end_turn()
	check(Snapshot.snapshot(board.game_state) == before, "Human cannot skip AI turn")
	# Start AI, then restart while its coroutine is waiting; old work must stop.
	board._ai_delay = 0.0
	board._queue_ai_turn()
	await process_frame
	board._new_match("Hotseat")
	before = Snapshot.snapshot(board.game_state)
	for frame in range(5):
		await process_frame
	check(Snapshot.snapshot(board.game_state) == before and not board._ai_running, "Restart cancels queued/in-progress AI")
	board._new_match("Vs AI")
	board.request_end_turn()
	for frame in range(160):
		if board.game_state.active_player == 1 and not board._ai_running:
			break
		await process_frame
	check(board.game_state.active_player == 1 and not board._ai_running and not board.end_turn_button.disabled, "AI completes turn and restores human UI")
	check(board.game_state.units.size() == 7, "AI recruited once in its first turn")
	board._new_match("Hotseat")
	print("Economy/UI/camera/AI scheduling checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)

