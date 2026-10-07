class_name BaumeisterRules
extends RefCounted
## Authoritative Baumeister infrastructure, production, support, and network rules.

var state: GameState
var research: ResearchRules

func _init(game_state: GameState,research_rules: ResearchRules) -> void:
	state=game_state; research=research_rules

func config_for(controller_id: int) -> BaumeisterConfig:
	var player:=state.player_for_controller(controller_id)
	if player==null: return null
	var faction:=state.registry.faction(player.faction_id)
	return faction.gameplay_config as BaumeisterConfig if faction!=null and faction.gameplay_config is BaumeisterConfig else null

func is_baumeister(controller_id: int) -> bool: return config_for(controller_id)!=null

func end_turn(controller_id: int) -> void:
	if not is_baumeister(controller_id): return
	for bridge: BridgeState in _owned_bridges(controller_id):
		if not bridge.completed: bridge.construction_progress=mini(bridge.required_turns,bridge.construction_progress+1)
	for district: DistrictState in _owned_districts(controller_id):
		if not district.completed: district.construction_progress=mini(district.required_turns,district.construction_progress+1)
	var research_points:=0
	for district: DistrictState in _owned_districts(controller_id):
		if district.completed and "research" in state.registry.district(district.definition_id).tags:
			research_points+=config_for(controller_id).research_per_civic_monument
	if research_points>0 and not state.players[controller_id].research.current_technology_id.is_empty():
		research.add_research_progress(controller_id,research_points)
	recalculate_supply(controller_id)

func start_turn(controller_id: int) -> void:
	if not is_baumeister(controller_id): return
	recalculate_supply(controller_id)
	if state.baumeister.last_maintenance_serial.get(controller_id,-1)==state.turn_state.serial: return
	state.baumeister.last_maintenance_serial[controller_id]=state.turn_state.serial
	var player:=state.players[controller_id]; var config:=config_for(controller_id); var unpaid:=0
	var integrity_bonus:=config.improved_integrity_bonus if research.has_unlock_tag(controller_id,"integrity_engineering") else 0
	for pillar: GameState.Structure in _owned_pillars(controller_id):
		pillar.pillar_state.maintenance_paid=true
		pillar.pillar_state.max_integrity=config.pillar_max_integrity+integrity_bonus
	for bridge: BridgeState in _owned_bridges(controller_id):
		if not bridge.operational: continue
		if player.resource_amount("materials")>=config.bridge_maintenance_materials:
			player.resources.materials=player.resource_amount("materials")-config.bridge_maintenance_materials; bridge.maintenance_paid=true
		else:
			bridge.maintenance_paid=false; unpaid+=config.bridge_maintenance_materials
			if state.structures.has(bridge.endpoint_b):
				var pillar: GameState.Structure=state.structures[bridge.endpoint_b]
				pillar.pillar_state.maintenance_paid=false
				var loss:=config.neglected_integrity_loss
				if research.has_unlock_tag(controller_id,"integrity_engineering"): loss=maxi(0,loss-config.improved_neglect_reduction)
				pillar.pillar_state.integrity=maxi(0,pillar.pillar_state.integrity-loss)
	state.baumeister.unpaid_maintenance[controller_id]=unpaid

func recalculate_supply(controller_id: int) -> Array[int]:
	var pillars:=_owned_pillars(controller_id)
	for pillar: GameState.Structure in pillars: pillar.pillar_state.supplied=false
	var origin_id: int=state.baumeister.origin_pillars.get(controller_id,-1)
	if not state.structures.has(origin_id): return []
	var supplied: Array[int]=[origin_id]; state.structures[origin_id].pillar_state.supplied=true
	var cursor:=0
	while cursor<supplied.size():
		var current:=supplied[cursor]; cursor+=1
		for bridge: BridgeState in _owned_bridges(controller_id):
			if not bridge.operational: continue
			var other:=-1
			if bridge.endpoint_a==current: other=bridge.endpoint_b
			elif bridge.endpoint_b==current: other=bridge.endpoint_a
			if other>=0 and state.structures.has(other) and other not in supplied:
				supplied.append(other); state.structures[other].pillar_state.supplied=true
	supplied.sort(); return supplied

func is_pillar_supplied(pillar_id: int) -> bool:
	return state.structures.has(pillar_id) and state.structures[pillar_id].pillar_state!=null and state.structures[pillar_id].pillar_state.supplied

