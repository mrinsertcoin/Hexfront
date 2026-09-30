extends SceneTree

const Game:=preload("res://scenes/game.tscn")
var failures:=0
func check(ok: bool,message: String)->void: if not ok: failures+=1; push_error(message)
func _initialize()->void: call_deferred("_run")
func capture(name: String)->void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/15_"+name+".png")==OK,"Capture saved: "+name)

func _run()->void:
	if DisplayServer.get_name()=="headless": push_error("Run strategic_ui_graphical without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=Game.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await process_frame
	var spider: GameState.Unit=board.game_state.units[1]
	board.selected=spider.cell_id; board.selected_unit_id=spider.id; board._focus_selected(); board._refresh_display()
	board.notification_feed.post("Brood ready for deployment",StrategicNotificationFeed.Severity.SUCCESS,spider.cell_id,spider.id)
	await capture("living_actions_notifications")
	board._toggle_research(); await capture("living_research")
	check(board.strategic_panel.visible and board.resource_bar.get_node_or_null("Resource_synapse")!=null,"Living strategic HUD rendered")
	board._close_strategic_panel(); board.rules.try_end_turn(1); board.clear_selection(); board._refresh_display()
	var pillar: GameState.Structure
	for structure: GameState.Structure in board.game_state.structures.values():
		if structure.controller_id==2 and structure.pillar_state!=null: pillar=structure; break
	board.selected=pillar.cell_id; board.selected_structure_id=pillar.id; board._focus_selected(); board._refresh_display()
	await capture("baumeister_pillar_actions")
	board._toggle_research(); await capture("baumeister_research")
	check(board.strategic_panel.visible and board.resource_bar.get_node_or_null("Resource_unity")!=null,"Baumeister strategic HUD rendered")
	board.queue_free(); await process_frame
	print("Strategic UI graphical checks complete; failures=",failures); quit(0 if failures==0 else 1)
