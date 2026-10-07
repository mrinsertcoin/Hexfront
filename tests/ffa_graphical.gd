extends SceneTree

const GameScene:=preload("res://scenes/game.tscn")
var failures:=0

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Run ffa_graphical without --headless"); quit(1); return
	root.size=Vector2i(1152,648)
	var config:=MatchConfig.new(); config.network_match=true; config.planet_size=MatchConfig.PlanetSize.SMALL
	config.world_seed=191919; config.private_population_seed=292929; config.world_population_preset=WorldPopulationConfig.STANDARD
	var factions: Array[String]=["living_migration","baumeister","living_migration","baumeister"]
	for index in range(4):
		config.player_assignments.append({"player_id":index+1,"player_name":"Graphical P%d" % (index+1),
			"faction_id":factions[index],"team_id":index+1,"controller_kind":ControllerState.HUMAN,
			"player_color":PlayerIdentity.color_hex_for_slot(index)})
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=GameScene.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await RenderingServer.frame_post_draw
	check(board.game_state.players.size()==4 and board.game_state.starting_cells.size()==4,"Graphical Small match renders four FFA participants")
	var colors:={}
	for player_id: int in board.game_state.players: colors[board._owner_color(player_id).to_html()]=true
	check(colors.size()==4,"Graphical ownership rings use four distinct colors")
	var sample_frames:=180; var started:=Time.get_ticks_usec()
	for _frame in range(sample_frames): await process_frame
	var elapsed_seconds:=float(Time.get_ticks_usec()-started)/1000000.0
	var measured_fps:=float(sample_frames)/maxf(0.001,elapsed_seconds)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/m19_ffa_small.png")==OK,"FFA graphical capture saved")
	print("FFA graphical profile cells=%d fps=%.1f entities=%d sites=%d visibility_ms=%.2f" % [board.grid.get_cell_count(),
		measured_fps,board.game_state.units.size()+board.game_state.structures.size(),board.game_state.world_sites.size(),
		board.game_state.visibility_system.last_recalculation_ms])
	check(measured_fps>=10.0,"Small four-player client presentation remains interactive")
	board.queue_free(); await process_frame
	print("FFA graphical checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
