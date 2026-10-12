extends SceneTree

var failures:=0
var checks:=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(message)

func setup_for(count: int) -> Dictionary:
	var factions: Array[String]=[]; var kinds: Array[String]=[]
	for index in range(count):
		factions.append("living_migration" if index%2==0 else "baumeister")
		kinds.append(ControllerState.HUMAN)
	return {"faction_ids":factions,"controller_kinds":kinds,"simultaneous_combat":true,"neutral_phase":true,"start_seed":8181}

func test_hold_and_round_progression() -> void:
	for count in range(2,5):
		var state:=GameState.new(PlanetGrid.new(2),setup_for(count)); var rules:=GameRules.new(state)
		state.turn_state.neutral_phase_enabled=true
		for expected_round in range(2,5):
			for actor in range(1,count+1): check(rules.try_end_turn(actor).success,"P%d ends movement in %d-player game" % [actor,count])
			check(state.combat_orders.intents.is_empty() and state.turn_state.phase==TurnState.NEUTRAL,"%d-player empty combat skips directly to neutral" % count)
			check(rules.finish_neutral_phase().success and state.turn_state.phase==TurnState.MANAGEMENT and state.round_number==expected_round and state.active_player==1,"%d-player game reaches round %d without combat input" % [count,expected_round])

	var eliminated_state:=GameState.new(PlanetGrid.new(2),setup_for(4)); var eliminated_rules:=GameRules.new(eliminated_state)
	eliminated_state.turn_state.neutral_phase_enabled=true
	eliminated_state.eliminate_player(3,"test")
	check(eliminated_rules.try_end_turn(1).success and eliminated_rules.try_end_turn(2).success and eliminated_rules.try_end_turn(4).success,"Eliminated player is skipped during movement")
	check(eliminated_state.turn_state.phase==TurnState.NEUTRAL,"Eliminated player cannot block automatic combat progression")

