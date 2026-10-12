extends SceneTree
const Snapshot=preload("res://tests/test_state.gd")

var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func make_state() -> GameState:
	return GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","living_migration"],"simultaneous_combat":false})

func _run() -> void:
	var state:=make_state(); var rules:=GameRules.new(state)
	var ids:=state.registry.faction("living_migration").technology_ids
	check(ids.size()>=15,"At least fifteen unlockables")
	check(rules.available_technologies(1)==PackedStringArray(["lm_symbiotic_foundations"]),"Only the first root is available initially")
	for id: String in ids:
		var definition:=state.registry.technology(id)
		check(not definition.unlock_tags.is_empty() or not definition.unlock_unit_ids.is_empty(),id+" has a gameplay unlock")
		if id=="lm_symbiotic_foundations": continue
		check(not definition.prerequisite_ids.is_empty(),id+" requires an earlier root")
		var before:=Snapshot.snapshot(state)
		check(not rules.research_rules.start_research(1,id).success and Snapshot.snapshot(state)==before,"Locked root cannot mutate research: "+id)
	for id: String in state.registry.technology_order():
		if id not in ids: continue
		check(rules.research_rules.start_research(1,id).success,"Reachable node starts: "+id)
		check(not rules.research_rules.start_research(1,id).success,"No concurrent research")
		check(rules.research_rules.add_research_progress(1,state.registry.technology(id).research_cost).success,"Progress completes node: "+id)
		check(not rules.research_rules.start_research(1,id).success,"Completed research cannot restart")
	check(state.players[1].research.completed_ids.size()==15 and rules.available_technologies(1).is_empty(),"All fifteen nodes are reachable and complete")
	check(state.players[2].research.completed_ids.is_empty(),"Research remains player-specific")
	state=make_state(); rules=GameRules.new(state)
	rules.try_end_turn(1)
	var phase_before:=Snapshot.snapshot(state)
	check(not rules.start_research(1,"lm_symbiotic_foundations").success and Snapshot.snapshot(state)==phase_before,"Finished players cannot start research outside their phase")
	state=GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","living_migration"],"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_player_turns":true})
	rules=GameRules.new(state)
	check(rules.start_research(1,"lm_symbiotic_foundations").success and rules.start_research(2,"lm_symbiotic_foundations").success,"Both humans can research independently during their shared phase")
	state=make_state(); rules=GameRules.new(state)
	var spider: GameState.Unit=state.units[1]
	spider.spider_state.slots.append("food_production"); spider.spider_state.slots.append("research_building")
	var baseline: Dictionary=rules.living_migration_rules.economic_summary(1).production
	state.players[1].research.completed_ids=PackedStringArray(["lm_silk_glands","lm_abundant_organs","lm_root_memory"])
	var upgraded: Dictionary=rules.living_migration_rules.economic_summary(1).production
	check(upgraded.food==baseline.food+1 and upgraded.silk==baseline.silk+1,"Food and Silk upgrades affect income summary")
	state.players[1].research.current_technology_id="lm_symbiotic_foundations"
	rules.living_migration_rules.end_turn(1)
	check(state.players[1].research.accumulated_progress==2,"Root Memory doubles base Research organ output")
	var food_before:=state.players[1].resource_amount("food"); var silk_before:=state.players[1].resource_amount("silk")
	state._process_unit_economy_and_status(1,state.players[1])
	check(state.players[1].resource_amount("silk")==silk_before+upgraded.silk,"Actual Silk production agrees with summary")
	check(state.players[1].resource_amount("food")>food_before,"Upgraded food is actually produced")
	state=make_state(); rules=GameRules.new(state)
	root.size=Vector2i(1280,720)
	var panel:=StrategicResearchPanel.new(); root.add_child(panel); panel.position=Vector2(35,25); panel.size=Vector2(1210,670)
	panel.configure(rules,1); await process_frame; await process_frame
	check(panel.graph!=null and panel.graph.node_buttons.size()==15 and panel.graph.edges.size()==14,"Overlay displays every node and prerequisite link")
	for id: String in ids:
		panel.graph.node_buttons[id].pressed.emit()
		check(panel.selected_id==id,"Root button selects its own technology: "+id)
	for first: Button in panel.graph.node_buttons.values():
		for second: Button in panel.graph.node_buttons.values():
			if first!=second: check(not first.get_rect().intersects(second.get_rect()),"Root nodes do not overlap")
	var emitted: Array[String]=[]; panel.research_requested.connect(func(id: String): emitted.append(id))
	panel._select("lm_root_memory"); panel._start_selected()
	check(panel.start_button.disabled and emitted.is_empty() and panel.detail_label.text.contains("Requires:"),"Locked inspection explains prerequisite and cannot emit research")
	panel._select("lm_symbiotic_foundations"); panel._start_selected()
	check(emitted==["lm_symbiotic_foundations"],"Available selection emits one research intent")
	rules.research_rules.start_research(1,"lm_symbiotic_foundations"); panel.refresh()
	check(panel.technology_state("lm_symbiotic_foundations")==StrategicResearchPanel.RESEARCHING,"Active root is shown as researching")
	rules.research_rules.add_research_progress(1,4); panel.refresh()
	check(panel.technology_state("lm_symbiotic_foundations")==StrategicResearchPanel.COMPLETED and panel.technology_state("lm_ant_adaptation")==StrategicResearchPanel.AVAILABLE,"Completing root opens its branches")
	var original_width:=panel.graph.custom_minimum_size.x; panel._zoom(-0.1)
	check(panel.graph.custom_minimum_size.x<original_width,"Zoom scales the actual graph, not only its font")
	panel._zoom(-0.35); panel._center_selected(); await process_frame; await process_frame
	check(panel.start_button.get_global_rect().end.y<=720 and panel.get_global_rect().end.x<=1280,"Research modal fits 1280x720")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/research_roots_1280.png")
	panel.queue_free(); await process_frame
	print("Research roots checks complete; checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
