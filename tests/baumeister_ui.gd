extends "res://tests/hotseat.gd"

func _run() -> void:
	root.size=Vector2i(1152,648)
	board=Main.instantiate() as PlanetBoard
	board.animate_movement=false
	var config:=MatchConfig.new()
	config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.world_population_preset=WorldPopulationConfig.OFF
	config.player_faction_id="baumeister"
	config.opponent_faction_id="living_migration"
	config.opponent_controller="Human"
	board.configure_match(config,UserSettings.new())
	root.add_child(board); board.set_process(false)
	await process_frame; await process_frame
	check(board.game_state.players[1].faction_id=="baumeister","Board starts selected Baumeister faction")
	for label in ["Food","Materials","Energy","Unity","Expected production","maintenance"]:
		check(board.materials_label.text.contains(label),"Economy HUD exposes "+label)
	var pillar: GameState.Structure
	for structure: GameState.Structure in board.game_state.structures.values():
		if structure.controller_id==1 and structure.pillar_state!=null: pillar=structure; break
	board.select_at(_screen(pillar.cell_id))
	check(board.selected_structure_id==pillar.id,"Pillar selection opens city panel")
	check(board.unit_label.text.contains("Integrity:") and board.unit_label.text.contains("SUPPLIED"),"Pillar UI separates Integrity and supply from HP")
	check(board.unit_label.text.contains("District cells:") and board.unit_label.text.contains("Bridge connections:"),"Pillar UI exposes district ring and bridge network")
	var has_district:=false; var has_research:=false; var has_expansion:=false
	for child: Node in board.recruit_box.get_children():
		if child is Button:
			var label: String=(child as Button).text
			has_district=has_district or label.contains("Build Mine")
			has_research=has_research or label.contains("Research:")
			has_expansion=has_expansion or label.contains("Build pillar + bridge")
	check(has_district and has_research and has_expansion,"Pillar panel exposes construction, research and expansion intents")
	var engineer: GameState.Unit=board.game_state.units[2]
	board.select_at(_screen(engineer.cell_id))
	check(board.unit_label.text.contains("infrastructure build/repair"),"Bridgewright UI exposes engineering role")
	board.game_state.players[1].resources.materials=100; engineer.moved=false; engineer.attacked=false
	var candidates:=board.rules.baumeister_rules.candidate_pillar_cells(1,engineer.id,pillar.id)
	var result:=board.rules.start_bridge_extension(1,engineer.id,pillar.id,candidates[0])
	check(result.success,"Board command starts bridge expansion")
	board.clear_selection(); board._refresh_display()
	var bridge: BridgeState=board.game_state.baumeister.bridges.values()[0]
	check(board.tiles.has(bridge.path[0]) and board.tiles[bridge.path[0]].visible,"Bridge construction has a world overlay")
	board.restart_match()
	check(board.game_state.baumeister.bridges.is_empty() and board.game_state.baumeister.districts.is_empty(),"Restart clears Baumeister runtime infrastructure")
	board.queue_free(); await process_frame
	print("Baumeister UI checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
