extends SceneTree

const Game := preload("res://scenes/game.tscn")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run swarm_models_graphical without --headless")
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	var config := MatchConfig.new()
	config.planet_size = MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id = "living_migration"
	config.opponent_faction_id = "baumeister"
	config.opponent_controller = "Human"
	var settings := UserSettings.new()
	settings.terrain_quality = "Medium"
	var board := Game.instantiate() as PlanetBoard
	board.configure_match(config, settings)
	root.add_child(board)
	await process_frame
	await process_frame
	board.visibility_omniscient = true
	board.game_state.units.clear()
	board.game_state.structures.clear()
	var roster: PackedStringArray = board.game_state.registry.faction("living_migration").unit_roster_ids
	var cells: Array[int] = board.grid.breadth_first(0, 3).order
	for index in range(roster.size()):
		var unit_id := 2100 + index
		board.game_state.units[unit_id] = GameState.Unit.new(unit_id, 1, roster[index], cells[index], -1, board.game_state.registry)
	board._refresh_display()
	await process_frame
	check(board.unit_views.size() == roster.size(), "Every Swarm roster unit receives a board view")
	var mapped := 0
	var placeholders := 0
	for index in range(roster.size()):
		var unit_id := 2100 + index
		var definition := board.game_state.registry.unit(roster[index])
		var view: EntityView = board.unit_views[unit_id]
		var wrapper := view.get_node("visual_root") as Node3D
		var model_root := wrapper.get_node("ModelRoot") as Node3D
		check(model_root.get_child_count() == 1, "Exactly one model or placeholder is instantiated for " + roster[index])
		if board.visual_map.has_real_model(definition.visual_id):
			mapped += 1
			var profile := board.visual_map.model_definition(definition.visual_id)
			check(model_root.scale.is_equal_approx(profile.model_scale), "Profile scale is applied to " + roster[index])
			check(is_equal_approx(model_root.position.y, profile.height_offset), "Profile height is applied to " + roster[index])
		else:
			placeholders += 1
		check(wrapper.get_child_count() >= 2, "Ownership ring remains outside the authored model for " + roster[index])
		check(view.position.normalized().is_equal_approx(board.grid.get_cell(cells[index]).up), "Unit remains radial on the spherical board: " + roster[index])
	check(mapped == 11 and placeholders == 4, "Gallery contains 11 mapped models and 4 honest placeholders")
	var worker_id := 2100 + roster.find("worker_ant")
	var worker: EntityView = board.unit_views[worker_id]
	var worker_cell: int = board.game_state.units[worker_id].cell_id
	var route: Array[int] = [worker_cell, board.grid.get_neighbors(worker_cell)[0]]
	worker.play_path(route, board.grid, board.SURFACE_OFFSET)
	worker.advance_movement(0.05)
	check(worker.moving, "Static Swarm models remain compatible with accepted movement paths")
	worker.cancel_movement()
	var admiral_id := 2100 + roster.find("admiral")
	board.game_state.units.erase(admiral_id)
	board._sync_units()
	await process_frame
	check(not board.unit_views.has(admiral_id), "Death/removal frees the mapped model view")
	board.game_state.units[admiral_id] = GameState.Unit.new(admiral_id, 1, "admiral", cells[roster.find("admiral")], -1, board.game_state.registry)
	board._sync_units()
	check(board.unit_views.has(admiral_id) and board.visual_map.has_real_model("admiral"), "Spawn/recruit refresh restores a mapped model view")
	board.clear_selection()
	board.focus_cell(0, true)
	board.navigation.target_distance = minf(board.navigation.max_distance(), board.planet_radius * 1.35)
	board.navigation.distance = board.navigation.target_distance
	board.navigation.apply_transform()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/21a_swarm_roster.png") == OK, "Swarm roster capture saved")
	board.queue_free()
	await process_frame
	print("Swarm model graphical checks complete: mapped=", mapped, " placeholders=", placeholders, "; failures=", failures)
	quit(0 if failures == 0 else 1)
