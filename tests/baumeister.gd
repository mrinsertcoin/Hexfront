extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<50: push_error(message)

func make_state(first: String="baumeister",second: String="living_migration") -> GameState:
	return GameState.new(PlanetGrid.new(2),{"faction_ids":[first,second],"controller_kinds":[ControllerState.HUMAN,ControllerState.PLAYER_AI]})

func pillar_for(state: GameState,controller: int) -> GameState.Structure:
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller and structure.pillar_state!=null: return structure
	return null

func cycle_to_one(rules: GameRules) -> void:
	if rules.state.active_player==1: rules.try_end_turn(1)
	if rules.state.active_player==2: rules.try_end_turn(2)

func test_content_economy_and_districts() -> void:
	var registry:=ContentRegistry.new()
	check(registry.validate().is_empty(),"Baumeister content validates")
	var faction:=registry.faction("baumeister")
	check(faction!=null and faction.playable and faction.gameplay_config is BaumeisterConfig,"Baumeister is typed and playable")
	for id in ["food","materials","energy","unity"]: check(registry.resource(id)!=null,"Resource exists: "+id)
	for id in ["mine","greenhouse","power_plant","civic_monument","barracks","hospital","workshop"]: check(registry.district(id)!=null,"District exists: "+id)
	check(registry.district("mine").turn_production=={"materials":3},"Mine produces Materials")
	check(registry.district("greenhouse").turn_production=={"food":3},"Greenhouse produces Food")
	check(registry.district("power_plant").turn_production=={"energy":3},"Power Plant produces Energy")
	check(registry.district("civic_monument").turn_production=={"unity":2},"Civic Monument produces Unity")
	check("recruits_infantry" in registry.district("barracks").tags,"Barracks has infantry role")
	check("heals_biological" in registry.district("hospital").tags,"Hospital has biological healing role")
	check("recruits_vehicle" in registry.district("workshop").tags,"Workshop has vehicle role")
	var state:=make_state(); var rules:=GameRules.new(state); var pillar:=pillar_for(state,1)
	check(pillar!=null and pillar.pillar_state.integrity==20 and pillar.pillar_state.supplied,"Initial pillar is local-Integrity supply origin")
	check(state.players[1].resources=={"food":18,"materials":21,"energy":6,"unity":3},"Starting structure production and unit upkeep process once")
	var before:=state.players[1].resources.duplicate(true); state.start_turn()
	check(state.players[1].resources==before,"Repeated start turn cannot duplicate Baumeister economy")
	var cell:=state.grid.get_neighbors(pillar.cell_id)[3]
	check(rules.build_district(1,pillar.id,cell,"mine").success,"District construction begins authoritatively")
	var district:=state.baumeister.district_at(cell)
	check(district!=null and not district.completed,"District is not instantly operational")
	check(not rules.build_district(1,pillar.id,cell,"greenhouse").success,"District cell has exactly one owner")
	check(rules.baumeister_rules.district_cells(pillar.id).size()==state.grid.get_neighbors(pillar.cell_id).size(),"Pillar exposes at most six topology neighbors")
	cycle_to_one(rules); cycle_to_one(rules)
	check(district.completed,"District finishes after authored build time")
	for record in [["greenhouse",100],["power_plant",101],["civic_monument",102]]:
		var extra:=state.baumeister.add_district(1,pillar.id,record[1],record[0],1); extra.construction_progress=1
	var before_income:=state.players[1].resources.duplicate(true); cycle_to_one(rules)
	check(state.players[1].resource_amount("materials")==before_income.materials+4,"Completed Mine and pillar produce Materials exactly once")
	check(state.players[1].resource_amount("food")==before_income.food+1,"Greenhouse, pillar and biological upkeep resolve Food exactly once")
	check(state.players[1].resource_amount("energy")==before_income.energy+3 and state.players[1].resource_amount("unity")==before_income.unity+2,"Power and civic districts produce Energy and Unity exactly once")