func bridge_plan_error(actor: int,engineer_id: int,source_pillar_id: int,destination: int) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not is_baumeister(actor): return "This faction cannot construct pillars."
	if not state.units.has(engineer_id) or "engineer" not in state.registry.unit(state.units[engineer_id].definition_id).tags: return "Choose a Bridgewright."
	var engineer: GameState.Unit=state.units[engineer_id]
	if engineer.controller_id!=actor or engineer.moved or engineer.attacked: return "Bridgewright action is unavailable."
	if not state.structures.has(source_pillar_id): return "Choose a valid source pillar."
	var source: GameState.Structure=state.structures[source_pillar_id]
	if source.controller_id!=actor or source.pillar_state==null or not source.pillar_state.supplied: return "Expansion must originate from a supplied pillar."
	if state.grid.distance(engineer.cell_id,source.cell_id)>1: return "Bridgewright must be adjacent to the source pillar."
	if not state.grid.contains(destination) or state.is_cell_blocked(destination) or state.baumeister.district_at(destination)!=null: return "Destination is blocked or conflicts with a district."
	if state.grid.distance(source.cell_id,destination)>config_for(actor).max_bridge_distance: return "Destination is too far from the network."
	if bridge_path(source.cell_id,destination,actor).is_empty(): return "No valid bridge path."
	var cost:=bridge_cost(actor,source.cell_id,destination)
	if not state.players[actor].can_afford(cost): return "Insufficient Materials for bridge and pillar."
	return ""

func bridge_path(source_cell: int,destination: int,controller_id: int) -> Array[int]:
	if not state.grid.contains(source_cell) or not state.grid.contains(destination): return []
	var config:=config_for(controller_id); if config==null: return []
	var blocked:={}
	for cell: PlanetCell in state.grid.cells:
		if cell.id!=destination and cell.id!=source_cell and (state.structure_at(cell.id)!=null or state.site_at(cell.id)!=null or state.baumeister.district_at(cell.id)!=null): blocked[cell.id]=true
	var traversal:=state.grid.breadth_first(source_cell,config.max_bridge_distance,blocked)
	return PlanetGrid.reconstruct_path(traversal.parents,source_cell,destination)

func bridge_cost(controller_id: int,source_cell: int,destination: int) -> Dictionary[String,int]:
	var path:=bridge_path(source_cell,destination,controller_id)
	var structure:=state.registry.structure("pillar_city")
	var config:=config_for(controller_id)
	var edge_cost:=config.bridge_material_cost_per_edge
	if research.has_unlock_tag(controller_id,"efficient_bridges"): edge_cost=maxi(1,edge_cost-config.efficient_bridge_cost_reduction)
	return {"materials":structure.costs.get("materials",0)+maxi(0,path.size()-1)*edge_cost}

func candidate_pillar_cells(actor: int,engineer_id: int,source_pillar_id: int) -> Array[int]:
	var result: Array[int]=[]
	if not state.structures.has(source_pillar_id): return result
	var source: GameState.Structure=state.structures[source_pillar_id]
	for cell: PlanetCell in state.grid.cells:
		if bridge_plan_error(actor,engineer_id,source_pillar_id,cell.id).is_empty(): result.append(cell.id)
	result.sort(); return result

func start_bridge_extension(actor: int,engineer_id: int,source_pillar_id: int,destination: int) -> RuleResult:
	var error:=bridge_plan_error(actor,engineer_id,source_pillar_id,destination)
	if not error.is_empty(): return RuleResult.new(false,error)
	var source: GameState.Structure=state.structures[source_pillar_id]
	var path:=bridge_path(source.cell_id,destination,actor); state.players[actor].apply_cost(bridge_cost(actor,source.cell_id,destination))
	var config:=config_for(actor)
	var improved:=research.has_unlock_tag(actor,"bridge_improvements")
	var pillar:=GameState.Structure.new(state.allocate_id(),actor,"pillar_city",destination,-1,state.registry)
	var integrity_bonus:=config.improved_integrity_bonus if research.has_unlock_tag(actor,"integrity_engineering") else 0
	pillar.pillar_state=PillarState.new(config.pillar_max_integrity+integrity_bonus,false); state.structures[pillar.id]=pillar
	var build_turns:=maxi(1,config.bridge_construction_turns-(config.improved_bridge_build_reduction if improved else 0))
	var bridge_hp:=config.bridge_max_hp+(config.improved_bridge_hp_bonus if improved else 0)
	var bridge:=state.baumeister.add_bridge(actor,source.id,pillar.id,path,build_turns,bridge_hp)
	state.units[engineer_id].moved=true; state.units[engineer_id].attacked=true; recalculate_supply(actor)
	return RuleResult.new(true,"Pillar %d founded; bridge %d construction started." % [pillar.id,bridge.id],path)

