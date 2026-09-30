extends SceneTree

const Game:=preload("res://scenes/game.tscn")
var failures:=0
func check(ok: bool,message: String)->void: if not ok: failures+=1; push_error(message)
func _initialize()->void: call_deferred("_run")

func capture(name: String)->void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/16_"+name+".png")==OK,"Capture saved: "+name)

func _run()->void:
	if DisplayServer.get_name()=="headless": push_error("Run world_population_graphical without --headless"); quit(1); return
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	config.world_population_preset=WorldPopulationConfig.STANDARD
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	var board:=Game.instantiate() as PlanetBoard; board.configure_match(config,settings); root.add_child(board)
	await process_frame; await process_frame
	check(board.population_result.site_records.size()>0 and board.population_result.neutral_group_records.size()>0,"Standard match renders generated population")
	check(board.site_views.size()==board.game_state.world_sites.size(),"Every logical site has one surface marker")
	var site: WorldSiteState
	for candidate: WorldSiteState in board.game_state.world_sites.values():
		if not board.site_views[candidate.id].visible: site=candidate; break
	if site==null: site=board.game_state.world_sites.values()[0]
	check(not board.site_views[site.id].visible,"Undiscovered generated site starts suppressed")
	var observer: GameState.Unit=board.game_state.units[2]
	observer.cell_id=board.grid.get_neighbors(site.cell_id)[0]; board.game_state.refresh_visibility(); board._refresh_display()
	board.selected=site.cell_id; board.selected_site_id=site.id; board.focus_cell(site.cell_id,true); board._refresh_display()
	await capture("site_selection")
	check(board.site_views[site.id].visible and not board.site_highlights.is_empty() and board.unit_label.text.contains("Interaction"),"Observed site selection has distinct overlay and strategic details")
	var neutral: GameState.Unit
	for unit: GameState.Unit in board.game_state.units.values():
		if not unit.neutral_group_id.is_empty(): neutral=unit; break
	check(neutral!=null and board.unit_views.has(neutral.id),"Neutral unit uses normal entity presentation")
	if neutral!=null:
		observer.cell_id=board.grid.get_neighbors(neutral.cell_id)[0]; board.game_state.refresh_visibility(); board._refresh_display()
		check(board.unit_views[neutral.id].visible,"Neutral population becomes visible through observation")
		board.clear_selection(); board.selected=neutral.cell_id; board.selected_unit_id=neutral.id; board.focus_cell(neutral.cell_id,true); board._refresh_display()
	await capture("neutral_population")
	var fingerprint:=board.population_result.fingerprint
	var runtime_sites:=board.game_state.world_sites.size(); var runtime_neutrals:=0
	for unit: GameState.Unit in board.game_state.units.values(): runtime_neutrals+=int(not unit.neutral_group_id.is_empty())
	board.restart_match(); await process_frame
	var restarted_neutrals:=0
	for unit: GameState.Unit in board.game_state.units.values(): restarted_neutrals+=int(not unit.neutral_group_id.is_empty())
	check(board.population_result.fingerprint==fingerprint and board.game_state.world_sites.size()==runtime_sites and restarted_neutrals==runtime_neutrals,"Restart reapplies identical population and resets runtime state")
	board.world_debug_panel.visible=true
	await capture("population_diagnostics")
	check(board.world_debug_panel.summary_label.text.contains("Population Standard"),"F6 diagnostics includes population version/count/fingerprint data")
	board.queue_free(); await process_frame
	print("World population graphical checks complete; failures=",failures); quit(0 if failures==0 else 1)
