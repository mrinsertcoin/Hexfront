extends SceneTree

const Game:=preload("res://scenes/game.tscn")
var failures:=0

func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)

func _initialize() -> void: call_deferred("_run")

func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/14a_"+name+".png")==OK,"Capture saved: "+name)

func _run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Run living_migration_graphical without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="red"; config.opponent_controller="Human"
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=Game.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await process_frame
	var spider: GameState.Unit=board.game_state.units[1]
	board.selected=spider.cell_id; board.selected_unit_id=spider.id; board._focus_selected(); board._refresh_display()
	await capture("spider_panel")
	check(board.unit_label.text.contains("Spider internals") and board.materials_label.text.contains("Synapse"),"Rendered HUD contains Spider and resource state")
	var destination: int=-1
	for cell_id: int in board.grid.get_neighbors(spider.cell_id):
		if not board.game_state.is_cell_blocked(cell_id): destination=cell_id; break
	check(board.rules.try_move(1,spider.id,destination).success,"Graphical Spider movement accepted")
	board.clear_selection(); board._refresh_display(); await capture("terrain_connection")
	check(board.tiles.has(destination) and board.tiles[destination].visible,"Terrain-consumption overlay rendered")
	board.queue_free(); await process_frame
	print("Living Migration graphical checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
