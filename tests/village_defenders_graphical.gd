extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/village_"+name+".png")
func _run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Run without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	config.world_population_preset=WorldPopulationConfig.OFF; config.villages_per_player=2
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=load("res://scenes/game.tscn").instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board); board.set_process(false)
	board._ai_token+=1; board._ai_running=false
	await process_frame; await process_frame
	board.visibility_omniscient=true; board._refresh_display()
	var village: WorldSiteState
	for site: WorldSiteState in board.game_state.world_sites.values():
		if site.definition_id=="village": village=site; break
	check(village!=null and not board.generated_planet.terraces.is_ramp(village.cell_id),"Rendered village is on flat terrain")
	var villager: GameState.Unit; var knight: GameState.Unit
	for unit: GameState.Unit in board.game_state.units.values():
		if unit.home_site_id!=village.id: continue
		if unit.definition_id=="villager": villager=unit
		if unit.definition_id=="knight_of_the_land": knight=unit
	check(villager!=null and knight!=null,"Village retains both defender types")
	check(board.unit_views[villager.id].squad_members.size()==7,"Seven supplied Villager models are rendered")
	var positions:={}
	for member: Node3D in board.unit_views[villager.id].squad_members: positions[Vector2(member.position.x,member.position.z)]=true
	check(positions.size()==7,"Squad members do not overlap")
	for unit: GameState.Unit in [villager,knight]:
		board.selected=unit.cell_id; board.selected_unit_id=unit.id; board._refresh_display(); board.focus_cell(unit.cell_id,true)
		check(board.model_preview.current_visual_id==unit.definition_id,"Real defender preview is selected")
		for _frame in range(4): await process_frame
		await capture(unit.definition_id)
	board.clear_selection(); board.focus_cell(village.cell_id,true)
	board.navigation.distance=12; board.navigation.target_distance=12; board.navigation.apply_transform()
	await capture("defenders_overview")
	board.free(); print("Village defenders graphical checks complete; failures=",failures); quit(0 if failures==0 else 1)
