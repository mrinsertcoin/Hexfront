class_name MovementRules
extends RefCounted

var state: GameState
var capability_rules: LivingMigrationRules
var network_rules: BaumeisterRules
func _init(game_state: GameState) -> void: state=game_state

func move_error(actor: int,unit_id: int) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not state.units.has(unit_id): return "That unit does not exist."
	var unit: GameState.Unit=state.units[unit_id]
	if unit.hp<=0: return "That unit is no longer alive."
	if unit.controller_id!=actor: return "You can only move your own units."
	if unit.attacked: return "Cannot move after attacking this turn."
	if unit.moved: return "This unit has already moved this turn."
	if unit.disconnected_turns>=2: return "This disconnected unit must retreat automatically."
	if unit.deployed and "deployable_artillery" in state.registry.unit(unit.definition_id).tags: return "Deployed artillery must become mobile before moving."
	return ""

func parents(unit: GameState.Unit) -> Dictionary[int,int]:
	var blocked:={}
	var team_id:=state.visibility_system.team_id_for_controller(unit.controller_id)
	var controller: ControllerState=state.controllers.get(unit.controller_id) as ControllerState
	var uses_player_observation:=controller==null or controller.kind!=ControllerState.NEUTRAL_AI
	# Build occupancy from entities rather than scanning every planet cell and
	# performing linear entity lookups. This keeps movement proportional to the
	# match population on Medium and Large worlds.
	var occupants: Array[RefCounted]=[]
	occupants.append_array(state.units.values()); occupants.append_array(state.structures.values())
	for occupant: RefCounted in occupants:
		if occupant.id==unit.id: continue
		var allied:=state.players.has(occupant.controller_id) and state.visibility_system.team_id_for_controller(occupant.controller_id)==team_id
		if not uses_player_observation or allied or state.visibility_system.can_observe_entity(team_id,occupant.id): blocked[occupant.cell_id]=true
	for site: WorldSiteState in state.world_sites.values():
		var definition:=state.registry.world_site(site.definition_id)
		if definition!=null and definition.blocks_movement \
				and (not uses_player_observation or state.visibility_system.has_discovered_site(team_id,site.id)): blocked[site.cell_id]=true
	var movement_tags:=state.registry.unit(unit.definition_id).tags
	# Workers physically create the network while moving; other road-bound ants
	# still require an already active Connection route.
	if capability_rules!=null and "road_bound" in movement_tags and "road_builder" not in movement_tags:
		var active:=capability_rules.active_road_cells(unit.controller_id)
		for cell: PlanetCell in state.grid.cells:
			if cell.id not in active: blocked[cell.id]=true
		blocked.erase(unit.cell_id)
	if network_rules!=null and network_rules.is_baumeister(unit.controller_id):
		return _weighted_parents(unit,blocked)
	if state.village_guard_home(unit)>=0: return _guard_parents(unit,blocked)
	var cliff_edges: Dictionary=state.terrain.blocked_edges if state.terrain!=null and "flying" not in movement_tags else {}
	return state.grid.breadth_first(unit.cell_id,UnitStatResolver.movement(unit,state.registry),blocked,cliff_edges).parents

func _guard_parents(unit: GameState.Unit,blocked: Dictionary) -> Dictionary[int,int]:
	var result: Dictionary[int,int]={unit.cell_id:unit.cell_id}
	var costs: Dictionary[int,int]={unit.cell_id:0}; var queue: Array[int]=[unit.cell_id]; var cursor:=0
	var budget:=UnitStatResolver.movement(unit,state.registry)
	while cursor<queue.size():
		var current:=queue[cursor]; cursor+=1
		if costs[current]>=budget: continue
		for neighbor: int in state.grid.get_neighbors(current):
			if result.has(neighbor) or blocked.has(neighbor) or not state.terrain_edge_allowed(unit,current,neighbor): continue
			result[neighbor]=current; costs[neighbor]=costs[current]+1; queue.append(neighbor)
	return result

func _weighted_parents(unit: GameState.Unit,blocked: Dictionary) -> Dictionary[int,int]:
	var budget:=network_rules.movement_budget(unit)
	var distances: Dictionary[int,int]={unit.cell_id:0}; var parents_result: Dictionary[int,int]={unit.cell_id:-1}
	var open: Array[int]=[unit.cell_id]
	while not open.is_empty():
		open.sort_custom(func(a: int,b: int)->bool:
			return distances[a]<distances[b] or (distances[a]==distances[b] and a<b))
		var current: int=open.pop_front(); var neighbors: Array[int]=state.grid.get_neighbors(current); neighbors.sort()
		for neighbor: int in neighbors:
			if not state.terrain_edge_allowed(unit,current,neighbor): continue
			if blocked.has(neighbor): continue
			var candidate: int=distances[current]+network_rules.movement_edge_cost(unit,current,neighbor)
			if candidate>budget: continue
			if not distances.has(neighbor) or candidate<distances[neighbor] or (candidate==distances[neighbor] and current<parents_result[neighbor]):
				distances[neighbor]=candidate; parents_result[neighbor]=current
				if neighbor not in open: open.append(neighbor)
	return parents_result

func reachable(actor: int,unit_id: int) -> Array[int]:
	var result: Array[int]=[]
	if not move_error(actor,unit_id).is_empty(): return result
	var unit: GameState.Unit=state.units[unit_id]
	for cell_id: int in parents(unit):
		if cell_id!=unit.cell_id: result.append(cell_id)
	return result

func path_to(actor: int,unit_id: int,destination: int) -> Array[int]:
	if not move_error(actor,unit_id).is_empty(): return []
	var unit: GameState.Unit=state.units[unit_id]
	if destination==unit.cell_id or not state.grid.contains(destination): return []
	return PlanetGrid.reconstruct_path(parents(unit),unit.cell_id,destination)

func try_move(actor: int,unit_id: int,destination: int) -> RuleResult:
	var error:=move_error(actor,unit_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var unit: GameState.Unit=state.units[unit_id]
	if not state.grid.contains(destination): return RuleResult.new(false,"Choose a tile on the board.")
	if destination==unit.cell_id: return RuleResult.new(false,"The unit is already on that tile.")
	var path:=path_to(actor,unit_id,destination)
	if path.is_empty(): return RuleResult.new(false,"No open path within this unit's movement allowance.")
	for index in range(1,path.size()):
		if not state.terrain_edge_allowed(unit,path[index-1],path[index]): return RuleResult.new(false,"A cliff blocks this ground route.")
		if state.is_cell_blocked(path[index],unit.id):
			return RuleResult.new(false,"Movement is blocked by an obstruction discovered along the route.")
	unit.cell_id=destination; unit.moved=true
	return RuleResult.new(true,"Moved %d step(s). Movement action spent." % (path.size()-1),path)
