extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<40: push_error(message)

func make_state(first: String="living_migration",second: String="red") -> GameState:
	return GameState.new(PlanetGrid.new(2),{"faction_ids":[first,second],"controller_kinds":[ControllerState.HUMAN,ControllerState.PLAYER_AI],"simultaneous_combat":false})

func cycle_to_player_one(rules: GameRules) -> void:
	if rules.state.active_player==1: rules.try_end_turn(1)
	if rules.state.active_player==2: rules.try_end_turn(2)

func first_free_neighbor(state: GameState,cell_id: int) -> int:
	for id: int in state.grid.get_neighbors(cell_id):
		if not state.is_cell_blocked(id): return id
	return -1

func test_content_and_economy() -> void:
	var registry:=ContentRegistry.new()
	check(registry.validate().is_empty(),"Living Migration production content validates")
	for id in ["food","silk","synapse"]: check(registry.resource(id)!=null,"Faction resource loads: "+id)
	var faction:=registry.faction("living_migration")
	check(faction!=null and faction.display_name=="The Living Migration" and faction.playable,"Living Migration is selectable")
	check(faction.gameplay_config is LivingMigrationConfig,"Faction has typed gameplay tuning")
	check(registry.unit("living_spider").movement==4,"Spider starting movement is four")
	for id in ["living_spider","mite","poison_dart_frog","bullfrog","unke"]:
		check("synaptic" in registry.unit(id).tags,"Synaptic capability authored for "+id)
		check(registry.unit(id).turn_production.get("synapse",0)>0,"Synaptic production is data-driven for "+id)
	for unit_id: String in faction.unit_roster_ids:
		check(registry.unit(unit_id).upkeep.get("food",0)>0,"Every buildable faction unit has Food upkeep: "+unit_id)
	var state:=make_state(); var rules:=GameRules.new(state); var player: PlayerState=state.players[1]
	check(player.resource_amount("food")==19 and player.resource_amount("silk")==10 and player.resource_amount("synapse")==7,"Initial production and upkeep process exactly once")
	var before:=player.resources.duplicate(); state.start_turn()
	check(player.resources==before,"Repeated start-turn call cannot duplicate economy")
	var summary:=rules.living_migration_rules.economic_summary(1)
	check(summary.production=={"food":3,"silk":2,"synapse":2} and summary.upkeep=={"food":4},"Economic summary exposes production and upkeep")
	cycle_to_player_one(rules)
	check(player.resource_amount("food")==18 and player.resource_amount("silk")==12 and player.resource_amount("synapse")==9,"Per-turn production/upkeep remain deterministic")
	player.resources.food=0; var unit_count:=state.units.size(); cycle_to_player_one(rules)
	check(player.resource_amount("food")==0 and state.units.size()==unit_count and state.living_migration.unpaid_upkeep[1].food==1,"Insufficient Food records unpaid upkeep without deleting units")

