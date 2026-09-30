class_name LivingMigrationRules
extends RefCounted
## Authoritative Living Migration commands and deterministic turn processing.

const BRANCHES: Array[String]=["ant_hill","marsh","caterpillar_foliage"]
const INTERNAL_BUILDINGS: Array[String]=["research_building","clearing_upgrade","food_production","synapse_production"]

var state: GameState
var research: ResearchRules

func _init(game_state: GameState,research_rules: ResearchRules) -> void:
	state=game_state; research=research_rules

func config_for(controller_id: int) -> LivingMigrationConfig:
	var player:=state.player_for_controller(controller_id)
	if player==null: return null
	var faction:=state.registry.faction(player.faction_id)
	return faction.gameplay_config as LivingMigrationConfig if faction!=null and faction.gameplay_config is LivingMigrationConfig else null

func is_living_migration(controller_id: int) -> bool: return config_for(controller_id)!=null

func after_move(unit_id: int) -> String:
	if not state.units.has(unit_id): return ""
	var unit: GameState.Unit=state.units[unit_id]
	var definition:=state.registry.unit(unit.definition_id)
	if "terrain_harvester" not in definition.tags: return ""
	var terrain:=state.living_migration.terrain_at(unit.cell_id)
	if terrain.kind!=TerrainConsumptionState.Kind.FRESH: return " Terrain already depleted."
	var config:=config_for(unit.controller_id)
	if config==null: return ""
	terrain.deplete(config.terrain_regrowth_turns)
	if unit.development!=null:
		unit.development.add_nutrients(config.caterpillar_nutrients_per_harvest)
		return " Gathered %d nutrients; terrain depleted." % config.caterpillar_nutrients_per_harvest
	state.players[unit.controller_id].add_resources({"food":config.terrain_food_yield})
	return " Harvested %d Food; terrain depleted." % config.terrain_food_yield

func end_turn(controller_id: int) -> void:
	if not is_living_migration(controller_id): return
	var config:=config_for(controller_id)
	for unit: GameState.Unit in _owned_units(controller_id):
		if unit.spider_state!=null: _advance_spider(unit,config)
		if unit.development!=null: unit.development.advance()
	_expose_diseases(controller_id)
	_update_disconnection(controller_id)
	var research_buildings:=0
	for unit: GameState.Unit in _owned_units(controller_id):
		if unit.spider_state!=null: research_buildings+=unit.spider_state.building_count("research_building")
	if research_buildings>0 and not state.players[controller_id].research.current_technology_id.is_empty():
		research.add_research_progress(controller_id,research_buildings*config.research_per_building)

func start_turn(controller_id: int) -> void:
	if not is_living_migration(controller_id): return
	for unit: GameState.Unit in _owned_units(controller_id):
		if "ant" not in state.registry.unit(unit.definition_id).tags: continue
		if is_ant_connected(unit): unit.disconnected_turns=0
		elif unit.disconnected_turns>=config_for(controller_id).disconnection_limit:
			_retreat(unit)

func _advance_spider(unit: GameState.Unit,config: LivingMigrationConfig) -> void:
	var spider:=unit.spider_state
	if unit.moved: return
	if spider.construction!=null:
		spider.construction.advance()
		if spider.construction.is_complete() and spider.construction.recipe_id.begins_with("internal:"):
			spider.slots.append(spider.construction.recipe_id.trim_prefix("internal:"))
			spider.construction=null
	for job: BiologicalProductionState in spider.nursery_jobs:
		if not job.held: job.advance()
	var interval:=config.improved_mite_interval if research.has_unlock_tag(unit.controller_id,"improved_mite_interval") else config.mite_production_interval
	spider.mite_progress+=1
	if spider.mite_progress>=interval:
		spider.mite_progress=0; spider.held_mites+=1

