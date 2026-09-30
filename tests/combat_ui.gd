extends "res://tests/hotseat.gd"

var route: Array[int] = []

func _next_round() -> void:
	click(board.end_turn_button.get_global_rect().get_center())
	if board.privacy_overlay.visible: board._dismiss_privacy()
	click(board.end_turn_button.get_global_rect().get_center())
	if board.privacy_overlay.visible: board._dismiss_privacy()

func _hover(hex: int) -> void:
	# Exercise the same hover projection/query as the per-frame mouse handler.
	board.update_hover_at(_screen(hex))

func _fixture() -> void:
	route = board.grid.find_path(100, board.grid.breadth_first(100).order[-1])
	board.game_state.units.clear()
	board.game_state.units[1] = GameState.Unit.new(1, 1, "Gunner", route[0])
	board.game_state.units[2] = GameState.Unit.new(2, 1, "Scout", board.grid.get_neighbors(route[0])[1])
	board.game_state.units[3] = GameState.Unit.new(3, 2, "Scout", route[2])
	board.game_state.units[4] = GameState.Unit.new(4, 2, "Infantry", board.grid.get_neighbors(route[0])[2])
	board.game_state.units[4].hp = 1
	# This fixture replaces unit types as well as positions; recreate its
	# visual fixtures instead of reusing meshes for IDs from the live setup.
	for view: MeshInstance3D in board.unit_views.values():
		board.remove_child(view)
		view.queue_free()
	board.unit_views.clear()
	board.health_fills.clear()
	board.game_state.visibility_system.reset(); board.game_state.refresh_visibility()
	board.clear_selection()

func _check_fresh() -> void:
	# Fresh positions depend on the configured topology (Milestone 10 sizes).
	var initial := GameState.new(board.grid)
	check(board.game_state.units.size() == 6 and board.game_state.structures.size() == 2 and board.unit_views.size() == 8 and board.health_fills.size() == 8, "Restart restores six military units, two headquarters, and eight views/bars")
	for id: int in initial.units:
		var unit: GameState.Unit = board.game_state.units[id]
		var expected: GameState.Unit = initial.units[id]
		check(unit.cell_id == expected.cell_id and unit.hp == expected.max_hp and not unit.moved and not unit.attacked, "Restart restores position, HP, and actions")
		check(is_equal_approx(board.health_fills[id].scale.x, 1.0), "Restart fills health bars")
	check(board.game_state.winner_id == 0 and board.game_state.active_player == 1 and board.game_state.round_number == 1, "Restart restores active match")
	check(board.selected_unit_id == -1 and board.selected == board.NONE and board.preview_path.is_empty() and board.reachable_tiles.is_empty() and board.attack_tiles.is_empty(), "Restart clears all selection and highlights")
	check(board.hover_cell == board.NONE and board.attack_preview_label.text.is_empty() and board.feedback_label.text.is_empty(), "Restart clears hover and combat feedback")
	check(not board.end_turn_button.disabled and not board.restart_button.visible, "Restart restores UI controls")
	check(is_equal_approx(board.navigation.distance, board.camera_config.default_distance), "Restart resets tactical distance" )
	check(board.end_turn_button.pressed.get_connections().size() == 1 and board.restart_button.pressed.get_connections().size() == 1, "No duplicate button signal connections")

func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://.godot/" + name + ".png")
	check(error == OK, "Save graphical capture")

func _shoot_standard_target(target_id: int) -> void:
	var target: RefCounted = board.game_state.units.get(target_id) if board.game_state.units.has(target_id) else board.game_state.structures.get(target_id)
	var shots: int = ceili(float(target.hp) / board.game_state.units[5].attack_damage)
	for shot in range(shots):
		click(_screen(board.game_state.units[5].cell_id))
		var target_hex: int = target.cell_id
		click(_screen(target_hex), MOUSE_BUTTON_RIGHT)
		check(board.game_state.units[5].attacked, "Standard battle attack routed through input")
		if board.game_state.winner_id == 0:
			_next_round()
	check(not board.game_state.units.has(target_id) and not board.game_state.structures.has(target_id), "Standard battle target eliminated")