func test_simultaneous_player_turn_flow() -> void:
	var setup:={"faction_ids":["living_migration","baumeister","living_migration","baumeister"],
		"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN,ControllerState.PLAYER_AI,ControllerState.HUMAN],
		"simultaneous_combat":true,"simultaneous_player_turns":true,"start_seed":9191}
	var state:=GameState.new(PlanetGrid.new(2),setup); var rules:=GameRules.new(state)
	check(state.turn_state.order==[3,1,2,4] and state.active_player==3,"Enemy AI is scheduled before the shared human stage")
	check(state.turn_state.can_act(3) and not state.turn_state.can_act(1),"Only the ordered AI can act during the enemy turn")
	check(rules.try_end_turn(3).success and state.turn_state.simultaneous_stage_started,"Ending the enemy turn opens simultaneous player turns")
	check(state.turn_state.can_act(1) and state.turn_state.can_act(2) and state.turn_state.can_act(4),"Every living human can act in the simultaneous stage")
	var p2_unit: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==2 and unit.attack_damage>0: p2_unit=unit; break
	check(p2_unit!=null and rules.submit_combat_intent(2,p2_unit.id,"dodge").success,"A non-cursor human can submit an action concurrently")
	check(rules.try_end_turn(2).success and not state.turn_state.can_act(2) and state.turn_state.can_act(1) and state.turn_state.can_act(4),"A ready player locks independently without ending the shared stage")
	check(not rules.submit_combat_intent(2,p2_unit.id,"dodge").success,"A player cannot issue more orders after becoming ready")
	check(rules.try_end_turn(4).success and state.turn_state.phase==TurnState.MANAGEMENT,"Combat waits for the final human")
	check(rules.try_end_turn(1).success and state.round_number==2 and state.active_player==3 and state.turn_state.can_act(3),"The final human triggers combat and the next round starts with the enemy AI")

	var initial:=GameState.new(PlanetGrid.new(2),setup); initial.turn_state.neutral_phase_enabled=true
	initial.turn_state.begin_initial_enemy_phase(); var initial_rules:=GameRules.new(initial)
	check(initial.turn_state.neutral_phase and initial.round_number==1,"A populated match begins with neutral enemy activity")
	check(initial_rules.finish_neutral_phase().success and initial.active_player==3 and initial.round_number==1,"Neutral activity hands the same round to player AI")
	initial_rules.try_end_turn(3)
	initial_rules.try_end_turn(1); initial_rules.try_end_turn(2); initial_rules.try_end_turn(4)
	check(initial.turn_state.neutral_phase and initial.round_number==2,"Shared combat hands the new round to neutral enemy activity")

	var defender: GameState.Unit
	for unit: GameState.Unit in initial.units.values():
		if unit.controller_id==1 and unit.attack_damage>0: defender=unit; break
	initial.controllers[50]=ControllerState.new(50,ControllerState.NEUTRAL_AI,"")
	initial.relationships.set_relationship(1,50,RelationshipState.Kind.HOSTILE)
	var neutral:=GameState.Unit.new(initial.allocate_id(),50,defender.definition_id,initial.grid.get_neighbors(defender.cell_id)[0],-1,initial.registry)
	initial.units[neutral.id]=neutral; initial.refresh_visibility(); var hp_before:=defender.hp
	check(initial_rules.try_attack(50,neutral.id,defender.id).success and defender.hp==hp_before and initial.combat_orders.intents.has(neutral.id),"Neutral attacks queue during enemy activity instead of resolving early")
	initial_rules.finish_neutral_phase(); initial_rules.try_end_turn(3)
	initial_rules.try_end_turn(1); initial_rules.try_end_turn(2); initial_rules.try_end_turn(4)
	check(defender.hp<hp_before,"Queued neutral attacks resolve with all other attacks after player planning (hp %d/%d, outcomes %s)" % [defender.hp,hp_before,initial.combat_orders.last_outcomes])

	var network_state:=GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","baumeister"],
		"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_player_turns":true})
	var network_rules:=GameRules.new(network_state); var dispatcher:=CommandDispatcher.new(network_state,network_rules)
	dispatcher.register_peer(101,1); dispatcher.register_peer(202,2)
	var p2_end:=dispatcher.dispatch(202,GameplayCommand.create(1,CommandDispatcher.END_TURN,{}))
	check(p2_end.accepted and network_state.turn_state.can_act(1) and not network_state.turn_state.can_act(2),"Network peers can finish in any order during simultaneous turns")
	var snapshot:=ObservationCodec.encode(network_state,1,1)
	check(snapshot.turn.actionable_players==[1] and snapshot.turn.completed_players==[2],"Network snapshots expose actionable and ready players")

func test_spider_road_invariant() -> void:
	var state:=GameState.new(PlanetGrid.new(2),setup_for(2)); var rules:=GameRules.new(state)
	var spider: GameState.Unit=state.units[1]; var worker: GameState.Unit=state.units[2]
	check(not state.living_migration.roads.get(1,{}).has(spider.cell_id),"Initial Spider cell has no road")
	var destination:=state.grid.get_neighbors(spider.cell_id)[0]
	state.living_migration.add_road(1,destination); spider.cell_id=destination
	rules.living_migration_rules.after_move(spider.id,[destination])
	check(not state.living_migration.roads.get(1,{}).has(destination),"Spider moving onto a road removes it")
	var start:=spider.cell_id; var traversed:=state.grid.get_neighbors(start)[0]
	worker.cell_id=start; rules.living_migration_rules.after_move(worker.id,[start,traversed])
	check(not state.living_migration.roads.get(1,{}).has(start) and state.living_migration.roads.get(1,{}).has(traversed),"Worker skips Spider start cell and roads only traversed cells")
	state.living_migration.add_road(1,start); rules.living_migration_rules.start_turn(1)
	check(not state.living_migration.roads.get(1,{}).has(start),"Turn cleanup removes legacy Spider road state")

