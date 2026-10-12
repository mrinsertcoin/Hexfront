extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<50: push_error(message)

func make_state(first: String="living_migration",second: String="baumeister") -> GameState:
	return GameState.new(PlanetGrid.new(2),{"faction_ids":[first,second],"controller_kinds":[ControllerState.HUMAN,ControllerState.PLAYER_AI],"simultaneous_combat":false})

func cycle_to_one(rules: GameRules) -> void:
	if rules.state.active_player==1: rules.try_end_turn(1)
	if rules.state.active_player==2: rules.try_end_turn(2)

func _run() -> void:
	test_rosters_and_research()
	test_economy_upkeep_and_affordability()
	test_mechanic_upgrades()
	test_duplicate_faction_independence_and_commands()
	test_deterministic_analysis_and_report()
	print("Alpha 0.1 balance checks complete; checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func test_rosters_and_research() -> void:
	var registry:=ContentRegistry.new()
	check(registry.validate().is_empty(),"All balanced content definitions validate")
	var living:=registry.faction("living_migration"); var builder:=registry.faction("baumeister")
	check(living.unit_roster_ids.size()==15 and _unique_count(living.unit_roster_ids)==15,"Living Migration retains 15 unique playable units")
	check(builder.unit_roster_ids.size()==8 and _unique_count(builder.unit_roster_ids)==8,"Baumeister retains 8 unique playable units")
	check(living.technology_ids.size()==15,"Living Migration has 15 rooted technologies")
	check(builder.technology_ids.size()==10,"Baumeister has 10 concise technologies")
	var state:=make_state(); var rules:=GameRules.new(state)
	check(rules.research_rules.is_unit_unlocked(1,"fighter_ant"),"Living Migration has a viable starting military recruit")
	check(not rules.research_rules.is_unit_unlocked(1,"fire_ant") and not rules.research_rules.is_unit_unlocked(1,"ant_queen"),"Advanced ants remain research gated")
	state.players[1].research.completed_ids.append("lm_ant_adaptation")
	check(rules.research_rules.is_unit_unlocked(1,"fire_ant") and not rules.research_rules.is_unit_unlocked(1,"ant_queen"),"Ant Adaptation unlocks only its authored tier")
	check("lm_queen_signal" in rules.available_technologies(1),"Queen Signal prerequisite resolves after Ant Adaptation")
	check("lm_apex_metamorphosis" not in rules.available_technologies(1),"Deep research remains unavailable without its prerequisite")
	state=make_state("baumeister","living_migration"); rules=GameRules.new(state)
	check(not rules.research_rules.is_unit_unlocked(1,"assault_tank"),"Baumeister vehicles are research gated")
	state.players[1].research.completed_ids.append("bm_industrial_foundations")
	check(not rules.research_rules.is_unit_unlocked(1,"assault_tank") and "bm_armored_fabrication" in rules.available_technologies(1),"Industrial Foundations exposes Armored Fabrication without skipping its unit gate")
	# The unit belongs to Armored Fabrication and must remain locked until that technology completes.
	check(not rules.research_rules.is_unit_unlocked(1,"long_range_tank"),"Artillery remains gated behind Armored Fabrication")
	state.players[1].research.completed_ids.append("bm_armored_fabrication")
	check(rules.research_rules.is_unit_unlocked(1,"assault_tank") and "bm_deployed_artillery" in rules.available_technologies(1),"Armored Fabrication unlock and dependent technology resolve")

func test_economy_upkeep_and_affordability() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var player:=state.players[1]
	player.resources.food=0
	cycle_to_one(rules)
	check(player.resource_amount("food")>=0 and state.living_migration.unpaid_upkeep[1].get("food",0)>0,"Living Migration shortage records unpaid upkeep without negative Food")
	var unpaid_producers:=0
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1 and not unit.upkeep_paid: unpaid_producers+=1
	check(unpaid_producers>0,"Individual unpaid Living Migration units become inactive")
	for amount: int in player.resources.values(): check(amount>=0,"Living Migration resources never become negative")
	state=make_state("baumeister","living_migration"); rules=GameRules.new(state); player=state.players[1]
	var pillar:=_pillar(state,1); var cell:=state.grid.get_neighbors(pillar.cell_id)[3]
	var mine:=state.baumeister.add_district(1,pillar.id,cell,"mine",1); mine.construction_progress=1
	player.resources.energy=0
	var before_materials:=player.resource_amount("materials"); cycle_to_one(rules)
	var first_gain:=player.resource_amount("materials")-before_materials
	check(not mine.maintenance_paid and first_gain==4,"Unpowered Mine produces once, then becomes unmaintained")
	before_materials=player.resource_amount("materials"); cycle_to_one(rules)
	check(player.resource_amount("materials")-before_materials==1,"Unmaintained Mine cannot form an infinite Materials loop")
	for amount: int in player.resources.values(): check(amount>=0,"Baumeister resources never become negative")
	var barracks:=state.baumeister.add_district(1,pillar.id,state.grid.get_neighbors(pillar.cell_id)[4],"barracks",1); barracks.construction_progress=1
	player.resources={"food":0,"materials":0,"energy":0,"unity":0}; pillar.recruit_available=true
	check(not rules.try_recruit(1,pillar.id,"conqueror_squad",state.grid.get_neighbors(pillar.cell_id)[0]).success,"Unaffordable recruitment is rejected before resource mutation")
	for amount: int in player.resources.values(): check(amount>=0,"Rejected recruitment preserves non-negative resources")

func test_mechanic_upgrades() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var spider: GameState.Unit=state.units[1]
	state.players[1].research.completed_ids.append("lm_regenerative_clearings")
	var destination:=_free_neighbor(state,spider.cell_id); var before:=state.players[1].resource_amount("food")
	check(rules.try_move(1,spider.id,destination).success,"Upgraded Spider can perform its normal harvest move")
	check(state.players[1].resource_amount("food")==before+5 and state.living_migration.terrain_at(destination).regrowth_turns_remaining==2,"Regenerative Clearings changes both yield and recovery")
	state=make_state("baumeister","living_migration"); rules=GameRules.new(state)
	var pillar:=_pillar(state,1); var engineer: GameState.Unit=state.units[2]
	var candidates:=rules.baumeister_rules.candidate_pillar_cells(1,engineer.id,pillar.id)
	var destination_cell:=candidates[0]; var base_cost:=rules.baumeister_rules.bridge_cost(1,pillar.cell_id,destination_cell).materials
	state.players[1].research.completed_ids.append("bm_logistics_grid")
	var improved_cost:=rules.baumeister_rules.bridge_cost(1,pillar.cell_id,destination_cell).materials
	check(improved_cost<base_cost,"Logistics Grid reduces authored bridge edge cost")
	state.players[1].research.completed_ids.append("bm_repair_doctrine")
	state.players[1].resources.materials=999
	check(rules.start_bridge_extension(1,engineer.id,pillar.id,destination_cell).success,"Improved bridge remains constructible")
	var bridge: BridgeState=state.baumeister.bridges.values()[0]
	check(bridge.required_turns==1 and bridge.max_hp==16,"Repair Doctrine applies stronger, faster bridge construction")

func test_duplicate_faction_independence_and_commands() -> void:
	var state:=make_state("living_migration","living_migration"); var rules:=GameRules.new(state)
	state.players[1].research.completed_ids.append("lm_ant_adaptation")
	check(rules.research_rules.is_unit_unlocked(1,"fire_ant") and not rules.research_rules.is_unit_unlocked(2,"fire_ant"),"Duplicate Living Migration players keep independent research")
	state.players[1].resources.food=0; cycle_to_one(rules)
	check(state.players[1].resources!=state.players[2].resources,"Duplicate faction economies remain independent")
	for command: String in [CommandDispatcher.START_RESEARCH,CommandDispatcher.QUEUE_BIOLOGICAL_PRODUCTION,
		CommandDispatcher.DEPLOY_BIOLOGICAL,CommandDispatcher.START_SPIDER_CONSTRUCTION,CommandDispatcher.BUILD_ROAD,
		CommandDispatcher.BUILD_DISTRICT,CommandDispatcher.START_BRIDGE_EXTENSION,CommandDispatcher.TOGGLE_DEPLOYMENT,
		CommandDispatcher.HEAL_UNIT,CommandDispatcher.REPAIR_BRIDGE,CommandDispatcher.DESIGNATE_TARGET]:
		check(command in CommandDispatcher.COMMAND_TYPES,"Multiplayer command inventory includes "+command)

func test_deterministic_analysis_and_report() -> void:
	var registry:=ContentRegistry.new(); var first:=BalanceAnalysis.development_timings(registry); var second:=BalanceAnalysis.development_timings(registry)
	check(first==second,"Balance simulation is deterministic")
	check(first.living_migration.first_additional_production_turn==3 and first.baumeister.first_additional_production_turn==3,"Additional production is comparable at turn 3")
	check(first.living_migration.first_military_recruit_turn==3 and first.baumeister.first_military_recruit_turn==3,"First additional military recruit is comparable at turn 3")
	check(first.living_migration.first_researched_upgrade_turn==5 and first.baumeister.first_researched_upgrade_turn==5,"First research upgrade is comparable at turn 5")
	check(first.living_migration.first_expansion_turn==6 and first.baumeister.first_expansion_turn==3,"Expansion timing preserves asymmetric mobile versus infrastructure identity")
	for faction_id: String in ["living_migration","baumeister"]:
		var army: Dictionary=first[faction_id].representative_army
		check(not army.cost.is_empty() and not army.upkeep.is_empty(),"Representative midgame army has explicit cost and upkeep: "+faction_id)
	var report:=BalanceAnalysis.generate_report(registry)
	for faction: FactionDefinition in registry.playable_factions():
		if faction.id not in ["living_migration","baumeister"]: continue
		for unit_id: String in faction.unit_roster_ids: check(registry.unit(unit_id).display_name in report,"Generated report includes "+unit_id)
	check(report.contains("provisional Alpha 0.1 values") and report.contains("Simulation assumptions"),"Generated report labels provisional values and assumptions")

func _pillar(state: GameState,controller_id: int) -> GameState.Structure:
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller_id and structure.pillar_state!=null: return structure
	return null

func _free_neighbor(state: GameState,cell_id: int) -> int:
	for neighbor: int in state.grid.get_neighbors(cell_id):
		if not state.is_cell_blocked(neighbor): return neighbor
	return -1

func _unique_count(values: PackedStringArray) -> int:
	var unique:={}
	for value: String in values: unique[value]=true
	return unique.size()