func district_error(actor: int,pillar_id: int,cell_id: int,district_id: String) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not state.structures.has(pillar_id): return "Unknown pillar."
	var pillar: GameState.Structure=state.structures[pillar_id]
	if pillar.controller_id!=actor or pillar.pillar_state==null: return "Choose one of your pillars."
	var definition:=state.registry.district(district_id)
	if definition==null: return "Unknown district type."
	if state.grid.distance(pillar.cell_id,cell_id)!=1: return "District must occupy one of the six neighboring cells."
	if state.baumeister.district_at(cell_id)!=null: return "District cell is already assigned."
	if state.structure_at(cell_id)!=null or state.site_at(cell_id)!=null: return "District cell is blocked."
	if not definition.required_unlock_tag.is_empty() and not research.has_unlock_tag(actor,definition.required_unlock_tag): return "District is not unlocked."
	if not state.players[actor].can_afford(definition.costs): return "Insufficient resources."
	return ""

func build_district(actor: int,pillar_id: int,cell_id: int,district_id: String) -> RuleResult:
	var error:=district_error(actor,pillar_id,cell_id,district_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var definition:=state.registry.district(district_id); state.players[actor].apply_cost(definition.costs)
	state.baumeister.add_district(actor,pillar_id,cell_id,district_id,definition.construction_turns)
	return RuleResult.new(true,"%s construction started." % definition.display_name)

func district_cells(pillar_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not state.structures.has(pillar_id): return result
	for cell_id: int in state.grid.get_neighbors(state.structures[pillar_id].cell_id):
		var district:=state.baumeister.district_at(cell_id); var status:="available"
		if district!=null:
			status="completed" if district.completed else "under_construction"
			if district.pillar_id!=pillar_id: status="claimed_by_another_pillar"
		elif state.structure_at(cell_id)!=null or state.site_at(cell_id)!=null: status="blocked"
		result.append({"cell_id":cell_id,"status":status,"district_id":district.id if district!=null else -1})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.cell_id<b.cell_id); return result

func recruitment_error(actor: int,pillar_id: int,unit_id: String) -> String:
	if not is_baumeister(actor): return ""
	if not state.structures.has(pillar_id) or state.structures[pillar_id].pillar_state==null: return "Baumeister recruitment requires a pillar."
	var definition:=state.registry.unit(unit_id); if definition==null: return "Unknown unit type."
	var required_tag:="recruits_vehicle" if "vehicle" in definition.tags else "recruits_infantry"
	if not _pillar_has_district_tag(pillar_id,required_tag): return "Requires a completed %s." % ("Workshop" if required_tag=="recruits_vehicle" else "Barracks")
	if "network_recruitment" in definition.tags and not is_pillar_supplied(pillar_id): return "Advanced recruitment requires supply."
	if "hero" in definition.tags:
		var count:=0
		for unit: GameState.Unit in state.units.values():
			if unit.controller_id==actor and "hero" in state.registry.unit(unit.definition_id).tags: count+=1
		if count>=config_for(actor).hero_limit: return "Hero limit reached."
	return ""

func toggle_deployment(actor: int,unit_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(unit_id): return RuleResult.new(false,"Unknown unit.")
	var unit: GameState.Unit=state.units[unit_id]
	if unit.controller_id!=actor or "deployable_artillery" not in state.registry.unit(unit.definition_id).tags: return RuleResult.new(false,"Choose your deployable artillery.")
	if unit.moved or unit.attacked: return RuleResult.new(false,"Deployment action is unavailable.")
	unit.deployed=not unit.deployed; unit.moved=true
	return RuleResult.new(true,"Artillery is now %s." % ("DEPLOYED" if unit.deployed else "MOBILE"))

func heal_unit(actor: int,healer_id: int,target_id: int) -> RuleResult:
	return _support_unit(actor,healer_id,target_id,"healer","biological",false)

func repair_unit(actor: int,engineer_id: int,target_id: int) -> RuleResult:
	return _support_unit(actor,engineer_id,target_id,"engineer","vehicle",true)

func district_support(actor: int,district_id: int,target_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.baumeister.districts.has(district_id) or not state.units.has(target_id): return RuleResult.new(false,"Unknown district or target.")
	var district: DistrictState=state.baumeister.districts[district_id]; var target: GameState.Unit=state.units[target_id]
	if district.controller_id!=actor or target.controller_id!=actor or not district.completed or not district.maintenance_paid: return RuleResult.new(false,"District support is unavailable.")
	if district.last_action_serial==state.turn_state.serial: return RuleResult.new(false,"District support was already used this turn.")
	var definition:=state.registry.district(district.definition_id); var target_tags:=state.registry.unit(target.definition_id).tags
	if "heals_biological" in definition.tags and "biological" not in target_tags: return RuleResult.new(false,"Hospital only heals biological personnel.")
	if "repairs_vehicle" in definition.tags and "vehicle" not in target_tags: return RuleResult.new(false,"Workshop only repairs vehicles through this action.")
	if "heals_biological" not in definition.tags and "repairs_vehicle" not in definition.tags: return RuleResult.new(false,"District has no unit support action.")
	if state.grid.distance(district.cell_id,target.cell_id)>1 or target.hp>=target.max_hp: return RuleResult.new(false,"Target is out of range or at full HP.")
	var config:=config_for(actor)
	if "repairs_vehicle" in definition.tags:
		if not is_pillar_supplied(district.pillar_id): return RuleResult.new(false,"Workshop vehicle repair requires supply.")
		if not state.players[actor].can_afford({"materials":config.repair_material_cost}): return RuleResult.new(false,"Insufficient Materials.")
		state.players[actor].apply_cost({"materials":config.repair_material_cost})
	target.hp=mini(target.max_hp,target.hp+config.unit_repair_amount); district.last_action_serial=state.turn_state.serial
	return RuleResult.new(true,"%s support restored %s to %d/%d HP." % [definition.display_name,target.unit_type,target.hp,target.max_hp])

func _support_unit(actor: int,source_id: int,target_id: int,source_tag: String,target_tag: String,spend_materials: bool) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(source_id) or not state.units.has(target_id): return RuleResult.new(false,"Choose valid units.")
	var source: GameState.Unit=state.units[source_id]; var target: GameState.Unit=state.units[target_id]
	if source.controller_id!=actor or target.controller_id!=actor or source_tag not in state.registry.unit(source.definition_id).tags: return RuleResult.new(false,"Illegal support source or target.")
	if target_tag not in state.registry.unit(target.definition_id).tags: return RuleResult.new(false,"Target has the wrong support category.")
	if state.grid.distance(source.cell_id,target.cell_id)>1 or source.moved or source.attacked: return RuleResult.new(false,"Support requires an available adjacent source.")
	if target.hp>=target.max_hp: return RuleResult.new(false,"Target is already at full HP.")
	var config:=config_for(actor)
	if spend_materials and not state.players[actor].can_afford({"materials":config.repair_material_cost}): return RuleResult.new(false,"Insufficient Materials.")
	if spend_materials: state.players[actor].apply_cost({"materials":config.repair_material_cost})
	target.hp=mini(target.max_hp,target.hp+config.unit_repair_amount); source.moved=true; source.attacked=true
	return RuleResult.new(true,"%s restored to %d/%d HP." % [target.unit_type,target.hp,target.max_hp])

func repair_structure(actor: int,engineer_id: int,pillar_id: int) -> RuleResult:
	var error:=_engineer_target_error(actor,engineer_id,pillar_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var pillar: GameState.Structure=state.structures[pillar_id]; var config:=config_for(actor)
	if pillar.hp>=pillar.max_hp and pillar.pillar_state.integrity>=pillar.pillar_state.max_integrity: return RuleResult.new(false,"Pillar needs no repair.")
	if not state.players[actor].can_afford({"materials":config.repair_material_cost}): return RuleResult.new(false,"Insufficient Materials.")
	state.players[actor].apply_cost({"materials":config.repair_material_cost})
	var amount:=config.pillar_repair_amount+(config.supplied_repair_bonus if pillar.pillar_state.supplied else 0)
	if research.has_unlock_tag(actor,"repair_improvements"): amount+=config.improved_repair_bonus
	pillar.hp=mini(pillar.max_hp,pillar.hp+amount); pillar.pillar_state.integrity=mini(pillar.pillar_state.max_integrity,pillar.pillar_state.integrity+amount)
	state.units[engineer_id].moved=true; state.units[engineer_id].attacked=true
	return RuleResult.new(true,"Pillar repaired to %d HP / %d Integrity." % [pillar.hp,pillar.pillar_state.integrity])

func damage_bridge(actor: int,attacker_id: int,bridge_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(attacker_id) or not state.baumeister.bridges.has(bridge_id): return RuleResult.new(false,"Unknown attacker or bridge.")
	var attacker: GameState.Unit=state.units[attacker_id]; var bridge: BridgeState=state.baumeister.bridges[bridge_id]
	if attacker.controller_id!=actor or not state.relationships.is_hostile(actor,bridge.controller_id) or attacker.attacked: return RuleResult.new(false,"Illegal bridge attack.")
	var in_range:=false
	for cell_id: int in bridge.path:
		if state.grid.distance(attacker.cell_id,cell_id)<=attacker.attack_range: in_range=true; break
	if not in_range: return RuleResult.new(false,"Bridge is out of range.")
	bridge.hp=maxi(0,bridge.hp-attacker.attack_damage); attacker.attacked=true; attacker.moved=true; recalculate_supply(bridge.controller_id)
	return RuleResult.new(true,"Bridge %d has %d/%d HP." % [bridge.id,bridge.hp,bridge.max_hp])

func repair_bridge(actor: int,engineer_id: int,bridge_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(engineer_id) or not state.baumeister.bridges.has(bridge_id): return RuleResult.new(false,"Unknown engineer or bridge.")
	var engineer: GameState.Unit=state.units[engineer_id]; var bridge: BridgeState=state.baumeister.bridges[bridge_id]
	if engineer.controller_id!=actor or bridge.controller_id!=actor or "engineer" not in state.registry.unit(engineer.definition_id).tags or engineer.moved or engineer.attacked: return RuleResult.new(false,"Bridgewright action unavailable.")
	var in_range:=false
	for cell_id: int in bridge.path:
		if state.grid.distance(engineer.cell_id,cell_id)<=1: in_range=true; break
	if not in_range or bridge.hp>=bridge.max_hp: return RuleResult.new(false,"Bridge is out of range or undamaged.")
	var config:=config_for(actor)
	if not state.players[actor].can_afford({"materials":config.repair_material_cost}): return RuleResult.new(false,"Insufficient Materials.")
	var amount:=config.bridge_repair_amount+(config.improved_repair_bonus if research.has_unlock_tag(actor,"repair_improvements") else 0)
	state.players[actor].apply_cost({"materials":config.repair_material_cost}); bridge.hp=mini(bridge.max_hp,bridge.hp+amount)
	engineer.moved=true; engineer.attacked=true; recalculate_supply(actor)
	return RuleResult.new(true,"Bridge repaired to %d/%d HP." % [bridge.hp,bridge.max_hp])

func designate_target(actor: int,commander_id: int,target_id: int) -> RuleResult:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return RuleResult.new(false,error)
	if not state.units.has(commander_id): return RuleResult.new(false,"Unknown commander.")
	var commander: GameState.Unit=state.units[commander_id]
	if commander.controller_id!=actor or "designator" not in state.registry.unit(commander.definition_id).tags or commander.moved or commander.attacked: return RuleResult.new(false,"Designation action unavailable.")
	var target: RefCounted=state.units.get(target_id,state.structures.get(target_id))
	if target==null or not state.relationships.is_hostile(actor,target.controller_id): return RuleResult.new(false,"Choose a hostile target.")
	if not state.visibility_system.can_observe_entity(state.visibility_system.team_id_for_controller(actor),target_id): return RuleResult.new(false,"Target is not currently observed.")
	var config:=config_for(actor)
	if state.grid.distance(commander.cell_id,target.cell_id)>config.designation_range: return RuleResult.new(false,"Target is outside designation range.")
	target.designation=DesignationState.new(actor,config.designation_duration_turns,config.designation_damage_bonus)
	commander.moved=true; commander.attacked=true
	return RuleResult.new(true,"Target designated for %d turns." % config.designation_duration_turns)

func movement_edge_cost(unit: GameState.Unit,from_cell: int,to_cell: int) -> int:
	var config:=config_for(unit.controller_id)
	if config==null: return 1
	return config.bridge_edge_cost if _is_supplied_bridge_edge(unit.controller_id,from_cell,to_cell) else config.ordinary_edge_cost

func movement_budget(unit: GameState.Unit) -> int:
	var config:=config_for(unit.controller_id)
	return UnitStatResolver.movement(unit,state.registry)*(config.ordinary_edge_cost if config!=null else 1)

func economic_summary(controller_id: int) -> Dictionary:
	var production: Dictionary[String,int]={}; var upkeep: Dictionary[String,int]={}
	var unmaintained_districts:=0
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller_id:
			_add_records(production,state.registry.structure(structure.definition_id).turn_production)
			_add_records(upkeep,state.registry.structure(structure.definition_id).upkeep)
	for district: DistrictState in _owned_districts(controller_id):
		if district.completed:
			var definition:=state.registry.district(district.definition_id)
			if not district.maintenance_paid: unmaintained_districts+=1
			if district.maintenance_paid:
				_add_records(production,definition.turn_production)
				if research.has_unlock_tag(controller_id,"district_specialization") and not definition.turn_production.is_empty():
					for resource_id: String in definition.turn_production: production[resource_id]=production.get(resource_id,0)+config_for(controller_id).district_production_bonus
			_add_records(upkeep,definition.upkeep)
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id:
			if unit.upkeep_paid: _add_records(production,state.registry.unit(unit.definition_id).turn_production)
			_add_records(upkeep,state.registry.unit(unit.definition_id).upkeep)
	upkeep.materials=upkeep.get("materials",0)+_owned_bridges(controller_id).filter(func(b: BridgeState)->bool: return b.operational).size()*config_for(controller_id).bridge_maintenance_materials
	return {"production":production,"upkeep":upkeep,"unpaid_maintenance":state.baumeister.unpaid_maintenance.get(controller_id,0),
		"unmaintained_districts":unmaintained_districts}

func _engineer_target_error(actor: int,engineer_id: int,pillar_id: int) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not state.units.has(engineer_id) or not state.structures.has(pillar_id): return "Unknown engineer or pillar."
	var engineer: GameState.Unit=state.units[engineer_id]; var pillar: GameState.Structure=state.structures[pillar_id]
	if engineer.controller_id!=actor or pillar.controller_id!=actor or "engineer" not in state.registry.unit(engineer.definition_id).tags: return "Choose your Bridgewright and pillar."
	if engineer.moved or engineer.attacked or state.grid.distance(engineer.cell_id,pillar.cell_id)>1: return "Repair requires an available adjacent Bridgewright."
	return ""

func _pillar_has_district_tag(pillar_id: int,tag: String) -> bool:
	for district: DistrictState in state.baumeister.districts.values():
		if district.pillar_id==pillar_id and district.completed and tag in state.registry.district(district.definition_id).tags: return true
	return false

func _is_supplied_bridge_edge(controller_id: int,a: int,b: int) -> bool:
	for bridge: BridgeState in _owned_bridges(controller_id):
		if not bridge.operational or not is_pillar_supplied(bridge.endpoint_a) or not is_pillar_supplied(bridge.endpoint_b): continue
		for index in range(bridge.path.size()-1):
			if (bridge.path[index]==a and bridge.path[index+1]==b) or (bridge.path[index]==b and bridge.path[index+1]==a): return true
	return false

func _owned_pillars(controller_id: int) -> Array[GameState.Structure]:
	var result: Array[GameState.Structure]=[]
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller_id and structure.pillar_state!=null: result.append(structure)
	result.sort_custom(func(a: GameState.Structure,b: GameState.Structure)->bool: return a.id<b.id); return result

func _owned_bridges(controller_id: int) -> Array[BridgeState]:
	var result: Array[BridgeState]=[]
	for bridge: BridgeState in state.baumeister.bridges.values():
		if bridge.controller_id==controller_id: result.append(bridge)
	result.sort_custom(func(a: BridgeState,b: BridgeState)->bool: return a.id<b.id); return result

func _owned_districts(controller_id: int) -> Array[DistrictState]:
	var result: Array[DistrictState]=[]
	for district: DistrictState in state.baumeister.districts.values():
		if district.controller_id==controller_id: result.append(district)
	result.sort_custom(func(a: DistrictState,b: DistrictState)->bool: return a.id<b.id); return result

func _add_records(target: Dictionary[String,int],source: Dictionary) -> void:
	for id: String in source: target[id]=target.get(id,0)+int(source[id])