func test_spider_terrain_slots_and_construction() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var spider: GameState.Unit=state.units[1]
	check(spider.spider_state!=null and spider.spider_state.slot_limit==9 and spider.spider_state.slots.size()==1,"Spider owns nine internal slots and starting Ant Hill")
	check(not rules.choose_nursery(1,spider.id,"marsh").success,"One spider cannot select a second nursery branch")
	var destination:=first_free_neighbor(state,spider.cell_id); var food_before:=state.players[1].resource_amount("food")
	check(rules.try_move(1,spider.id,destination).success,"Mobile spider moves through normal authoritative movement")
	check(state.players[1].resource_amount("food")==food_before+4,"Fresh terrain harvest grants configured Food")
	var terrain:=state.living_migration.terrain_at(destination)
	check(terrain.kind==TerrainConsumptionState.Kind.DEPLETED,"Harvest marks terrain depleted")
	var after_harvest:=state.players[1].resource_amount("food"); rules.living_migration_rules.after_move(spider.id)
	check(state.players[1].resource_amount("food")==after_harvest,"Depleted terrain cannot be harvested twice")
	var config:=rules.living_migration_rules.config_for(1)
	for _turn in range(config.terrain_regrowth_turns): terrain.advance()
	check(terrain.kind==TerrainConsumptionState.Kind.FRESH,"Terrain becomes fresh after configured regrowth")

	state=make_state(); rules=GameRules.new(state); spider=state.units[1]
	state.players[1].resources.silk=100
	check(rules.start_spider_construction(1,spider.id).success,"Spider construction starts through rules")
	var base_cost:=rules.living_migration_rules.spider_cost(1).silk
	destination=first_free_neighbor(state,spider.cell_id); rules.try_move(1,spider.id,destination); rules.try_end_turn(1)
	check(spider.spider_state.construction.progress_turns==1,"Moving does not pause spider construction")
	rules.try_end_turn(2); rules.try_end_turn(1)
	check(spider.spider_state.construction.progress_turns==2,"Stationary spider advances construction identically")
	rules.try_end_turn(2); rules.try_end_turn(1); rules.try_end_turn(2)
	var spider_cell:=first_free_neighbor(state,spider.cell_id)
	check(rules.deploy_spider(1,spider.id,spider_cell).success,"Completed Spider construction deploys a second mobile headquarters")
	check(rules.living_migration_rules.spider_cost(1).silk==base_cost+config.spider_silk_cost_per_owned,"Spider Silk cost scales centrally with owned spiders")

	state=make_state(); rules=GameRules.new(state); spider=state.units[1]
	state.players[1].resources={"food":100,"silk":100,"synapse":100}
	check(rules.queue_biological_production(1,spider.id,"worker_ant_brood").success,"Spider queues biological recruitment")
	destination=first_free_neighbor(state,spider.cell_id); rules.try_move(1,spider.id,destination); rules.try_end_turn(1)
	check(spider.spider_state.nursery_jobs[0].progress_turns==1,"Moving does not pause biological recruitment progress")

	state=make_state(); rules=GameRules.new(state); spider=state.units[1]
	spider.spider_state.slots=PackedStringArray(["ant_hill","a","b","c","d","e","f","g","h"])
	check(not rules.start_internal_construction(1,spider.id,"food_production").success,"Internal construction enforces the nine-slot limit")
	spider.spider_state.slots=PackedStringArray(["ant_hill","research_building"])
	check(rules.start_research(1,"lm_symbiotic_foundations").success,"Living Migration research root starts")
	destination=first_free_neighbor(state,spider.cell_id); rules.try_move(1,spider.id,destination); rules.try_end_turn(1)
	check(state.players[1].research.accumulated_progress==1,"Research continues when its spider moves")

	state=make_state(); rules=GameRules.new(state); spider=state.units[1]; config=rules.living_migration_rules.config_for(1)
	for _turn in range(config.mite_production_interval): cycle_to_player_one(rules)
	check(spider.spider_state.held_mites==1 and spider.spider_state.mite_progress==0,"All spiders use the configured visible mite interval")