func test_network_integrity_and_movement() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var pillar:=pillar_for(state,1); var engineer: GameState.Unit=state.units[2]
	state.players[1].resources.materials=100
	var candidates:=rules.baumeister_rules.candidate_pillar_cells(1,engineer.id,pillar.id)
	check(not candidates.is_empty(),"Bridge planner exposes legal pillar candidates")
	var far:=state.grid.breadth_first(pillar.cell_id).order[-2]
	check(not rules.start_bridge_extension(1,engineer.id,pillar.id,far).success,"Map-wide pillar placement is rejected")
	var destination:=candidates[0]; var longest:=0
	for candidate: int in candidates:
		var length:=rules.baumeister_rules.bridge_path(pillar.cell_id,candidate,1).size()
		if length>longest: longest=length; destination=candidate
	var start:=rules.start_bridge_extension(1,engineer.id,pillar.id,destination)
	check(start.success and start.path.size()>=2,"Bridge extension creates a bounded logical path")
	var bridge: BridgeState=state.baumeister.bridges.values()[0]; var second:=pillar_for_id(state,bridge.endpoint_b)
	check(second!=null and not second.pillar_state.supplied and not bridge.completed,"New pillar exists locally while incomplete bridge leaves it isolated")
	rules.try_end_turn(1); rules.try_end_turn(2); rules.try_end_turn(1); rules.try_end_turn(2)
	check(bridge.completed and second.pillar_state.supplied,"Completed bridge propagates supply")
	check(rules.baumeister_rules.movement_edge_cost(state.units[1],bridge.path[0],bridge.path[1])<rules.baumeister_rules.config_for(1).ordinary_edge_cost,"Supplied bridge edge has reduced movement cost")
	if bridge.path.size()>=3:
		var mover:=state.units[1]; mover.cell_id=bridge.path[1]; mover.moved=false; mover.attacked=false
		var move_destination:=bridge.path[bridge.path.size()-2]
		var preview:=rules.path_to(1,mover.id,move_destination); var repeated:=rules.path_to(1,mover.id,move_destination)
		var moved:=rules.try_move(1,mover.id,move_destination)
		check(not preview.is_empty() and preview==repeated and moved.success and moved.path==preview,"Weighted path preview and validation share deterministic tie-breaking")
	bridge.hp=0; rules.baumeister_rules.recalculate_supply(1)
	check(not second.pillar_state.supplied and state.structures.has(second.id),"Bridge destruction isolates without destroying pillar")
	var local_cell:=state.grid.get_neighbors(second.cell_id)[0]
	var local:=state.baumeister.add_district(1,second.id,local_cell,"greenhouse",1); local.construction_progress=1
	var food:=state.players[1].resource_amount("food"); cycle_to_one(rules)
	check(state.players[1].resource_amount("food")>=food+1,"Isolated pillar retains ordinary local production")
	engineer.cell_id=bridge.path[0]; engineer.moved=false; engineer.attacked=false; state.active_player=1
	check(rules.repair_bridge(1,engineer.id,bridge.id).success and bridge.hp>0,"Bridgewright repairs same bridge record")
	bridge.hp=bridge.max_hp; rules.baumeister_rules.recalculate_supply(1)
	check(second.pillar_state.supplied,"Bridge repair restores network supply")
	second.hp-=5; second.pillar_state.integrity-=5; engineer.moved=false; engineer.attacked=false; engineer.cell_id=state.grid.get_neighbors(second.cell_id)[0]
	check(rules.repair_structure(1,engineer.id,second.id).success and second.hp>second.max_hp-5 and second.pillar_state.integrity>15,"Pillar HP and local Integrity repair independently")

func pillar_for_id(state: GameState,id: int) -> GameState.Structure: return state.structures.get(id)

func test_units_support_artillery_and_designation() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var registry:=state.registry
	check("anti_air" in registry.unit("anti_air_tank").tags,"AA unit preserves future interception capability")
	var cell:=state.grid.get_neighbors(state.units[2].cell_id)[0]
	var vehicle:=GameState.Unit.new(state.allocate_id(),1,"assault_tank",cell,-1,registry); vehicle.hp-=5; state.units[vehicle.id]=vehicle
	state.players[1].resources.materials=100
	check(rules.repair_unit(1,2,vehicle.id).success and vehicle.hp>vehicle.max_hp-5,"Bridgewright repairs adjacent vehicle")
	var medic:=GameState.Unit.new(state.allocate_id(),1,"medic_squad",state.grid.get_neighbors(state.units[1].cell_id)[0],-1,registry); state.units[medic.id]=medic
	var biological:=state.units[5]; biological.cell_id=state.grid.get_neighbors(medic.cell_id)[0]; biological.hp-=3
	check(rules.heal_unit(1,medic.id,biological.id).success,"Medic heals biological personnel")
	medic.moved=false; medic.attacked=false; vehicle.cell_id=state.grid.get_neighbors(medic.cell_id)[0]; vehicle.hp-=1
	check(not rules.heal_unit(1,medic.id,vehicle.id).success,"Medic cannot heal vehicles")
	var artillery:=GameState.Unit.new(state.allocate_id(),1,"long_range_tank",state.grid.get_neighbors(pillar_for(state,1).cell_id)[0],-1,registry); state.units[artillery.id]=artillery
	check(rules.toggle_deployment(1,artillery.id).success and artillery.deployed and artillery.attack_range==4,"Long Range Tank deployment spends action and enables authored range")
	check(rules.reachable(1,artillery.id).is_empty(),"Deployed artillery cannot reposition")
	artillery.moved=false; check(rules.toggle_deployment(1,artillery.id).success and not artillery.deployed,"Artillery can return to MOBILE state")
	var commander:=GameState.Unit.new(state.allocate_id(),1,"trike_commander",state.units[1].cell_id,-1,registry); state.units[commander.id]=commander
	var enemy:=state.units[4]; enemy.cell_id=state.grid.get_neighbors(commander.cell_id)[0]
	state.refresh_visibility()
	check(rules.designate_target(1,commander.id,enemy.id).success and enemy.designation!=null,"Commander applies bounded non-stacking designation")
	var base:=registry.unit(state.units[1].definition_id).attack_damage
	check(UnitStatResolver.attack_damage_against(state.units[1],enemy,registry)==base+1,"Designation bonus resolves centrally against target")

