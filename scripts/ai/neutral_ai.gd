class_name NeutralAI
extends RefCounted
## Deterministic bounded behavior for wildlife and site guardians.

var _leash_cells: Dictionary = {}

func choose_actions(state: GameState,controller_id: int) -> Array[Dictionary]:
	var actions: Array[Dictionary]=[]
	if not state.turn_state.neutral_phase or not state.controllers.has(controller_id): return actions
	_leash_cells.clear()
	var rules:=GameRules.new(state)
	var ids: Array[int]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id: ids.append(unit.id)
	ids.sort()
	for unit_id: int in ids:
		if not state.units.has(unit_id): continue
		var unit: GameState.Unit=state.units[unit_id]
		var target:=_nearest_hostile(state,unit)
		if target!=null:
			if rules.preview_attack(controller_id,unit.id,target.id).success:
				actions.append({"type":"attack","attacker":unit.id,"target":target.id}); continue
			var destination:=_approach_cell(state,rules,unit,target.cell_id)
			if destination>=0: actions.append({"type":"move","unit":unit.id,"dest":destination})
		else:
			var destination:=_wander_cell(state,rules,unit)
			if destination>=0: actions.append({"type":"move","unit":unit.id,"dest":destination})
	return actions

func execute_actions(state: GameState,controller_id: int) -> Array[RuleResult]:
	var rules:=GameRules.new(state)
	var results: Array[RuleResult]=[]
	var actions:=choose_actions(state,controller_id)
	var budget:=mini(actions.size(),_unit_count(state,controller_id)*2+4)
	for index in range(budget):
		var action:=actions[index]
		# Neutral controllers resolve as one authoritative phase. Domain rules still
		# validate every command; visibility is refreshed once after the batch.
		if action.type=="attack": results.append(rules.combat_rules.try_attack(controller_id,action.attacker,action.target))
		elif action.type=="move": results.append(rules.movement_rules.try_move(controller_id,action.unit,action.dest))
	state.refresh_visibility()
	return results

func _nearest_hostile(state: GameState,unit: GameState.Unit) -> RefCounted:
	# Neutral awareness is deliberately local. A bounded traversal avoids filling
	# the planet-wide distance cache once per wildlife unit on large worlds.
	var traversal:=state.grid.breadth_first(unit.cell_id,unit.neutral_awareness_range)
	var candidates: Array[RefCounted]=[]
	for other: GameState.Unit in state.units.values():
		if state.relationships.is_hostile(unit.controller_id,other.controller_id) and traversal.costs.has(other.cell_id): candidates.append(other)
	for structure: GameState.Structure in state.structures.values():
		if state.relationships.is_hostile(unit.controller_id,structure.controller_id) and traversal.costs.has(structure.cell_id): candidates.append(structure)
	candidates.sort_custom(func(a: RefCounted,b: RefCounted)->bool:
		var da: int=traversal.costs[a.cell_id]; var db: int=traversal.costs[b.cell_id]
		return da<db or (da==db and a.id<b.id))
	for candidate: RefCounted in candidates:
		if _inside_leash(state,unit,candidate.cell_id): return candidate
	return null

func _approach_cell(state: GameState,rules: GameRules,unit: GameState.Unit,target_cell: int) -> int:
	# Use the target as the cached BFS origin while comparing many candidate
	# cells. Reversing these arguments would generate one traversal per cell.
	var best:=-1; var best_distance:=state.grid.distance(target_cell,unit.cell_id)
	var reachable:=rules.reachable(unit.controller_id,unit.id); reachable.sort()
	for cell_id: int in reachable:
		if not _inside_leash(state,unit,cell_id): continue
		var distance:=state.grid.distance(target_cell,cell_id)
		if distance<best_distance: best_distance=distance; best=cell_id
	return best

func _wander_cell(state: GameState,rules: GameRules,unit: GameState.Unit) -> int:
	var reachable:=rules.reachable(unit.controller_id,unit.id)
	var allowed: Array[int]=[]
	for cell_id: int in reachable:
		if _inside_leash(state,unit,cell_id): allowed.append(cell_id)
	allowed.sort()
	if allowed.is_empty(): return -1
	return allowed[(unit.id+state.round_number)%allowed.size()]

func _inside_leash(state: GameState,unit: GameState.Unit,cell_id: int) -> bool:
	if unit.neutral_home_cell<0: return true
	var key:=Vector2i(unit.neutral_home_cell,unit.neutral_leash_distance)
	if not _leash_cells.has(key):
		var allowed: Dictionary={}
		for allowed_cell: int in state.grid.get_cells_within_distance(key.x,key.y): allowed[allowed_cell]=true
		_leash_cells[key]=allowed
	return (_leash_cells[key] as Dictionary).has(cell_id)

func _unit_count(state: GameState,controller_id: int) -> int:
	var result:=0
	for unit: GameState.Unit in state.units.values(): result+=int(unit.controller_id==controller_id)
	return result
