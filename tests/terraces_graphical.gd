extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/terraces_"+name+".png")==OK,"Capture "+name)
func _run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Run terraces_graphical without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	config.world_population_preset=WorldPopulationConfig.OFF; config.villages_per_player=0; config.cliff_generation="High"
	var board:=load("res://scenes/game.tscn").instantiate() as PlanetBoard
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"; board.configure_match(config,settings); root.add_child(board)
	board._ai_token+=1; board._ai_running=false; board.set_process(false)
	await process_frame; await process_frame
	board.visibility_omniscient=true; board._refresh_display()
	check(board.terrain_renderer.cliff_overlay.mesh!=null,"Explored cliffs have a red rim mesh")
	var terrain:=board.generated_planet.terraces
	var cliff: Dictionary={}; var ramp: Dictionary={}
	for record: Dictionary in terrain.boundaries:
		if board.game_state.is_water_cell(record.high) or board.game_state.is_water_cell(record.low): continue
		if record.cliff and cliff.is_empty(): cliff=record
		if not record.cliff and ramp.is_empty(): ramp=record
	check(not cliff.is_empty() and not ramp.is_empty(),"Dry cliff and ramp fixtures exist")
	board.hud_panel.visible=false; board.coordinate_label.visible=false; board.notification_feed.visible=false; board.action_panel.visible=false
	board.navigation.pitch=55.0; board.navigation.target_pitch=55.0; board.navigation.distance=6.0; board.navigation.target_distance=6.0
	board.focus_cell(cliff.high,true); await capture("cliff")
	var walker: GameState.Unit=board.game_state.units[2]; walker.cell_id=ramp.low; board._refresh_display(); board.focus_cell(ramp.low,true)
	board.hud_panel.visible=false; board.coordinate_label.visible=false; board.notification_feed.visible=false; board.action_panel.visible=false
	var view: EntityView=board.unit_views[walker.id]
	view.play_path([int(ramp.low),int(ramp.high)],board.grid,board.SURFACE_OFFSET)
	view.advance_movement(0.12)
	check(view.grounded,"Worker remains a ground-contact model")
	check(view.basis.y.dot(board.terrain_surface.ground_normal(view.position.normalized()))>0.999,"Walking unit aligns with the rendered ramp normal")
	await capture("walking_ramp")
	view.cancel_movement(); board.navigation.distance=board.navigation.max_distance()*0.90; board.navigation.target_distance=board.navigation.distance
	board.navigation.pitch=80.0; board.navigation.target_pitch=80.0; board.navigation.apply_transform()
	await capture("ranges")
	board.free(); print("Terraces graphical checks complete; failures=",failures); quit(0 if failures==0 else 1)
