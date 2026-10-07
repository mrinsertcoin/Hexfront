extends SceneTree
const Main = preload("res://scenes/game.tscn")
var failures: int = 0
var board: PlanetBoard

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func setup(animated: bool = false, level: int = 3) -> void:
	root.size = Vector2i(1152, 648)
	board = Main.instantiate() as PlanetBoard
	board.animate_movement = animated
	board.subdivision_level = level
	board.planet_radius = 12.0 * pow(2.0, level - 3)
	# Headless suites validate material structure and gameplay, not texture
	# fidelity. Keep their independent processes fast while graphical coverage
	# continues to exercise the production 512-pixel arrays.
	if DisplayServer.get_name() == "headless":
		board.terrain_config = TerrainRenderConfig.new()
	root.add_child(board)
	board._new_match("Hotseat")
	board.set_process(false)
	await process_frame
	await process_frame
	board.game_state.setup["simultaneous_combat"]=false; board.game_state.turn_state.combat_planning_enabled=false; board._refresh_display()

func _screen(cell: int, focus: bool = true) -> Vector2:
	if focus:
		board.focus_cell(cell, true)
	return board.camera.unproject_position(board.terrain_surface.sample_position(board.grid.get_cell(cell).up))

func click(position: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button_index
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button_index == MOUSE_BUTTON_LEFT else 0
		root.push_input(event, true)

func keypress(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func finish(label: String) -> void:
	board.queue_free()
	await process_frame
	print(label, " checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)

func _run() -> void:
	await setup()
	check(board.unit_views.size() == 8, "Six units and two HQ views")
	check(board.unit_views[1].get_node("visual_root/ModelRoot").get_child_count() == 1, "One imported model per wrapper")
	for player in [1, 2]:
		if board.privacy_overlay.visible:
			check(board.selected_unit_id==-1 and board.notification_feed.records.is_empty(),"Hotseat handoff clears private selection and notifications")
			click(board.privacy_overlay.get_node("PrivacyCenter/PrivacyColumn/ReadyButton").get_global_rect().get_center())
			check(not board.privacy_overlay.visible,"Incoming player explicitly reveals their perspective")
		var ids: Array = [1, 2] if player == 1 else [3, 4]
		for id: int in ids:
			click(_screen(board.game_state.units[id].cell_id))
			check(board.selected_unit_id == id and board.unit_label.text.contains("Ready"), "Select own ready unit")
			check(board.reachable_tiles == board.rules.reachable(player, id), "Highlights use rules destinations")
			for cell: int in board.reachable_tiles:
				check(board.tiles[cell].visible and board.tiles[cell].material_override == board.reachable_material, "Reachable overlay visible")
			var destination: int = board.reachable_tiles[0]
			board.update_hover_at(_screen(destination))
			check(board.preview_path == board.rules.path_to(player, id, destination), "Hover previews accepted path")
			click(_screen(destination), MOUSE_BUTTON_RIGHT)
			check(board.game_state.units[id].cell_id == destination and board.game_state.units[id].moved, "Mouse movement commits")
			check(board.unit_views[id].position.is_equal_approx(board.terrain_surface.sample_position(board.grid.get_cell(destination).up, board.SURFACE_OFFSET)), "View follows logical cell")
			check(board.reachable_tiles.is_empty() and board.unit_label.text.contains("Moved"), "Spent unit has no highlights")
			click(_screen(board.grid.get_neighbors(destination)[0]), MOUSE_BUTTON_RIGHT)
			check(board.game_state.units[id].cell_id == destination, "Second move rejected")
		if player == 1:
			var enemy_start: int = board.game_state.units[3].cell_id
			click(_screen(enemy_start))
			check(board.selected_unit_id == -1 and not board.unit_views[3].visible, "Hidden enemy cannot be selected or rendered")
			click(_screen(board.grid.get_neighbors(enemy_start)[-1]), MOUSE_BUTTON_RIGHT)
			check(board.game_state.units[3].cell_id == enemy_start, "Cannot move enemy")
			keypress(KEY_ESCAPE)
			check(board.selected == board.NONE and board.selected_unit_id == -1, "Escape clears selection")
		click(board.end_turn_button.get_global_rect().get_center())
		check(board.selected == board.NONE and board.game_state.active_player == 3 - player and board.privacy_overlay.visible, "End turn passes control behind a privacy handoff")
	if board.privacy_overlay.visible: click(board.privacy_overlay.get_node("PrivacyCenter/PrivacyColumn/ReadyButton").get_global_rect().get_center())
	check(board.game_state.round_number == 2 and not board.game_state.units[1].moved and not board.game_state.units[2].moved, "Full round restores actions")
	click(_screen(board.game_state.units[1].cell_id))
	var selected: int = board.selected
	click(board.hud_panel.get_global_rect().position + Vector2(10, 10))
	click(board.hud_panel.get_global_rect().position + Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	click(board.coordinate_label.get_global_rect().get_center())
	check(board.selected == selected and not board.game_state.units[1].moved, "HUD consumes clicks without actions")
	board.navigation.distance = board.navigation.max_distance()
	board._update_camera_transform(0)
	click(Vector2(850, 350))
	check(board.selected == board.NONE, "Background clears selection")
	await finish("Hotseat globe")

# Terrain picking fixtures deliberately position the Camera3D directly. These are
# independent of the production tactical rig and retain the old sphere matrix.
func _globe_pose(yaw: float, latitude: float, altitude: float) -> void:
	var a := deg_to_rad(yaw)
	var b := deg_to_rad(latitude)
	var radial := Vector3(cos(b) * sin(a), sin(b), -cos(b) * cos(a))
	board.camera.position = radial * (board.planet_radius + altitude)
	board.camera.fov = 75.0
	board.camera.look_at(Vector3.ZERO, Vector3.UP)