func test_ant_hill_connection_roads_and_corpses() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var worker: GameState.Unit=state.units[2]
	state.players[1].resources={"food":999,"silk":999,"synapse":999}
	var accepted_jobs:=0
	for _slot in range(9):
		if rules.queue_biological_production(1,1,"worker_ant_brood").success: accepted_jobs+=1
	check(accepted_jobs==9 and state.units[1].spider_state.nursery_jobs.size()==9,"Ant Hill exposes nine finite production storage slots")
	check(not rules.queue_biological_production(1,1,"worker_ant_brood").success,"Ant Hill rejects a tenth production job")
	state=make_state(); rules=GameRules.new(state); worker=state.units[2]
	check(rules.living_migration_rules.is_ant_connected(worker),"Starting worker has positional Connection independent of Synapse")
	state.players[1].resources.synapse=0
	check(rules.living_migration_rules.is_ant_connected(worker),"Connection does not depend on Synapse balance")
	state.players[1].resources.synapse=100
	check(rules.queue_biological_production(1,1,"fighter_ant_brood").success,"Fighter Ant provides a viable starting military recruit")
	check(not rules.queue_biological_production(1,1,"fire_ant_brood").success,"Research gates advanced Ant Hill production")
	var path: Array[int]=[]; var previous:=worker.cell_id; var roads: Dictionary=state.living_migration.roads[1].duplicate()
	for _step in range(3):
		var candidates: Array[int]=[]
		for cell_id: int in state.grid.get_neighbors(previous):
			if not roads.has(cell_id) and not state.is_cell_blocked(cell_id): candidates.append(cell_id)
		candidates.sort(); check(not candidates.is_empty(),"Road extension candidate exists")
		if candidates.is_empty(): break
		previous=candidates[0]; path.append(previous); roads[previous]=true
	check(rules.try_build_road(1,worker.id,path).success and path.size()==3,"Worker extends three contiguous road cells authoritatively")
	check(not rules.try_build_road(1,worker.id,[state.grid.get_neighbors(previous)[0]]).success,"Worker cannot exceed three road cells in one turn")
	var road_reach:=rules.reachable(1,worker.id); var active_roads:=rules.living_migration_rules.active_road_cells(1)
	check(road_reach.any(func(cell_id: int)->bool: return cell_id not in active_roads),"Worker may traverse land beyond active roads so movement can extend the network")

	var far:=state.grid.breadth_first(0).order[-2]
	var fighter:=GameState.Unit.new(state.allocate_id(),1,"fighter_ant",far,-1,state.registry); state.units[fighter.id]=fighter
	rules.try_end_turn(1)
	check(fighter.disconnected_turns==1,"First disconnected turn stores warning countdown")
	rules.try_end_turn(2); rules.try_end_turn(1)
	check(fighter.disconnected_turns==2,"Second disconnected turn blocks offensive orders")
	var before_distance:=state.grid.distance(fighter.cell_id,state.units[1].cell_id)
	rules.try_end_turn(2)
	check(fighter.moved or state.grid.distance(fighter.cell_id,state.units[1].cell_id)==before_distance,"Disconnected retreat deterministically moves or legally holds")
	if fighter.moved: check(state.grid.distance(fighter.cell_id,state.units[1].cell_id)<before_distance,"Retreat approaches Connection without teleporting")

	var held_cell:=state.grid.breadth_first(0).order[-3]
	var held_ant:=GameState.Unit.new(state.allocate_id(),1,"fighter_ant",held_cell,-1,state.registry)
	held_ant.disconnected_turns=rules.living_migration_rules.config_for(1).disconnection_limit
	state.units[held_ant.id]=held_ant
	for neighbor: int in state.grid.get_neighbors(held_cell):
		var blocker:=GameState.Unit.new(state.allocate_id(),2,"prototype_infantry",neighbor,-1,state.registry)
		state.units[blocker.id]=blocker
	rules.living_migration_rules.start_turn(1)
	check(held_ant.cell_id==held_cell and not held_ant.moved,"Disconnected ant holds position when no legal retreat exists")

	state.active_player=1
	var corpse_cell:=state.grid.get_neighbors(worker.cell_id)[0]
	var corpse:=state.living_migration.add_corpse("prototype_infantry",corpse_cell,3)
	var food_before:=state.players[1].resource_amount("food")
	check(rules.try_consume_corpse(1,worker.id,corpse.id).success and state.players[1].resource_amount("food")==food_before+3,"Ant consumes adjacent corpse for visible Food value")
	check(not rules.try_consume_corpse(1,worker.id,corpse.id).success,"Corpse cannot be consumed twice")

	state=make_state(); rules=GameRules.new(state); worker=state.units[2]
	check(rules.queue_biological_production(1,1,"worker_ant_brood").success,"Ant Hill queues an unlocked persistent ant")
	rules.try_end_turn(1)
	check(state.units[1].spider_state.nursery_jobs[0].held,"Ant Hill stores completed brood in its production slots")