func test_recruitment_district_support_maintenance_and_victory() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var pillar:=pillar_for(state,1)
	var neighbors:=state.grid.get_neighbors(pillar.cell_id)
	var barracks:=state.baumeister.add_district(1,pillar.id,neighbors[0],"barracks",1); barracks.construction_progress=1
	var workshop:=state.baumeister.add_district(1,pillar.id,neighbors[1],"workshop",1); workshop.construction_progress=1
	var hospital:=state.baumeister.add_district(1,pillar.id,neighbors[2],"hospital",1); hospital.construction_progress=1
	check(rules.recruit_error(1,pillar.id,"conqueror_squad").is_empty(),"Barracks authorizes biological infantry recruitment")
	check(not rules.recruit_error(1,pillar.id,"assault_tank").is_empty(),"Research gates advanced vehicle recruitment")
	state.players[1].research.completed_ids.append("bm_armored_fabrication")
	state.players[1].resources={"food":100,"materials":100,"energy":100,"unity":100}
	check(rules.recruit_error(1,pillar.id,"assault_tank").is_empty(),"Supplied Workshop and research authorize vehicle production")
	var destination:=rules.recruit_destinations(1,pillar.id,"assault_tank")[0]; var material_before:=state.players[1].resource_amount("materials"); var energy_before:=state.players[1].resource_amount("energy")
	check(rules.try_recruit(1,pillar.id,"assault_tank",destination).success and state.players[1].resource_amount("materials")==material_before-8 and state.players[1].resource_amount("energy")==energy_before-3,"Vehicle recruitment spends Materials and Energy once")
	pillar.recruit_available=true; state.players[1].research.completed_ids.append("bm_command_network")
	destination=rules.recruit_destinations(1,pillar.id,"trike_commander")[0]; var unity_before:=state.players[1].resource_amount("unity")
	check(rules.try_recruit(1,pillar.id,"trike_commander",destination).success and state.players[1].resource_amount("unity")==unity_before-6,"Hero seam spends Unity once and obeys Workshop recruitment")
	var biological:=state.units[5]; biological.hp-=4; biological.cell_id=state.grid.get_neighbors(hospital.cell_id)[0]
	check(rules.district_support(1,hospital.id,biological.id).success,"Hospital heals biological personnel")
	var vehicle:=state.units[1]; vehicle.hp-=3; vehicle.cell_id=state.grid.get_neighbors(workshop.cell_id)[0]
	check(rules.district_support(1,workshop.id,vehicle.id).success,"Workshop repairs vehicles")
	check(not rules.district_support(1,hospital.id,vehicle.id).success,"Hospital rejects vehicles")

	var engineer:=state.units[2]; engineer.moved=false; engineer.attacked=false; engineer.cell_id=neighbors[3]
	var candidate:=rules.baumeister_rules.candidate_pillar_cells(1,engineer.id,pillar.id)[0]
	rules.start_bridge_extension(1,engineer.id,pillar.id,candidate)
	var bridge: BridgeState=state.baumeister.bridges.values()[0]; bridge.construction_progress=bridge.required_turns
	rules.baumeister_rules.recalculate_supply(1)
	state.baumeister.last_maintenance_serial.erase(1); var before:=state.players[1].resource_amount("materials")
	rules.baumeister_rules.start_turn(1); var after:=state.players[1].resource_amount("materials"); rules.baumeister_rules.start_turn(1)
	check(before-after==1 and state.players[1].resource_amount("materials")==after,"Bridge maintenance charges exactly once per owner turn")
	var integrity_before:=state.structures[bridge.endpoint_b].pillar_state.integrity
	state.players[1].resources.materials=0; state.turn_state.serial+=1; rules.baumeister_rules.start_turn(1)
	check(state.structures[bridge.endpoint_b].pillar_state.integrity==integrity_before-1 and state.baumeister.unpaid_maintenance[1]==1,"Neglected maintenance damages only local Pillar Integrity")

	var second: GameState.Structure=state.structures[bridge.endpoint_b]
	var attacker:=state.units[3]; attacker.cell_id=bridge.path[0]; state.active_player=2
	var damage:=rules.damage_bridge(2,attacker.id,bridge.id)
	check(damage.success and bridge.hp<bridge.max_hp,"Bridge is an authoritative damage target")
	bridge.hp=0; rules.baumeister_rules.recalculate_supply(1)
	check(not second.pillar_state.supplied,"Destroyed bridge immediately splits supply graph")

	state=make_state("red","baumeister"); rules=GameRules.new(state); state.active_player=1
	var enemy_pillars: Array[GameState.Structure]=[]
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==2 and structure.pillar_state!=null: enemy_pillars.append(structure)
	var original:=enemy_pillars[0]
	var extra:=GameState.Structure.new(state.allocate_id(),2,"pillar_city",state.grid.get_neighbors(original.cell_id)[0],-1,state.registry)
	extra.pillar_state=PillarState.new(20,false); state.structures[extra.id]=extra
	var attacker_unit:=state.units[1]; attacker_unit.cell_id=state.grid.get_neighbors(original.cell_id)[1]
	state.refresh_visibility()
	var integrity:=original.pillar_state.integrity; check(rules.try_attack(1,attacker_unit.id,original.id).success and original.pillar_state.integrity<integrity,"Direct structural damage reduces local Integrity through configured ratio")
	attacker_unit.moved=false; attacker_unit.attacked=false; original.hp=1
	check(rules.try_attack(1,attacker_unit.id,original.id).winner_id==0,"Destroying one of several pillars does not win")
	attacker_unit.moved=false; attacker_unit.attacked=false; attacker_unit.cell_id=state.grid.get_neighbors(extra.cell_id)[0]; extra.hp=1
	state.refresh_visibility()
	check(rules.try_attack(1,attacker_unit.id,extra.id).winner_id==1,"Destroying final headquarters pillar wins")

