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
	var enemy_wait:=0
	while board.game_state.turn_state.neutral_phase and enemy_wait<40:
		await process_frame; enemy_wait+=1
	check(not board.game_state.turn_state.neutral_phase and board.game_state.turn_state.simultaneous_stage_started,"Opening enemy activity completes before simultaneous player testing")
	for viewport_size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=viewport_size; await process_frame; board._layout_hud()
		check(board.top_bar.get_global_rect().end.x<=viewport_size.x and board.hud_panel.get_global_rect().end.y<=viewport_size.y and not board.action_panel.get_global_rect().intersects(board.notification_feed.get_global_rect()),"HUD fits without action/feed overlap at %s" % viewport_size)
		board._toggle_research()
		await process_frame
		check(board.research_backdrop.visible and board.research_backdrop.size==Vector2(viewport_size) and board.strategic_panel.get_global_rect().end.x<=viewport_size.x and board.strategic_panel.get_global_rect().end.y<=viewport_size.y,"Opaque modal research overlay fits at %s (backdrop=%s panel=%s)" % [viewport_size,board.research_backdrop.size,board.strategic_panel.get_global_rect()])
		board._close_strategic_panel()
	root.size=Vector2i(1280,720); board._layout_hud()

	check(board.top_bar.name=="TopBar" and board.hud_panel.name=="SelectionPanel" and board.action_panel.name=="ActionBar" and board.strategic_panel.name=="StrategicPanel" and board.notification_feed.name=="Notifications","Coherent HUD regions are present")
	check(board.resource_bar.get_node_or_null("Resource_food")!=null and board.resource_bar.get_node_or_null("Resource_silk")!=null and board.resource_bar.get_node_or_null("Resource_synapse")!=null,"Resource bar is generated from the active faction")
	check(board.resource_bar.get_node("Resource_food").tooltip_text.contains("Income:") and board.resource_bar.get_node("Resource_food").tooltip_text.contains("Upkeep:"),"Resource tooltip explains income, upkeep, and net")
	check(board.turn_label.text.contains("Simultaneous player turns") and board.turn_label.text.contains("Round"),"Top bar identifies the shared player stage and round")
	check(board.end_turn_button.text=="End Movement Phase","Management action uses phase-accurate label")

	board._toggle_research()
	check(board.research_backdrop.mouse_filter==Control.MOUSE_FILTER_STOP,"Research backdrop blocks world pointer input")
	var backdrop_style:=board.research_backdrop.get_theme_stylebox("panel") as StyleBoxFlat
	check(backdrop_style!=null and backdrop_style.bg_color.a>=0.9,"Research backdrop is visually opaque")
	var camera_distance:=board.navigation.target_distance
	var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true
	board._unhandled_input(wheel)
	check(is_equal_approx(board.navigation.target_distance,camera_distance),"Research modal blocks world camera input")
	board.strategic_panel.configure(board.rules,1)
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
	board._close_strategic_panel()

	var spider: GameState.Unit=board.game_state.units[1]
	board.select_at(_screen(spider.cell_id))
	check(board.unit_info_panel.visible and board.unit_info_panel.title_label.text=="LIVING SPIDER" and board.unit_info_panel.health_label.text.contains("%d / %d" % [spider.hp,spider.max_hp]),"Selecting a unit opens the tactical overlay with identity and health")
	check(board.unit_info_panel.stats_grid.get_child_count()>=8 and board.unit_info_panel.preview.current_visual_id=="living_spider","Overlay uses resolved tactical stats and the selected unit visual")
	check(board.unit_label.text.contains("HP:") and board.unit_label.text.contains("Damage:") and board.unit_label.text.contains("Movement:"),"Selection panel resolves current unit statistics")
	check(board.unit_label.text.contains("Internal storage (9 slots)") and board.unit_label.text.contains("Nursery:"),"Spider management shows nine slots and branch state")
	var before:=Snapshot.snapshot(board.game_state)
	board._set_input_mode(StrategicInputMode.Kind.ROAD,spider.id)
	check(board.has_active_input_mode(),"Targeting mode becomes active")
	board.cancel_input_mode(false)
	check(not board.has_active_input_mode() and Snapshot.snapshot(board.game_state)==before,"Mode cancellation is ephemeral and changes no game state")
	var spider_destination:=board.rules.reachable(1,spider.id)[0]
	check(board.rules.try_move(1,spider.id,spider_destination).success,"Spider moves in UI fixture")
	board._refresh_display()
	var moved_spider_management:=false
	for child: Node in board.unit_info_panel.action_flows[UnitInfoPanel.GROUP_CITY].get_children():
		if child is Button and not child.disabled and (child.text.begins_with("Produce ") or child.text.begins_with("Build ")): moved_spider_management=true
	check(moved_spider_management,"Moved Spider keeps valid nursery/internal management controls enabled")
	var worker: GameState.Unit=board.game_state.units[2]
	board.select_at(_screen(worker.cell_id)); var worker_hp:=worker.hp; worker.hp=maxi(1,worker.hp-1); board._refresh_display()
	check(board.unit_info_panel.title_label.text=="WORKER ANT" and board.unit_info_panel.squad_label.visible and board.unit_info_panel.squad_label.text.contains("/ 5"),"Changing selection updates identity, preview data, and squad count")
	check(board.unit_info_panel.health_label.text.contains("%d / %d" % [worker.hp,worker.max_hp]),"Authoritative HP changes update the overlay immediately")
	worker.hp=worker_hp; board.clear_selection(); check(not board.unit_info_panel.visible,"Deselection collapses the tactical overlay without stale data")
	var attacker: GameState.Unit; var target: GameState.Unit
	for candidate: GameState.Unit in board.game_state.units.values():
		if candidate.controller_id==1 and candidate.attack_damage>0 and attacker==null: attacker=candidate
		elif candidate.controller_id==2 and candidate.attack_damage>0 and target==null: target=candidate
	target.cell_id=board.grid.get_neighbors(attacker.cell_id)[0]; board.game_state.refresh_visibility()
	board.select_at(_screen(attacker.cell_id))
	var attack_button: Button
	for child: Node in board.unit_info_panel.action_flows[UnitInfoPanel.GROUP_ATTACKS].get_children():
		if child is Button: attack_button=child; break
	check(attack_button!=null and not attack_button.disabled and attack_button.tooltip_text.contains("Damage:") and attack_button.tooltip_text.contains("Range:"),"Data-driven attack option exposes effective combat information")
	var selected_before_panel_click:=board.selected_unit_id
	click(board.unit_info_panel.get_global_rect().position+Vector2(8,8))
	check(board.selected_unit_id==selected_before_panel_click,"Unit overlay consumes clicks instead of interacting with the world behind it")
	attack_button.pressed.emit()
	check(board.selected_unit_id==attacker.id and board.input_mode==StrategicInputMode.Kind.ATTACK,"Overlay attack button consumes UI input and enters authoritative targeting mode")
	click(_screen(target.cell_id),MOUSE_BUTTON_LEFT)
	check(board.game_state.combat_orders.intents.has(attacker.id) and board.game_state.combat_orders.intents[attacker.id].target_id==target.id,"Right-clicking an enemy with an owned unit selected queues its attack")
	check(board.attack_order_overlay.arrow_views.has(attacker.id),"Queued attack displays a world-space arrow")
	var attack_arrow: MeshInstance3D=board.attack_order_overlay.arrow_views[attacker.id]
	var arrow_material:=attack_arrow.material_override as StandardMaterial3D
	check(arrow_material!=null and arrow_material.albedo_color==AttackOrderOverlay.ARROW_COLOR and arrow_material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Queued attack arrow is opaque red")
	var cancel_button: Button
	for child: Node in board.unit_info_panel.action_flows[UnitInfoPanel.GROUP_STANCES].get_children():
		if child is Button and child.text.begins_with("Cancel"): cancel_button=child
	check(board.unit_info_panel.queued_panel.visible and board.unit_info_panel.queued_label.text.contains("QUEUED ATTACK") and cancel_button!=null,"Selected unit shows queued target timing and cancel control")
	cancel_button.pressed.emit()
	check(not board.game_state.combat_orders.intents.has(attacker.id) and board.attack_order_overlay.arrow_views.is_empty(),"Cancelling removes the queued attack and its arrow")
	board.game_state.combat_orders.intents[target.id]=CombatIntent.new(target.controller_id,target.id,"counter",-1,board.game_state.round_number)
	board.select_at(_screen(target.cell_id))
	check(not board.unit_info_panel.queued_panel.visible and not board.unit_label.text.contains("Combat order queued") and not board.unit_label.text.contains("Counter cooldown"),"Visible enemy inspection does not reveal hidden orders or cooldown state")
	board.game_state.combat_orders.intents.erase(target.id); board.select_at(_screen(attacker.cell_id))
	var neutral_cell:=target.cell_id
	for relocation: int in board.grid.breadth_first(neutral_cell).order:
		if not board.game_state.is_cell_blocked(relocation): target.cell_id=relocation; break
	board.game_state.controllers[50]=ControllerState.new(50,ControllerState.NEUTRAL_AI,"")
	var neutral_target:=GameState.Unit.new(board.game_state.allocate_id(),50,"wild_grazer",neutral_cell,-1,board.game_state.registry)
	board.game_state.units[neutral_target.id]=neutral_target; target=neutral_target
	board.game_state.refresh_visibility(); board._refresh_display()
	check(board.attack_tiles.has(neutral_cell) and board._owner_color(50).r>board._owner_color(50).g,"Neutral red placeholder is presented as a legal deliberate attack target")
	click(_screen(target.cell_id),MOUSE_BUTTON_RIGHT)
	var queued_target_hp:=target.hp
	check(board.game_state.combat_orders.intents.has(attacker.id) and board.game_state.combat_orders.intents[attacker.id].target_id==target.id,"Spider right-click queues an attack against the selected neutral red placeholder")

	check(board.rules.try_end_turn(1).success,"Switch to Baumeister succeeds")
	board.clear_selection(); board._refresh_display()
	check(board.resource_bar.get_node_or_null("Resource_materials")!=null and board.resource_bar.get_node_or_null("Resource_energy")!=null and board.resource_bar.get_node_or_null("Resource_unity")!=null,"Active-turn switch rebuilds faction resources")
	check(board.turn_label.text.contains("Simultaneous player turns") and board.turn_label.text.contains("1 planning"),"Shared-turn HUD shows the remaining planning player")
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
	check(board.rules.try_end_turn(2).success,"Second movement phase ends")
	board._refresh_display()
	check(not board.game_state.units.has(target.id) or board.game_state.units[target.id].hp<queued_target_hp,"Right-clicked attack executes in shared combat resolution")
	check(board.attack_order_overlay.arrow_views.is_empty(),"Attack arrow clears after shared combat resolution")
	check(board.end_turn_button.text!="Lock Combat" and board.game_state.turn_state.neutral_phase,"Combat resolves automatically into neutral activity without a Lock Combat action")
	await finish("Strategic UI")