func prepare_branch(branch: String) -> Array:
	var state:=make_state(); var rules:=GameRules.new(state); var spider: GameState.Unit=state.units[1]
	spider.spider_state.nursery_branch=""; spider.spider_state.slots.clear()
	check(rules.choose_nursery(1,spider.id,branch).success,"Selects "+branch+" nursery")
	return [state,rules,spider]

func test_marsh_and_caterpillar() -> void:
	var setup:=prepare_branch("marsh"); var state: GameState=setup[0]; var rules: GameRules=setup[1]; var spider: GameState.Unit=setup[2]
	state.players[1].research.completed_ids.append("lm_marsh_metabolism")
	check(rules.queue_biological_production(1,spider.id,"marsh_larva").success,"Marsh larva enters a finite nursery slot")
	cycle_to_player_one(rules); check(not spider.spider_state.nursery_jobs[0].held,"Marsh larva visibly develops")
	cycle_to_player_one(rules); check(spider.spider_state.nursery_jobs[0].held,"Mature marsh larva may be held")
	var cell:=first_free_neighbor(state,spider.cell_id)
	check(rules.deploy_biological(1,spider.id,0,"dragonfly",cell).success,"Held larva deploys as selected unlocked form")
	var dragonfly:=state.unit_at(cell)
	check(dragonfly.remaining_lifetime_turns==state.registry.unit("dragonfly").temporary_lifetime_turns,"Marsh unit exposes finite lifetime")
	for _turn in range(dragonfly.remaining_lifetime_turns+1):
		if state.units.has(dragonfly.id): cycle_to_player_one(rules)
	check(not state.units.has(dragonfly.id),"Temporary marsh unit expires authoritatively")

	setup=prepare_branch("caterpillar_foliage"); state=setup[0]; rules=setup[1]; spider=setup[2]
	state.players[1].research.completed_ids.append("lm_metamorphosis")
	check(rules.queue_biological_production(1,spider.id,"caterpillar_brood").success,"Caterpillar brood enters foliage storage")
	cell=first_free_neighbor(state,spider.cell_id)
	check(rules.deploy_biological(1,spider.id,0,"brimstone_butterfly",cell).success,"Caterpillar deploys for field development")
	var caterpillar:=state.unit_at(cell)
	check(caterpillar.definition_id=="living_caterpillar" and caterpillar.development!=null,"Caterpillar carries reusable development state")
	check(not rules.transform_caterpillar(1,caterpillar.id,"brimstone_butterfly").success,"Transformation is gated by time and nutrients")
	cycle_to_player_one(rules)
	var fresh:=first_free_neighbor(state,caterpillar.cell_id)
	check(rules.consume(1,caterpillar.id,"vegetation",fresh).success,"Caterpillar explicitly consumes vegetation")
	check(caterpillar.development.stored_food==4 and caterpillar.development.stored_matter==0 and state.living_migration.terrain_at(fresh).kind==TerrainConsumptionState.Kind.DEPLETED,"Vegetation grants content-defined Food and depletes once")
	state.round_number=caterpillar.development.transformation_round; rules.living_migration_rules.process_round_start()
	check(rules.transform_caterpillar(1,caterpillar.id,"brimstone_butterfly").success and state.units[caterpillar.id].definition_id=="brimstone_butterfly","Complete caterpillar transforms through authoritative rules")

