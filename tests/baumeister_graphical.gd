extends SceneTree

const Game:=preload("res://scenes/game.tscn")
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/14b_"+name+".png")==OK,"Capture saved: "+name)

func _run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Run baumeister_graphical without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="baumeister"; config.opponent_faction_id="living_migration"; config.opponent_controller="Human"
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=Game.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await process_frame
	var pillar: GameState.Structure
	for structure: GameState.Structure in board.game_state.structures.values():
		if structure.controller_id==1 and structure.pillar_state!=null: pillar=structure; break
	board.selected=pillar.cell_id; board.selected_structure_id=pillar.id; board._focus_selected(); board._refresh_display()
	await capture("pillar_panel")
	check(board.unit_label.text.contains("Integrity:") and board.materials_label.text.contains("Unity"),"Rendered HUD contains Pillar and resource state")
	var engineer: GameState.Unit=board.game_state.units[2]; board.game_state.players[1].resources.materials=100
	var candidates:=board.rules.baumeister_rules.candidate_pillar_cells(1,engineer.id,pillar.id)
	check(not candidates.is_empty() and board.rules.start_bridge_extension(1,engineer.id,pillar.id,candidates[0]).success,"Graphical bridge expansion accepted")
	board.clear_selection(); board._refresh_display(); await capture("bridge_network")
	var bridge: BridgeState=board.game_state.baumeister.bridges.values()[0]
	check(board.tiles.has(bridge.path[0]) and board.tiles[bridge.path[0]].visible,"Bridge network overlay rendered")
	board.queue_free(); await process_frame
	print("Baumeister graphical checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
