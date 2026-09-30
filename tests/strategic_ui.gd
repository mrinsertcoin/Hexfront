extends "res://tests/hotseat.gd"
const Snapshot=preload("res://tests/test_state.gd")

func _run() -> void:
	root.size=Vector2i(1280,720)
	board=Main.instantiate() as PlanetBoard; board.animate_movement=false
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	board.configure_match(config,settings); root.add_child(board); board.set_process(false)
	await process_frame; await process_frame
	for viewport_size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=viewport_size; board._layout_hud()
		check(board.top_bar.get_global_rect().end.x<=viewport_size.x and board.hud_panel.get_global_rect().end.y<=viewport_size.y and not board.action_panel.get_global_rect().intersects(board.notification_feed.get_global_rect()),"HUD fits without action/feed overlap at %s" % viewport_size)
	root.size=Vector2i(1280,720); board._layout_hud()

	check(board.top_bar.name=="TopBar" and board.hud_panel.name=="SelectionPanel" and board.action_panel.name=="ActionBar" and board.strategic_panel.name=="StrategicPanel" and board.notification_feed.name=="Notifications","Coherent HUD regions are present")
	check(board.resource_bar.get_node_or_null("Resource_food")!=null and board.resource_bar.get_node_or_null("Resource_silk")!=null and board.resource_bar.get_node_or_null("Resource_synapse")!=null,"Resource bar is generated from the active faction")
	check(board.resource_bar.get_node("Resource_food").tooltip_text.contains("Income:") and board.resource_bar.get_node("Resource_food").tooltip_text.contains("Upkeep:"),"Resource tooltip explains income, upkeep, and net")
	check(board.turn_label.text.contains("Living Migration") and board.turn_label.text.contains("Round"),"Top bar identifies active faction and round")

	board.strategic_panel.visible=true; board.strategic_panel.configure(board.rules,1)
	var faction:=board.game_state.registry.faction("living_migration")
	var available_found:=false; var locked_found:=false
	for technology_id: String in faction.technology_ids:
		var state_name:=board.strategic_panel.technology_state(technology_id)
		available_found=available_found or state_name==StrategicResearchPanel.AVAILABLE
		if not board.game_state.registry.technology(technology_id).prerequisite_ids.is_empty():
			locked_found=locked_found or (state_name==StrategicResearchPanel.LOCKED and board.strategic_panel.locked_reason(technology_id).contains("Requires:"))
	check(available_found and locked_found,"Research tree derives available and prerequisite-locked states")
	var locked_unit_reason:=""
	for unit_id: String in faction.unit_roster_ids:
		locked_unit_reason=board._unit_lock_reason(1,unit_id)
		if not locked_unit_reason.is_empty(): break
	check(locked_unit_reason.contains("Requires research:"),"Locked production exposes an actionable reason")

	var spider: GameState.Unit=board.game_state.units[1]
	board.select_at(_screen(spider.cell_id))
	check(board.unit_label.text.contains("HP:") and board.unit_label.text.contains("Damage:") and board.unit_label.text.contains("Movement:"),"Selection panel resolves current unit statistics")
	check(board.unit_label.text.contains("Internal storage (9 slots)") and board.unit_label.text.contains("Nursery:"),"Spider management shows nine slots and branch state")
	var before:=Snapshot.snapshot(board.game_state)
	board._set_input_mode(StrategicInputMode.Kind.ROAD,spider.id)
	check(board.has_active_input_mode(),"Targeting mode becomes active")
	board.cancel_input_mode(false)
	check(not board.has_active_input_mode() and Snapshot.snapshot(board.game_state)==before,"Mode cancellation is ephemeral and changes no game state")

	check(board.rules.try_end_turn(1).success,"Switch to Baumeister succeeds")
	board.clear_selection(); board._refresh_display()
	check(board.resource_bar.get_node_or_null("Resource_materials")!=null and board.resource_bar.get_node_or_null("Resource_energy")!=null and board.resource_bar.get_node_or_null("Resource_unity")!=null,"Active-turn switch rebuilds faction resources")
	check(board.turn_label.text.contains("Baumeister") and not board.turn_label.text.contains("Living Migration"),"Active HUD switches faction identity")
	var pillar: GameState.Structure
	for structure: GameState.Structure in board.game_state.structures.values():
		if structure.controller_id==2 and structure.pillar_state!=null: pillar=structure; break
	board.select_at(_screen(pillar.cell_id))
	check(board.unit_label.text.contains("Integrity:") and board.unit_label.text.contains("District cells:") and board.unit_label.text.contains("Bridge connections:"),"Pillar overview separates Integrity, districts, and network state")

	var site_cell:=-1
	for cell_id: int in board.grid.get_neighbors(board.game_state.units[3].cell_id):
		if not board.game_state.is_cell_blocked(cell_id) and board.game_state.baumeister.district_at(cell_id)==null: site_cell=cell_id; break
	var site:=board.game_state.add_world_site("trade_post",site_cell)
	board.game_state.refresh_visibility(); board._refresh_display()
	board.select_at(_screen(site_cell))
	check(board.selected_site_id==site.id and board.unit_label.text.contains("Trade Post") and board.unit_label.text.contains("Relation: World"),"Generic site selection is safe and informative")

	board.notification_feed.clear_all(); board.notification_feed.post("Production complete",StrategicNotificationFeed.Severity.SUCCESS,site_cell)
	check(board.notification_feed.records.size()==1 and board.notification_feed.records[0].cell_id==site_cell,"Notification feed stores severity and logical focus target")
	await finish("Strategic UI")