func test_spider_actions_after_move() -> void:
	var state:=GameState.new(PlanetGrid.new(2),setup_for(2)); var rules:=GameRules.new(state); var spider: GameState.Unit=state.units[1]
	var destination:=rules.reachable(1,spider.id)[0]
	check(rules.try_move(1,spider.id,destination).success and spider.moved,"Spider movement fixture succeeds")
	var config:=rules.living_migration_rules.config_for(1); state.players[1].resources.food=100
	var food_before:=state.players[1].resource_amount("food")
	check(rules.start_internal_construction(1,spider.id,"research_building").success,"Moved Spider can start internal construction")
	check(state.players[1].resource_amount("food")==food_before-config.internal_building_food_cost,"Moved Spider construction charges resources exactly once")
	var recipe_id:="worker_ant_brood"
	var jobs_before:=spider.spider_state.nursery_jobs.size(); food_before=state.players[1].resource_amount("food")
	var recipe:=state.registry.biological_recipe(recipe_id)
	check(rules.queue_biological_production(1,spider.id,recipe_id).success,"Moved Spider can recruit through its nursery")
	check(spider.spider_state.nursery_jobs.size()==jobs_before+1 and state.players[1].resource_amount("food")==food_before-int(recipe.costs.get("food",0)),"Moved Spider nursery respects capacity and charges once")
	check(not rules.queue_biological_production(1,spider.id,"unknown_recipe").success,"Moved Spider nursery still validates recipes")

	var still_state:=GameState.new(PlanetGrid.new(2),setup_for(2)); var still_rules:=GameRules.new(still_state); var still_spider: GameState.Unit=still_state.units[1]
	still_state.players[1].resources.food=100
	check(still_rules.start_internal_construction(1,still_spider.id,"research_building").success,"Stationary Spider uses the same construction rules")

func _combat_pair() -> Dictionary:
	var state:=GameState.new(PlanetGrid.new(2),setup_for(2)); var rules:=GameRules.new(state)
	var attacker: GameState.Unit
	var target: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1 and unit.attack_damage>0 and attacker==null: attacker=unit
		elif unit.controller_id==2 and unit.attack_damage>0 and target==null: target=unit
	target.cell_id=state.grid.get_neighbors(attacker.cell_id)[0]; state.refresh_visibility()
	return {"state":state,"rules":rules,"attacker":attacker,"target":target}

func test_automatic_combat_orders() -> void:
	var fixture:=_combat_pair(); var state: GameState=fixture.state; var rules: GameRules=fixture.rules
	var attacker: GameState.Unit=fixture.attacker; var target: GameState.Unit=fixture.target; var before:=target.hp
	check(rules.submit_combat_intent(1,attacker.id,"attack",target.id).success,"Attack queues during movement")
	check(target.hp==before and state.combat_orders.intents.has(attacker.id),"Queued attack deals no movement-time damage")
	check(rules.clear_combat_intent(1,attacker.id).success and state.combat_orders.intents.is_empty(),"Queued attack can be cancelled")
	rules.submit_combat_intent(1,attacker.id,"attack",target.id); rules.try_end_turn(1)
	check(target.hp==before,"Combat waits for the final movement phase")
	check(rules.try_end_turn(2).success and target.hp<before and state.combat_orders.intents.is_empty() and state.round_number==2,"One-sided combat resolves automatically and clears intents")

	fixture=_combat_pair(); state=fixture.state; rules=fixture.rules; attacker=fixture.attacker
	state.controllers[50]=ControllerState.new(50,ControllerState.NEUTRAL_AI,"")
	var neutral:=GameState.Unit.new(state.allocate_id(),50,"wild_grazer",state.grid.get_neighbors(attacker.cell_id)[1],-1,state.registry)
	state.units[neutral.id]=neutral; state.refresh_visibility(); before=neutral.hp
	check(state.relationships.between(1,50)==RelationshipState.Kind.NEUTRAL and rules.submit_combat_intent(1,attacker.id,"attack",neutral.id).success,"Spider can deliberately queue an attack against a living neutral placeholder")
	check(state.relationships.between(1,50)==RelationshipState.Kind.HOSTILE,"Queuing a neutral attack provokes that controller before shared resolution")
	rules.try_end_turn(1); rules.try_end_turn(2)
	check(not state.units.has(neutral.id) or state.units[neutral.id].hp<before,"Provoked neutral target takes damage in shared combat resolution")

	fixture=_combat_pair(); state=fixture.state; rules=fixture.rules; attacker=fixture.attacker; target=fixture.target
	before=target.hp; rules.submit_combat_intent(1,attacker.id,"attack",target.id); rules.try_end_turn(1)
	target.cell_id=state.grid.breadth_first(attacker.cell_id).order[-1]
	check(rules.try_end_turn(2).success and target.hp==before and state.round_number==2,"Invalid moved target is discarded without blocking the round")

	fixture=_combat_pair(); state=fixture.state; rules=fixture.rules; attacker=fixture.attacker; target=fixture.target; before=target.hp
	state.combat_orders.intents[attacker.id]=CombatIntent.new(1,attacker.id,"attack",target.id,state.round_number-1)
	rules.try_end_turn(1); rules.try_end_turn(2)
	check(target.hp==before and state.combat_orders.intents.is_empty(),"Stale previous-round intent is discarded and cleared")

	var four:=GameState.new(PlanetGrid.new(2),setup_for(4)); var four_rules:=GameRules.new(four)
	var units: Dictionary={}
	for unit: GameState.Unit in four.units.values():
		if unit.attack_damage>0 and not units.has(unit.controller_id): units[unit.controller_id]=unit
	var p1: GameState.Unit=units[1]; var p2: GameState.Unit=units[2]; var p3: GameState.Unit=units[3]
	p2.cell_id=four.grid.get_neighbors(p1.cell_id)[0]; four.refresh_visibility()
	for cycle in range(2):
		check(four_rules.submit_combat_intent(1,p1.id,"attack",p2.id).success,"P1 queues attack in four-player round")
		four_rules.try_end_turn(1); four_rules.try_end_turn(2)
		check(four_rules.submit_combat_intent(3,p3.id,"dodge").success,"P3 queues Dodge in movement")
		four_rules.try_end_turn(3); check(four_rules.try_end_turn(4).success,"P4 ends with no action and triggers resolution")
		check(four.round_number==cycle+2 and four.turn_state.phase==TurnState.MANAGEMENT and four.active_player==1 and four.combat_orders.intents.is_empty(),"Four-player automatic combat reaches next round")

