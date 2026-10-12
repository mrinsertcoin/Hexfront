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
	config.world_population_preset=WorldPopulationConfig.OFF
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=Game.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await process_frame
	var worker: GameState.Unit=board.game_state.units[2]
	board.selected=worker.cell_id; board.selected_unit_id=worker.id; board._focus_selected(); board._refresh_display(); await process_frame
	var rotation_before:=board.model_preview.model_root.rotation.y; await process_frame; await process_frame
	check(board.model_preview.model_root.rotation.y!=rotation_before and board.model_preview.camera.position.is_finite(),"Worker preview rotates and auto-frames")
	await capture("unit_overlay_worker_1280")
	var additions: Array[GameState.Unit]=[]
	for definition_id: String in ["fighter_ant","dragonfly"]:
		var cell_id:=-1
		for candidate: int in board.grid.breadth_first(worker.cell_id).order:
			if not board.game_state.is_cell_blocked(candidate): cell_id=candidate; break
		var added:=GameState.Unit.new(board.game_state.allocate_id(),1,definition_id,cell_id,-1,board.game_state.registry); board.game_state.units[added.id]=added; additions.append(added)
	board.game_state.refresh_visibility(); board._refresh_display()
	for added: GameState.Unit in additions:
		board.selected=added.cell_id; board.selected_unit_id=added.id; board._refresh_display(); await process_frame
		check(board.model_preview.model_root.get_child_count()==1 and board.model_preview.camera.position.z>0.0,"%s preview is instantiated and framed" % added.definition_id)
		await capture("unit_overlay_"+added.definition_id)
	for added: GameState.Unit in additions:
		board.game_state.units.erase(added.id)
	var enemy: GameState.Unit
	for candidate: GameState.Unit in board.game_state.units.values():
		if candidate.controller_id==2: enemy=candidate; break
	var enemy_cell:=-1
	for candidate: int in board.grid.get_neighbors(worker.cell_id):
		if not board.game_state.is_cell_blocked(candidate,enemy.id): enemy_cell=candidate; break
	check(enemy_cell>=0,"Found a free visible cell for the enemy overlay case")
	if enemy_cell>=0: enemy.cell_id=enemy_cell
	board.game_state.refresh_visibility(); board._refresh_display()
	board.selected=enemy.cell_id; board.selected_unit_id=enemy.id; board._refresh_display(); await process_frame
	check(board.unit_info_panel.visible and not board.unit_info_panel.queued_panel.visible,"Visible Baumeister enemy uses the fog-safe unit overlay")
	await capture("unit_overlay_baumeister_enemy")
	for viewport_size: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=viewport_size; await process_frame; board._layout_hud(); await process_frame
		check(board.hud_panel.get_global_rect().end.x<=viewport_size.x and board.hud_panel.get_global_rect().end.y<=viewport_size.y,"Unit overlay fits at %s" % viewport_size)
		await capture("unit_overlay_%dx%d" % [viewport_size.x,viewport_size.y])
	root.size=Vector2i(1280,720); board._layout_hud()
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