func test_mites_diseases_and_victory() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var mite: GameState.Unit=state.units[5]
	state.players[1].research.completed_ids=PackedStringArray(["lm_symbiotic_foundations","lm_virulence"])
	check(rules.select_disease(1,mite.id,"weakening").success and mite.moved,"Mite disease selection spends movement action")
	var target: GameState.Unit=state.units[3]; target.cell_id=state.grid.get_neighbors(mite.cell_id)[0]
	var base_damage:=state.registry.unit(target.definition_id).attack_damage
	rules.try_end_turn(1)
	check(target.active_disease!=null and target.active_disease.definition_id=="weakening","End-turn adjacency applies one eligible disease")
	var first_disease:=target.active_disease
	mite.selected_disease_id="wasting"; rules.living_migration_rules.end_turn(1)
	check(target.active_disease==first_disease,"A second disease cannot replace an active disease")
	check(target.attack_damage==maxi(0,base_damage-2),"Weakening uses centralized damage resolution")
	rules.try_end_turn(2); rules.try_end_turn(1)
	check(target.active_disease==null and target.disease_immunities.has("weakening"),"Disease expiry grants disease-specific immunity")
	check(not target.disease_immunities.has("tracking"),"Disease immunity does not cover other diseases")

	state=make_state(); rules=GameRules.new(state); mite=state.units[5]; target=state.units[3]
	state.players[1].research.completed_ids=PackedStringArray(["lm_symbiotic_foundations","lm_virulence"])
	target.cell_id=state.grid.get_neighbors(mite.cell_id)[0]; var hp:=target.hp
	rules.select_disease(1,mite.id,"wasting"); rules.try_end_turn(1)
	check(target.hp==hp-1 and target.active_disease.definition_id=="wasting","Wasting deals deterministic authoritative damage")
	target.active_disease=null; target.disease_immunities.clear(); mite.moved=false; state.active_player=1
	rules.select_disease(1,mite.id,"tracking"); rules.try_end_turn(1)
	check(target.cell_id in rules.living_migration_rules.tracking_cells(1) and rules.living_migration_rules.tracking_cells(1).size()>1,"Tracking query reveals target and one-cell neighborhood")

	state=make_state("red","living_migration"); rules=GameRules.new(state); state.active_player=1
	var spider_ids: Array[int]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==2 and unit.spider_state!=null: spider_ids.append(unit.id)
	var original: GameState.Unit=state.units[spider_ids[0]]
	var second:=GameState.Unit.new(state.allocate_id(),2,"living_spider",first_free_neighbor(state,original.cell_id),-1,state.registry); state.units[second.id]=second
	var attacker: GameState.Unit=state.units[1]; attacker.cell_id=state.grid.get_neighbors(original.cell_id)[0]; original.hp=1
	state.refresh_visibility()
	var first_kill:=rules.try_attack(1,attacker.id,original.id)
	check(first_kill.success and first_kill.winner_id==0,"Destroying one of several spiders does not defeat faction")
	attacker.attacked=false; attacker.moved=false; attacker.cell_id=state.grid.get_neighbors(second.cell_id)[0]; second.hp=1
	state.refresh_visibility()
	var last_kill:=rules.try_attack(1,attacker.id,second.id)
	check(last_kill.success and last_kill.winner_id==1,"Faction loses only when no headquarters spider survives")

func test_ai_turn() -> void:
	var state:=make_state("red","living_migration"); var rules:=GameRules.new(state); rules.try_end_turn(1)
	var ai:=SimpleAI.new(); var attempts:=0; var successful:=true
	while state.active_player==2 and state.winner_id==0 and attempts<60:
		var action:=ai.choose_action(state,rules,2); var result: GameRules.Result
		match action.get("type","end"):
			"attack": result=rules.try_attack(2,action.attacker,action.target)
			"move": result=rules.try_move(2,action.unit,action.dest)
			"lm_queue": result=rules.queue_biological_production(2,action.spider,action.recipe)
			"lm_deploy": result=rules.deploy_biological(2,action.spider,action.job,action.outcome,action.dest)
			"lm_mite": result=rules.deploy_mite(2,action.spider,action.dest)
			"lm_internal": result=rules.start_internal_construction(2,action.spider,action.building)
			"lm_road": result=rules.try_build_road(2,action.worker,action.path)
			"research": result=rules.start_research(2,action.technology)
			_: result=rules.try_end_turn(2)
		successful=successful and result.success; attempts+=1
	check(successful and state.active_player!=2 and attempts<60,"Living Migration AI uses legal commands and terminates its turn")

func _run() -> void:
	test_content_and_economy()
	test_spider_terrain_slots_and_construction()
	test_ant_hill_connection_roads_and_corpses()
	test_marsh_and_caterpillar()
	test_mites_diseases_and_victory()
	test_ai_turn()
	print("Living Migration checks: ",checks,"; failures=",failures)
	quit(1 if failures else 0)