func choose_nursery(controller_id: int,spider_id: int,branch_id: String) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if branch_id not in BRANCHES: return RuleResult.new(false,"Unknown nursery branch.")
	var spider:=state.units[spider_id].spider_state
	if not spider.nursery_branch.is_empty(): return RuleResult.new(false,"This spider already has a nursery branch.")
	if not spider.has_slot(): return RuleResult.new(false,"All nine internal slots are occupied.")
	spider.nursery_branch=branch_id; spider.slots.append(branch_id)
	return RuleResult.new(true,"Nursery selected: "+branch_id.replace("_"," ").capitalize())

func start_internal_construction(controller_id: int,spider_id: int,building_id: String) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if building_id not in INTERNAL_BUILDINGS: return RuleResult.new(false,"Unknown internal building.")
	var unit: GameState.Unit=state.units[spider_id]; var spider:=unit.spider_state
	if unit.moved: return RuleResult.new(false,"Construction cannot start after the spider moved.")
	if not spider.has_slot(): return RuleResult.new(false,"All nine internal slots are occupied.")
	if spider.construction!=null: return RuleResult.new(false,"Construction is already in progress.")
	var config:=config_for(controller_id); var cost: Dictionary[String,int]={"food":config.internal_building_food_cost}
	if not state.players[controller_id].can_afford(cost): return RuleResult.new(false,"Insufficient Food.")
	state.players[controller_id].apply_cost(cost)
	spider.construction=BiologicalProductionState.new("internal:"+building_id,config.internal_construction_turns)
	return RuleResult.new(true,"Internal construction started.")

func queue_biological_production(controller_id: int,spider_id: int,recipe_id: String) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var unit: GameState.Unit=state.units[spider_id]; var spider:=unit.spider_state
	if unit.moved: return RuleResult.new(false,"Biological production cannot start after the spider moved.")
	var recipe:=state.registry.biological_recipe(recipe_id)
	if recipe==null or recipe.branch_id!=spider.nursery_branch: return RuleResult.new(false,"Recipe does not belong to this nursery.")
	if spider.nursery_jobs.size()>=config_for(controller_id).nursery_slot_count: return RuleResult.new(false,"Nursery storage is full.")
	var any_unlocked:=false
	for outcome_id: String in recipe.outcome_unit_ids:
		if research.is_unit_unlocked(controller_id,outcome_id): any_unlocked=true
	if not any_unlocked: return RuleResult.new(false,"No recipe outcome is unlocked.")
	if not state.players[controller_id].can_afford(recipe.costs): return RuleResult.new(false,"Insufficient faction resources.")
	state.players[controller_id].apply_cost(recipe.costs)
	var job:=BiologicalProductionState.new(recipe.id,recipe.development_turns,recipe.nutrient_requirement,recipe.outcome_unit_ids)
	if recipe.branch_id=="caterpillar_foliage": job.held=true
	spider.nursery_jobs.append(job)
	return RuleResult.new(true,recipe.display_name+" started.")

func deployment_cells(controller_id: int,spider_id: int,unit_id: String) -> Array[int]:
	var result: Array[int]=[]
	if not _spider_error(controller_id,spider_id).is_empty(): return result
	var definition:=state.registry.unit(unit_id)
	if definition==null: return result
	for cell_id: int in state.grid.get_neighbors(state.units[spider_id].cell_id):
		if state.is_cell_blocked(cell_id): continue
		if "road_bound" in definition.tags and cell_id not in active_road_cells(controller_id): continue
		result.append(cell_id)
	result.sort(); return result

