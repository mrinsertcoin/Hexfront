class_name VisibilitySystem
extends RefCounted
## Single authoritative boundary between complete GameState and team knowledge.

var state: GameState
var states: Dictionary[int,VisibilityState]={}
var last_recalculation_ms: float=0.0

func _init(game_state: GameState) -> void: state=game_state

func reset() -> void: states.clear()

func team_id_for_controller(controller_id: int) -> int:
	var controller: ControllerState=state.controllers.get(controller_id)
	return controller.team_id if controller!=null else controller_id

func player_team_ids() -> Array[int]:
	var result: Array[int]=[]
	for controller_id: int in state.players:
		var team_id:=team_id_for_controller(controller_id)
		if team_id not in result: result.append(team_id)
	result.sort(); return result

func recalculate_all() -> void:
	var started:=Time.get_ticks_usec()
	for team_id: int in player_team_ids(): recalculate(team_id)
	last_recalculation_ms=(Time.get_ticks_usec()-started)/1000.0

func recalculate(team_id: int) -> VisibilityState:
	var result:=_state_for(team_id)
	var previous_visible:=result.last_visible_hostiles.duplicate(true)
	result.clear_runtime()
	var source_cells: Array[int]=[]
	for unit: GameState.Unit in _sorted_units():
		if _is_allied_controller(team_id,unit.controller_id):
			var definition:=state.registry.unit(unit.definition_id)
			_mark_range(result.visible_cells,unit.cell_id,definition.vision_range)
			_mark_range(result.detection_cells,unit.cell_id,maxi(1,definition.detection_range))
			source_cells.append(unit.cell_id)
	for structure: GameState.Structure in _sorted_structures():
		if _is_allied_controller(team_id,structure.controller_id):
			var definition:=state.registry.structure(structure.definition_id)
			_mark_range(result.visible_cells,structure.cell_id,definition.vision_range)
			_mark_range(result.detection_cells,structure.cell_id,maxi(1,definition.detection_range))
			source_cells.append(structure.cell_id)
	var forced_entities:={}
	for unit: GameState.Unit in _sorted_units():
		if unit.active_disease!=null and unit.active_disease.definition_id=="tracking" \
				and team_id_for_controller(unit.active_disease.source_controller_id)==team_id:
			_mark_range(result.visible_cells,unit.cell_id,1); forced_entities[unit.id]=true
		if int(unit.revealed_to_teams.get(team_id,-1))>=state.turn_state.serial:
			_mark_range(result.visible_cells,unit.cell_id,0); forced_entities[unit.id]=true
	for cell_id in range(result.visible_cells.size()):
		if result.visible_cells[cell_id]!=0: result.explored_cells[cell_id]=1
	var current_hostiles: Dictionary[int,Dictionary]={}
	for unit: GameState.Unit in _sorted_units():
		var allied:=_is_allied_controller(team_id,unit.controller_id)
		var definition:=state.registry.unit(unit.definition_id)
		var observable:=allied or (result.is_visible(unit.cell_id) and (not definition.concealed or result.is_detected(unit.cell_id))) or forced_entities.has(unit.id)
		if not observable: continue
		var snapshot:=_unit_snapshot(unit)
		result.visible_entities[unit.id]=snapshot
		if not allied: current_hostiles[unit.id]=snapshot
	for structure: GameState.Structure in _sorted_structures():
		var allied:=_is_allied_controller(team_id,structure.controller_id)
		if allied or result.is_visible(structure.cell_id):
			var snapshot:=_structure_snapshot(structure); result.visible_entities[structure.id]=snapshot
			if not allied: current_hostiles[structure.id]=snapshot
	for id: int in previous_visible:
		if current_hostiles.has(id): continue
		result.known_contacts[id]=KnownContact.new(previous_visible[id]); result.lost_entity_ids.append(id)
	for id: int in current_hostiles:
		if not previous_visible.has(id): result.new_entity_ids.append(id)
		result.known_contacts.erase(id)
	# A remembered location that is observed empty no longer represents a contact.
	var invalid: Array[int]=[]
	for id: int in result.known_contacts:
		var contact: KnownContact=result.known_contacts[id]
		if result.is_visible(contact.last_known_cell_id) and not current_hostiles.has(id): invalid.append(id)
	for id: int in invalid: result.known_contacts.erase(id)
	result.last_visible_hostiles=current_hostiles
	for site: WorldSiteState in _sorted_sites():
		if not result.is_visible(site.cell_id): continue
		if not result.observed_sites.has(site.id): result.new_site_ids.append(site.id)
		result.observed_sites[site.id]=_site_snapshot(site)
	result.new_entity_ids.sort(); result.lost_entity_ids.sort(); result.new_site_ids.sort()
	result.visibility_revision+=1
	return result