func _run() -> void:
	root.size = Vector2i(1152, 648)
	board = Main.instantiate() as PlanetBoard
	# Instant presentation keeps this rules/input regression suite synchronous.
	board.animate_movement = false
	root.add_child(board)
	board._new_match("Hotseat")
	# Isolate scripted checks from physical keyboard pan during graphical runs.
	# Hover is exercised explicitly; desktop camera input remains a manual check.
	board.set_process(false)
	await process_frame
	await process_frame
	_check_fresh()
	var baseline_children: int = board.get_child_count() - board.tiles.size()
	check(board.unit_views[5].get_node("visual_root/ModelRoot").get_child_count() == 1, "Gunner has exactly one model")
	await _capture("milestone3_initial")
	click(_screen(board.game_state.units[1].cell_id))
	_hover(board.game_state.units[3].cell_id)
	check(board.attack_preview_label.text.is_empty(), "No actionable preview outside range")
	click(_screen(board.game_state.units[3].cell_id), MOUSE_BUTTON_RIGHT)
	check(board.selected_unit_id == 1 and not board.game_state.units[1].attacked and not board.game_state.visibility_system.observation_for_controller(1).visible_entities.has(3), "Hidden enemy input preserves selection and actions without exposing a target")

	_fixture()
	await process_frame
	board.focus_cell(route[0], true)
	var bar_position: Vector3 = board.health_fills[1].global_position
	var bar_screen:=board.camera.unproject_position(bar_position)
	check(board.pick_selectable_cell(bar_screen)==route[0],"Health bar does not obstruct tile picking")
	board.select_at(bar_screen)
	check(board.selected_unit_id == 1,"Health-bar ray selects its observed unit")
	_hover(route[2])
	check(board.attack_tiles.has(route[2]) and board.tiles[route[2]].material_override == board.attack_material, "Enemy gets distinct attack highlight")
	check(board.attack_preview_label.text.contains("HP 6 -> 3") and board.attack_preview_label.text.contains("survives"), "Enemy hover shows damage and remaining HP")
	check(board.unit_label.text.contains("HP:") and board.unit_label.text.contains("Attack: Ready"), "Selected combat stats and actions")
	click(_screen(route[2]))
	_hover(route[0])
	check(board.attack_tiles.is_empty() and board.attack_preview_label.text.is_empty(), "Enemy inspection grants no actionable previews")
	click(_screen(route[0]))
	click(_screen(route[2]), MOUSE_BUTTON_RIGHT)
	check(board.game_state.units[3].hp == 3 and is_equal_approx(board.health_fills[3].scale.x, 0.5), "Damage updates logical HP and health bar")
	check(board.game_state.units[1].attacked and board.reachable_tiles.is_empty() and board.attack_tiles.is_empty(), "Attack removes movement and attack highlights")
	check(board.feedback_label.text.contains("dealt 3 damage"), "Damage feedback")
	click(_screen(route[2]), MOUSE_BUTTON_RIGHT)
	check(board.game_state.units[3].hp == 3 and board.selected_unit_id == 1 and board.feedback_label.text.contains("already attacked"), "Second attack rejected without losing selection")
	_next_round()
	click(_screen(route[0]))
	_hover(route[2])
	check(board.attack_preview_label.text.contains("LETHAL"), "Lethal hover preview")
	await _capture("milestone3_combat")
	click(_screen(route[2]), MOUSE_BUTTON_RIGHT)
	check(not board.game_state.units.has(3) and not board.unit_views.has(3) and not board.health_fills.has(3), "Death removes logical unit, mesh and health bar")
	check(board.game_state.winner_id == 0, "Remaining enemy keeps match active")
	check(board.hover_cell == board.NONE and board.attack_preview_label.text.is_empty() and board.preview_path.is_empty(), "Death clears stale hover/path/preview")
	click(_screen(board.grid.get_neighbors(route[0])[1]))
	click(_screen(route[2]), MOUSE_BUTTON_RIGHT)
	check(board.game_state.units[2].cell_id == route[2], "Freed tile accepts a subsequent movement command")
	_next_round()
	click(_screen(route[0]))
	click(_screen(board.grid.get_neighbors(route[0])[2]), MOUSE_BUTTON_RIGHT)
	# Under milestone 4, eliminating all military units does not end the match while an HQ remains
	check(board.game_state.winner_id == 0 and not board.end_turn_button.disabled and not board.restart_button.visible, "Final death does not declare winner while HQ remains")
	_next_round()
	board.game_state.structures[101].cell_id = route[1]
	board.game_state.structures[101].hp = 1
	board.game_state.refresh_visibility()
	board._refresh_display()
	click(_screen(route[0]))
	_hover(route[1])
	check(board.attack_preview_label.text.contains("LETHAL"), "HQ lethal preview")
	click(_screen(route[1]), MOUSE_BUTTON_RIGHT)
	check(board.game_state.winner_id == 1 and board.end_turn_button.disabled and board.restart_button.visible, "Headquarters destruction wins through mouse routing")
	var round_before: int = board.game_state.round_number
	click(board.end_turn_button.get_global_rect().get_center())
	check(board.game_state.round_number == round_before, "Disabled turn button cannot advance")
	click(_screen(route[2]))
	check(board.selected_unit_id == 2 and board.unit_label.text.contains("Disabled"), "Inspection remains available after victory")
	click(_screen(route[3]), MOUSE_BUTTON_RIGHT)
	check(board.game_state.units[2].cell_id == route[2], "Right-click actions disabled after victory")
	await _capture("milestone3_victory")
	# Dynamic strategic containers settle their minimum sizes on the next frame.
	await process_frame
	board.camera.position += Vector3(2, 0, 1)
	board.camera.size = 12.0
	click(board.restart_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	_check_fresh()
	check(board.get_child_count() - board.tiles.size() == baseline_children, "No duplicated scene nodes after restart")

	# Complete a standard starting match using only viewport commands. P2 passes.
	# Follow the globe graph toward each defender, then shoot at normal damage.
	for target_id in [4, 6, 3, 101]:
		var target: RefCounted = board.game_state.units.get(target_id) if target_id != 101 else board.game_state.structures[101]
		for step in range(board.grid.get_cell_count()):
			var unit: GameState.Unit = board.game_state.units[5]
			if board.grid.distance(unit.cell_id, target.cell_id) <= unit.attack_range:
				break
			var blocked: Dictionary = {}
			for other: GameState.Unit in board.game_state.units.values():
				if other.id != 5 and other.id != target_id:
					blocked[other.cell_id] = true
			for structure: GameState.Structure in board.game_state.structures.values():
				if structure.id != target_id:
					blocked[structure.cell_id] = true
			var path: Array[int] = board.grid.find_path(unit.cell_id, target.cell_id, -1, blocked)
			check(path.size() > 1, "Standard battle route exists")
			if path.size() < 2:
				break
			click(_screen(unit.cell_id))
			click(_screen(path[1]), MOUSE_BUTTON_RIGHT)
			check(unit.cell_id == path[1], "Standard battle advances through globe input")
			_next_round()
		_shoot_standard_target(target_id)
		if target_id == 3:
			check(board.game_state.winner_id == 0 and board.game_state.units.size() == 3, "Army elimination alone does not win")
	check(board.game_state.winner_id == 1, "Standard full globe battle wins by HQ destruction")
	await process_frame
	click(board.restart_button.get_global_rect().get_center())
	await process_frame
	_check_fresh()
	check(board.get_child_count() - board.tiles.size() == baseline_children, "Repeated restart has no duplicates")
	_fixture()
	board.game_state.units[3].hp = 1
	click(_screen(board.game_state.units[3].cell_id))
	check(board.selected_unit_id == 3, "Inspect target before external rules command")
	check(board.rules.try_attack(1, 1, 3).killed, "Independent rules command kills inspected target")
	board._refresh_display()
	check(board.selected_unit_id == -1 and board.selected == board.NONE and board.hover_cell == board.NONE and board.attack_tiles.is_empty(), "Refresh clears a dead selection and stale targeting references")
	board.restart_match()
	await process_frame
	_check_fresh()
	print("Combat UI checks complete: previews, damage, death, standard full battle, repeated restart; failures=", failures)
	quit(0 if failures == 0 else 1)