func deploy_biological(controller_id: int,spider_id: int,job_index: int,outcome_id: String,cell_id: int) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var spider:=state.units[spider_id].spider_state
	if job_index<0 or job_index>=spider.nursery_jobs.size(): return RuleResult.new(false,"Unknown nursery production.")
	var job: BiologicalProductionState=spider.nursery_jobs[job_index]
	if not job.held: return RuleResult.new(false,"Production is not mature.")
	var deployed_id:=outcome_id
	if job.recipe_id=="caterpillar_brood": deployed_id="living_caterpillar"
	if outcome_id not in job.outcome_unit_ids or not research.is_unit_unlocked(controller_id,outcome_id): return RuleResult.new(false,"Outcome is not unlocked.")
	if cell_id not in deployment_cells(controller_id,spider_id,deployed_id): return RuleResult.new(false,"Choose a legal adjacent deployment cell.")
	var unit:=_spawn_unit(controller_id,deployed_id,cell_id)
	if job.recipe_id=="caterpillar_brood":
		unit.development=BiologicalProductionState.new(job.recipe_id,job.required_turns,job.required_nutrients,job.outcome_unit_ids)
	spider.nursery_jobs.remove_at(job_index)
	return RuleResult.new(true,state.registry.unit(deployed_id).display_name+" deployed.")

func transform_caterpillar(controller_id: int,unit_id: int,outcome_id: String) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,controller_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(unit_id): return RuleResult.new(false,"Unknown caterpillar.")
	var old: GameState.Unit=state.units[unit_id]
	if old.controller_id!=controller_id or old.development==null or not old.development.is_complete(): return RuleResult.new(false,"Transformation requirements are not complete.")
	if outcome_id not in old.development.outcome_unit_ids or not research.is_unit_unlocked(controller_id,outcome_id): return RuleResult.new(false,"Transformation is not unlocked.")
	var replacement:=GameState.Unit.new(old.id,controller_id,outcome_id,old.cell_id,-1,state.registry)
	replacement.moved=true; replacement.attacked=true; replacement.ready_next_turn=true
	state.units[unit_id]=replacement
	return RuleResult.new(true,"Caterpillar transformed into "+state.registry.unit(outcome_id).display_name+".")

func spider_cost(controller_id: int) -> Dictionary[String,int]:
	var count:=0
	for unit: GameState.Unit in _owned_units(controller_id):
		if unit.spider_state!=null: count+=1
	var config:=config_for(controller_id)
	return {"silk":config.spider_base_silk_cost+config.spider_silk_cost_per_owned*count}

func start_spider_construction(controller_id: int,spider_id: int) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var unit: GameState.Unit=state.units[spider_id]; var spider:=unit.spider_state
	if unit.moved: return RuleResult.new(false,"Spider construction cannot start after moving.")
	if spider.construction!=null: return RuleResult.new(false,"Construction is already in progress.")
	var cost:=spider_cost(controller_id)
	if not state.players[controller_id].can_afford(cost): return RuleResult.new(false,"Insufficient Silk.")
	state.players[controller_id].apply_cost(cost)
	spider.construction=BiologicalProductionState.new("spider_construction",config_for(controller_id).spider_construction_turns,0,PackedStringArray(["living_spider"]))
	return RuleResult.new(true,"Spider construction started.")

func deploy_spider(controller_id: int,spider_id: int,cell_id: int) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var spider:=state.units[spider_id].spider_state
	if spider.construction==null or spider.construction.recipe_id!="spider_construction" or not spider.construction.is_complete(): return RuleResult.new(false,"New spider is not ready.")
	if cell_id not in deployment_cells(controller_id,spider_id,"living_spider"): return RuleResult.new(false,"Choose a legal adjacent deployment cell.")
	var unit:=_spawn_unit(controller_id,"living_spider",cell_id)
	unit.spider_state.slot_limit=config_for(controller_id).internal_slot_count
	state.living_migration.add_road(controller_id,cell_id)
	spider.construction=null
	return RuleResult.new(true,"New spider deployed.")