func test_worker_formation_and_road_geometry() -> void:
	var profile:=load("res://assets/factions/swarm/units/worker_ant/visual.tres") as ModelVisualDefinition
	check(profile.squad_member_scale<1.0 and profile.squad_spacing>1.0 and profile.squad_formation=="cross_five","Worker uses compact models in a spaced five-member formation")
	var positions:={}
	for index in range(5): positions[EntityView._formation_offset(index,5,profile.squad_formation)]=true
	check(positions.size()==5,"Worker formation positions never overlap")
	var grid:=PlanetGrid.new(1); var cell_id:=0; var overlay:=AntRoadOverlay.new(); overlay.grid=grid
	var neighbors:=grid.get_neighbors(cell_id)
	for connection_count in range(1,neighbors.size()+1):
		overlay.visible_roads={cell_id:1}
		for index in range(connection_count): overlay.visible_roads[neighbors[index]]=1
		var topology:=overlay.connection_record(cell_id)
		check(topology.connected_neighbors.size()==connection_count and topology.exposed_edges.size()==grid.get_cell(cell_id).polygon_vertices.size()-connection_count,"Road topology derives %d connected edge(s)" % connection_count)
	var geometry:=overlay.edge_geometry_record(cell_id,0)
	var expected: Vector3=geometry.a.slerp(geometry.b,0.5).normalized()
	check((geometry.midpoint as Vector3).is_equal_approx(expected),"Road connector target is the shared-edge midpoint")
	check((geometry.inner_a as Vector3).angle_to(grid.get_cell(cell_id).up)<(geometry.a as Vector3).angle_to(grid.get_cell(cell_id).up),"Border strip runs inward from the real polygon edge")

func _init() -> void:
	test_hold_and_round_progression(); test_simultaneous_player_turn_flow(); test_automatic_combat_orders(); test_spider_road_invariant(); test_spider_actions_after_move(); test_worker_formation_and_road_geometry()
	print("Bugfix UX checks: %d; failures=%d" % [checks,failures])
	quit(1 if failures else 0)