func observation_for_controller(controller_id: int) -> TeamObservation:
	return observation_for_team(team_id_for_controller(controller_id))

func observation_for_team(team_id: int) -> TeamObservation:
	var source:=_state_for(team_id)
	var result:=TeamObservation.new(); result.team_id=team_id; result.revision=source.visibility_revision
	result.visible_cells=source.visible_cells.duplicate(); result.explored_cells=source.explored_cells.duplicate(); result.detection_cells=source.detection_cells.duplicate()
	for id: int in source.visible_entities: result.visible_entities[id]=source.visible_entities[id].duplicate(true)
	for id: int in source.known_contacts: result.known_contacts[id]=source.known_contacts[id].snapshot()
	for id: int in source.observed_sites: result.observed_sites[id]=source.observed_sites[id].duplicate(true)
	result.newly_observed_entity_ids=source.new_entity_ids.duplicate()
	result.lost_entity_ids=source.lost_entity_ids.duplicate()
	result.newly_discovered_site_ids=source.new_site_ids.duplicate()
	return result

func is_visible(team_id: int,cell_id: int) -> bool: return _state_for(team_id).is_visible(cell_id)
func is_explored(team_id: int,cell_id: int) -> bool: return _state_for(team_id).is_explored(cell_id)
func get_visibility(team_id: int,cell_id: int) -> VisibilityState.CellVisibility: return _state_for(team_id).get_visibility(cell_id)
func can_observe_entity(team_id: int,entity_id: int) -> bool: return _state_for(team_id).visible_entities.has(entity_id)
func has_discovered_site(team_id: int,site_id: int) -> bool: return _state_for(team_id).observed_sites.has(site_id)

func _state_for(team_id: int) -> VisibilityState:
	if not states.has(team_id): states[team_id]=VisibilityState.new(team_id,state.grid.get_cell_count())
	return states[team_id]

func _is_allied_controller(team_id: int,controller_id: int) -> bool:
	return state.players.has(controller_id) and team_id_for_controller(controller_id)==team_id

func _mark_range(mask: PackedByteArray,cell_id: int,distance: int) -> void:
	for visible_cell: int in state.grid.get_cells_within_distance(cell_id,maxi(0,distance)): mask[visible_cell]=1

func _unit_snapshot(unit: GameState.Unit) -> Dictionary:
	return {"id":unit.id,"kind":"unit","definition_id":unit.definition_id,"controller_id":unit.controller_id,
		"team_id":team_id_for_controller(unit.controller_id),"cell_id":unit.cell_id,"hp":unit.hp,"max_hp":unit.max_hp,
		"moved":unit.moved,"attacked":unit.attacked,"observed_round":state.round_number,"observed_turn":state.turn_state.serial}

func _structure_snapshot(structure: GameState.Structure) -> Dictionary:
	return {"id":structure.id,"kind":"structure","definition_id":structure.definition_id,"controller_id":structure.controller_id,
		"team_id":team_id_for_controller(structure.controller_id),"cell_id":structure.cell_id,"hp":structure.hp,"max_hp":structure.max_hp,
		"observed_round":state.round_number,"observed_turn":state.turn_state.serial}

func _site_snapshot(site: WorldSiteState) -> Dictionary:
	return {"id":site.id,"definition_id":site.definition_id,"cell_id":site.cell_id,"controller_id":site.controller_id,
		"runtime_state":site.runtime_state.duplicate(true),"observed_round":state.round_number,"observed_turn":state.turn_state.serial}

func _sorted_units() -> Array[GameState.Unit]:
	var result: Array[GameState.Unit]=[]; result.assign(state.units.values())
	result.sort_custom(func(a: GameState.Unit,b: GameState.Unit)->bool: return a.id<b.id); return result
func _sorted_structures() -> Array[GameState.Structure]:
	var result: Array[GameState.Structure]=[]; result.assign(state.structures.values())
	result.sort_custom(func(a: GameState.Structure,b: GameState.Structure)->bool: return a.id<b.id); return result
func _sorted_sites() -> Array[WorldSiteState]:
	var result: Array[WorldSiteState]=[]; result.assign(state.world_sites.values())
	result.sort_custom(func(a: WorldSiteState,b: WorldSiteState)->bool: return a.id<b.id); return result