func test_ai_terminates_legally() -> void:
	var state:=make_state("living_migration","baumeister"); var rules:=GameRules.new(state); var ai:=SimpleAI.new()
	var legal:=true; var built:=false; var recruited:=false; var terminated:=true
	for _round in range(5):
		if state.active_player==1: rules.try_end_turn(1)
		var attempts:=0
		while state.active_player==2 and state.winner_id==0 and attempts<80:
			var action:=ai.choose_action(state,rules,2); var result: GameRules.Result
			match action.get("type",""):
				"attack": result=rules.try_attack(2,action.attacker,action.target)
				"move": result=rules.try_move(2,action.unit,action.dest)
				"recruit": result=rules.try_recruit(2,action.hq_id,action.kind,action.dest); recruited=recruited or result.success
				"bm_district": result=rules.build_district(2,action.pillar,action.cell,action.district); built=built or result.success
				"bm_expand": result=rules.start_bridge_extension(2,action.engineer,action.pillar,action.cell); built=built or result.success
				"bm_repair_bridge": result=rules.repair_bridge(2,action.engineer,action.bridge)
				"bm_repair_pillar": result=rules.repair_structure(2,action.engineer,action.pillar)
				"bm_deploy": result=rules.toggle_deployment(2,action.unit)
				"research": result=rules.start_research(2,action.technology)
				_: result=rules.try_end_turn(2)
			legal=legal and result.success; ai.record_result(action,result.success); attempts+=1
		terminated=terminated and attempts<80 and state.active_player!=2
		if state.winner_id!=0: break
	check(legal and terminated,"Baumeister AI uses legal commands and terminates")
	check(built and recruited,"Baumeister AI constructs infrastructure and recruits through normal rules")

func _run() -> void:
	test_content_economy_and_districts()
	test_network_integrity_and_movement()
	test_units_support_artillery_and_designation()
	test_recruitment_district_support_maintenance_and_victory()
	test_ai_terminates_legally()
	print("Baumeister checks: %d; failures=%d" % [checks,failures])
	quit(1 if failures else 0)