func deploy_mite(controller_id: int,spider_id: int,cell_id: int) -> RuleResult:
	var error:=_spider_error(controller_id,spider_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var spider:=state.units[spider_id].spider_state
	if spider.held_mites<=0: return RuleResult.new(false,"No mature mite is held.")
	if cell_id not in deployment_cells(controller_id,spider_id,"mite"): return RuleResult.new(false,"Choose a legal adjacent deployment cell.")
	_spawn_unit(controller_id,"mite",cell_id); spider.held_mites-=1
	return RuleResult.new(true,"Mite deployed.")

func valid_road_extensions(controller_id: int,worker_id: int) -> Array[int]:
	var result: Array[int]=[]
	if not state.units.has(worker_id): return result
	var worker: GameState.Unit=state.units[worker_id]
	if worker.controller_id!=controller_id or "road_builder" not in state.registry.unit(worker.definition_id).tags or not is_ant_connected(worker): return result
	var roads: Dictionary=state.living_migration.roads.get(controller_id,{})
	if worker.cell_id not in active_road_cells(controller_id): return result
	for cell_id: int in state.grid.get_neighbors(worker.cell_id):
		if not roads.has(cell_id) and not state.is_cell_blocked(cell_id): result.append(cell_id)
	result.sort(); return result

func try_build_road(controller_id: int,worker_id: int,path: Array[int]) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,controller_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(worker_id): return RuleResult.new(false,"Unknown worker.")
	var worker: GameState.Unit=state.units[worker_id]; var config:=config_for(controller_id)
	if worker.controller_id!=controller_id or "road_builder" not in state.registry.unit(worker.definition_id).tags: return RuleResult.new(false,"Choose a worker ant.")
	if not is_ant_connected(worker): return RuleResult.new(false,"Worker must begin from a Connection source.")
	if path.is_empty() or path.size()+worker.road_segments_built_this_turn>config.road_segments_per_turn: return RuleResult.new(false,"Workers may extend at most three road cells per turn.")
	var roads: Dictionary=state.living_migration.roads.get(controller_id,{})
	var previous:=worker.cell_id
	for cell_id: int in path:
		if not state.grid.are_neighbors(previous,cell_id) or roads.has(cell_id) or state.is_cell_blocked(cell_id): return RuleResult.new(false,"Road path must be contiguous and unoccupied.")
		if previous==worker.cell_id and previous not in active_road_cells(controller_id): return RuleResult.new(false,"Road must start from an active connection.")
		previous=cell_id
	var cost: Dictionary[String,int]={"food":config.road_food_cost_per_cell*path.size()}
	if not state.players[controller_id].can_afford(cost): return RuleResult.new(false,"Insufficient Food for road construction.")
	state.players[controller_id].apply_cost(cost)
	for cell_id: int in path: state.living_migration.add_road(controller_id,cell_id)
	worker.road_segments_built_this_turn+=path.size()
	return RuleResult.new(true,"Built %d ant-road cell(s)." % path.size())

func active_road_cells(controller_id: int) -> Array[int]:
	var roads: Dictionary=state.living_migration.roads.get(controller_id,{})
	var active:={}; var queue: Array[int]=[]
	var config:=config_for(controller_id)
	for source: Dictionary in _connection_sources(controller_id):
		var range_limit:=config.queen_connection_range if source.kind=="queen" else config.ant_hill_connection_range
		for road_cell: int in roads:
			if state.grid.distance(source.cell_id,road_cell)<=range_limit and not active.has(road_cell):
				active[road_cell]=true; queue.append(road_cell)
	var cursor:=0
	while cursor<queue.size():
		var current:=queue[cursor]; cursor+=1
		for neighbor: int in state.grid.get_neighbors(current):
			if roads.has(neighbor) and not active.has(neighbor): active[neighbor]=true; queue.append(neighbor)
	var result: Array[int]=[]
	for cell_id: int in active: result.append(cell_id)
	result.sort(); return result

func is_ant_connected(unit: GameState.Unit) -> bool:
	var definition:=state.registry.unit(unit.definition_id)
	if "connection_independent" in definition.tags: return true
	if "ant" not in definition.tags: return true
	var config:=config_for(unit.controller_id)
	for source: Dictionary in _connection_sources(unit.controller_id):
		var range_limit:=config.queen_connection_range if source.kind=="queen" else config.ant_hill_connection_range
		if state.grid.distance(unit.cell_id,source.cell_id)<=range_limit: return true
	return unit.cell_id in active_road_cells(unit.controller_id)

func try_consume_corpse(controller_id: int,ant_id: int,corpse_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,controller_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(ant_id) or not state.living_migration.corpses.has(corpse_id): return RuleResult.new(false,"Unknown ant or corpse.")
	var ant: GameState.Unit=state.units[ant_id]; var corpse: CorpseState=state.living_migration.corpses[corpse_id]
	if ant.controller_id!=controller_id or "ant" not in state.registry.unit(ant.definition_id).tags: return RuleResult.new(false,"Only ants can consume corpses.")
	if corpse.consumed: return RuleResult.new(false,"Corpse was already consumed.")
	if state.grid.distance(ant.cell_id,corpse.cell_id)>1: return RuleResult.new(false,"Corpse is out of range.")
	corpse.consumed=true; state.players[controller_id].add_resources({"food":corpse.food_value})
	return RuleResult.new(true,"Corpse consumed for %d Food." % corpse.food_value)

func available_diseases(controller_id: int) -> PackedStringArray:
	var result:=PackedStringArray()
	for id: String in ContentRegistry._sorted_keys(state.registry.diseases):
		var disease:=state.registry.disease(id)
		if disease.unlock_tag.is_empty() or research.has_unlock_tag(controller_id,disease.unlock_tag): result.append(id)
	return result

func select_disease(controller_id: int,mite_id: int,disease_id: String) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,controller_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(mite_id): return RuleResult.new(false,"Unknown mite.")
	var mite: GameState.Unit=state.units[mite_id]
	if mite.controller_id!=controller_id or "disease_carrier" not in state.registry.unit(mite.definition_id).tags: return RuleResult.new(false,"Choose a mite.")
	if mite.moved: return RuleResult.new(false,"Changing disease replaces movement for this turn.")
	if disease_id not in available_diseases(controller_id): return RuleResult.new(false,"Disease is not unlocked.")
	mite.selected_disease_id=disease_id; mite.moved=true
	return RuleResult.new(true,"Selected "+state.registry.disease(disease_id).display_name+".")

func tracking_cells(controller_id: int) -> Array[int]:
	var visible:={}
	for unit: GameState.Unit in state.units.values():
		if unit.active_disease!=null and unit.active_disease.definition_id=="tracking" and unit.active_disease.source_controller_id==controller_id:
			visible[unit.cell_id]=true
			for neighbor: int in state.grid.get_neighbors(unit.cell_id): visible[neighbor]=true
	var result: Array[int]=[]
	for cell_id: int in visible: result.append(cell_id)
	result.sort(); return result

func economic_summary(controller_id: int) -> Dictionary:
	var production: Dictionary[String,int]={}; var upkeep: Dictionary[String,int]={}
	for unit: GameState.Unit in _owned_units(controller_id):
		var definition:=state.registry.unit(unit.definition_id)
		for id: String in definition.turn_production: production[id]=production.get(id,0)+definition.turn_production[id]
		for id: String in definition.upkeep: upkeep[id]=upkeep.get(id,0)+definition.upkeep[id]
		if unit.spider_state!=null:
			var config:=config_for(controller_id)
			production.food=production.get("food",0)+config.spider_food_production
			production.silk=production.get("silk",0)+config.spider_silk_production
			production.food=production.get("food",0)+unit.spider_state.building_count("food_production")*config.food_per_food_building
			production.synapse=production.get("synapse",0)+unit.spider_state.building_count("synapse_production")*config.synapse_per_synapse_building
	return {"production":production,"upkeep":upkeep,"unpaid":state.living_migration.unpaid_upkeep.get(controller_id,{})}

func _expose_diseases(controller_id: int) -> void:
	for mite: GameState.Unit in _owned_units(controller_id):
		if "disease_carrier" not in state.registry.unit(mite.definition_id).tags: continue
		var disease:=state.registry.disease(mite.selected_disease_id)
		if disease==null or disease.id not in available_diseases(controller_id): continue
		for target: GameState.Unit in state.units.values():
			if not state.relationships.is_hostile(controller_id,target.controller_id): continue
			if state.grid.distance(mite.cell_id,target.cell_id)>1: continue
			if "disease_susceptible" not in state.registry.unit(target.definition_id).tags: continue
			if target.active_disease!=null or target.disease_immunities.has(disease.id): continue
			target.active_disease=DiseaseState.new(disease.id,disease.duration_turns,controller_id,disease.damage_per_turn,disease.attack_damage_reduction)

func _update_disconnection(controller_id: int) -> void:
	for unit: GameState.Unit in _owned_units(controller_id):
		if "ant" not in state.registry.unit(unit.definition_id).tags: continue
		unit.disconnected_turns=0 if is_ant_connected(unit) else unit.disconnected_turns+1

func _retreat(unit: GameState.Unit) -> void:
	var targets:=active_road_cells(unit.controller_id)
	for source: int in _connection_source_cells(unit.controller_id):
		if source not in targets: targets.append(source)
	if targets.is_empty(): return
	var blocked:={}
	var road_bound:="road_bound" in state.registry.unit(unit.definition_id).tags
	var active_roads:=active_road_cells(unit.controller_id)
	for cell: PlanetCell in state.grid.cells:
		if state.is_cell_blocked(cell.id,unit.id) or (road_bound and cell.id!=unit.cell_id and cell.id not in active_roads): blocked[cell.id]=true
	var traversal:=state.grid.breadth_first(unit.cell_id,unit.movement,blocked)
	var best:=unit.cell_id; var best_distance:=_distance_to_any(unit.cell_id,targets)
	for cell_id: int in traversal.order:
		var distance:=_distance_to_any(cell_id,targets)
		if distance<best_distance or (distance==best_distance and cell_id<best): best=cell_id; best_distance=distance
	if best!=unit.cell_id:
		unit.cell_id=best; unit.moved=true

func _distance_to_any(cell_id: int,targets: Array[int]) -> int:
	var result:=2147483647
	for target: int in targets: result=mini(result,state.grid.distance(cell_id,target))
	return result

func _connection_sources(controller_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for unit: GameState.Unit in _owned_units(controller_id):
		var tags:=state.registry.unit(unit.definition_id).tags
		if "queen_connection_source" in tags: result.append({"cell_id":unit.cell_id,"kind":"queen"})
		elif unit.spider_state!=null and unit.spider_state.nursery_branch=="ant_hill": result.append({"cell_id":unit.cell_id,"kind":"hill"})
	return result

func _connection_source_cells(controller_id: int) -> Array[int]:
	var result: Array[int]=[]
	for source: Dictionary in _connection_sources(controller_id):
		if source.cell_id not in result: result.append(source.cell_id)
	result.sort(); return result

func _owned_units(controller_id: int) -> Array[GameState.Unit]:
	var result: Array[GameState.Unit]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id: result.append(unit)
	result.sort_custom(func(a: GameState.Unit,b: GameState.Unit)->bool: return a.id<b.id)
	return result

func _spider_error(controller_id: int,spider_id: int) -> String:
	var error:=RuleAuthority.actor_error(state,controller_id)
	if not error.is_empty(): return error
	if not state.units.has(spider_id): return "Unknown spider."
	var unit: GameState.Unit=state.units[spider_id]
	if unit.controller_id!=controller_id or unit.spider_state==null: return "Choose one of your spider headquarters."
	return ""

func _spawn_unit(controller_id: int,definition_id: String,cell_id: int) -> GameState.Unit:
	var unit:=GameState.Unit.new(state.allocate_id(),controller_id,definition_id,cell_id,-1,state.registry)
	unit.moved=true; unit.attacked=true; unit.ready_next_turn=true
	state.units[unit.id]=unit; return unit
