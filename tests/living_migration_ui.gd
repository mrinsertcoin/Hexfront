extends "res://tests/hotseat.gd"

func _run() -> void:
	root.size=Vector2i(1152,648)
	board=Main.instantiate() as PlanetBoard
	board.animate_movement=false
	var config:=MatchConfig.new()
	config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"
	config.opponent_faction_id="red"
	config.opponent_controller="Human"
	board.configure_match(config,UserSettings.new())
	root.add_child(board)
	board.set_process(false)
	await process_frame
	await process_frame
	check(board.game_state.players[1].faction_id=="living_migration","Board starts selected Living Migration faction")
	check(board.materials_label.text.contains("Food") and board.materials_label.text.contains("Silk") and board.materials_label.text.contains("Synapse"),"HUD exposes faction resources")
	check(board.materials_label.text.contains("Expected production") and board.materials_label.text.contains("Current upkeep"),"HUD exposes production and upkeep")
	var spider: GameState.Unit=board.game_state.units[1]
	board.select_at(_screen(spider.cell_id))
	check(board.selected_unit_id==spider.id and board.unit_label.text.contains("Spider internals: 1/9"),"Spider selection opens internal-slot panel")
	check(board.unit_label.text.contains("Ant Hill") and board.unit_label.text.contains("Mites:"),"Spider panel shows nursery and mite progress")
	var has_production:=false; var has_research:=false; var has_construction:=false
	for child: Node in board.recruit_box.get_children():
		if child is Button:
			var label: String=(child as Button).text
			has_production=has_production or label.contains("Worker Ant Brood")
			has_research=has_research or label.contains("Research:")
			has_construction=has_construction or label.contains("Grow Spider")
	check(has_production and has_research and has_construction,"Spider panel sends production, research and construction intents")
	var destination:=board.game_state.grid.get_neighbors(spider.cell_id)[0]
	var result:=board.rules.try_move(1,spider.id,destination)
	check(result.success,"Spider movement succeeds in board session")
	board.clear_selection(); board._refresh_display()
	check(board.tiles.has(destination) and board.tiles[destination].visible and board.tiles[destination].material_override==board.depleted_material,"Depleted terrain has gameplay overlay")
	var worker: GameState.Unit=board.game_state.units[2]
	board.select_at(_screen(worker.cell_id))
	check(board.unit_label.text.contains("Connection: connected") and not board.road_highlights.is_empty(),"Worker UI shows Connection and road previews")
	var initial:=TestState.snapshot(board.game_state)
	board.restart_match()
	check(board.game_state.units[1].spider_state!=null and board.game_state.living_migration.terrain.is_empty(),"Restart rebuilds Living Migration runtime state")
	check(TestState.snapshot(board.game_state)!=initial,"Restart removes mutated terrain and movement state")
	board.queue_free(); await process_frame
	print("Living Migration UI checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
