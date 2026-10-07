extends SceneTree

var failures:=0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _run() -> void:
	for level in [4,5]: profile_world(level)
	print("FFA performance checks complete; failures=",failures)
	quit(0 if failures==0 else 1)

func profile_world(level: int) -> void:
	var started:=Time.get_ticks_usec()
	var grid:=PlanetGrid.new(level,24.0 if level==4 else 48.0)
	var recipe:=PlanetGenerationConfig.new(); recipe.world_seed=190019+level
	var world:=GeneratedPlanet.generate(grid,recipe,false)
	var setup:={"player_ids":[1,2,3,4],"player_names":["P1","P2","P3","P4"],
		"player_colors":Array(PlayerIdentity.COLOR_HEX),"faction_ids":["living_migration","baumeister","living_migration","baumeister"],
		"team_ids":[1,2,3,4],"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN,ControllerState.HUMAN,ControllerState.HUMAN]}
	var suitability:={}
	for player_id in range(1,5):
		var row: Array[float]=[]
		for cell: PlanetWorldCellData in world.cell_world_data:
			row.append(clampf(0.55*cell.fertility+0.45*(1.0-cell.terrain_roughness),0.0,1.0))
		suitability[player_id]=row
	setup.start_suitability=suitability; setup.start_seed=recipe.world_seed
	var state:=GameState.new(grid,setup)
	var population_config:=WorldPopulationConfig.from_preset(WorldPopulationConfig.STANDARD)
	population_config.population_seed=99117; population_config.start_cells.assign(state.starting_cells.values())
	state.apply_population(WorldPopulationGenerator.generate(world,state.registry,population_config))
	var visibility_started:=Time.get_ticks_usec(); state.refresh_visibility()
	var visibility_ms:=(Time.get_ticks_usec()-visibility_started)/1000.0
	var maximum_payload:=0
	for player_id: int in state.players:
		maximum_payload=maxi(maximum_payload,JSON.stringify(ObservationCodec.encode(state,player_id,1)).to_utf8_buffer().size())
	var turn_started:=Time.get_ticks_usec()
	for _turn in range(4): state.advance_turn()
	var neutral_ai:=NeutralAI.new()
	if state.turn_state.neutral_phase:
		var neutral_ids: Array[int]=[]
		for controller_id: int in state.controllers:
			if state.controllers[controller_id].kind==ControllerState.NEUTRAL_AI: neutral_ids.append(controller_id)
		neutral_ids.sort()
		for controller_id: int in neutral_ids: neutral_ai.execute_actions(state,controller_id)
		GameRules.new(state).finish_neutral_phase()
	var turn_ms:=(Time.get_ticks_usec()-turn_started)/1000.0
	var total_ms:=(Time.get_ticks_usec()-started)/1000.0
	var memory_mb:=Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0
	print("FFA profile level=%d cells=%d total_ms=%.2f turn_ms=%.2f visibility_ms=%.2f max_payload_bytes=%d memory_mb=%.1f" % [
		level,grid.get_cell_count(),total_ms,turn_ms,visibility_ms,maximum_payload,memory_mb])
	check(world!=null and state.players.size()==4,"Four-player world initializes at level %d" % level)
	check(visibility_ms<3000.0,"Visibility refresh remains bounded at level %d" % level)
	check(maximum_payload<4*1024*1024,"Recipient snapshot remains bounded at level %d" % level)
	check(total_ms<60000.0,"Representative four-player setup remains bounded at level %d" % level)
