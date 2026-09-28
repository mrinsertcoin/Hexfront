class_name GameRules
extends RefCounted

class Result extends RefCounted:
	var success: bool
	var reason: String
	var path: Array[int] = []
	var damage: int = 0
	var target_hp: int = 0
	var killed: bool = false
	var winner_id: int = 0

	func _init(accepted: bool, message: String, route: Array[int] = []) -> void:
		success = accepted
		reason = message
		path = route

var state: GameState

func _init(game_state: GameState) -> void:
	state = game_state

func _actor_error(actor: int) -> String:
	if state.winner_id != 0:
		return "Match over. Player %d wins. Restart to play again." % state.winner_id
	if actor != 1 and actor != 2:
		return "Unknown player."
	if actor != state.active_player:
		return "It is Player %d's turn." % state.active_player
	return ""

func _move_error(actor: int, unit_id: int) -> String:
	var actor_error: String = _actor_error(actor)
	if not actor_error.is_empty():
		return actor_error
	if not state.units.has(unit_id):
		return "That unit does not exist."
	var unit: GameState.Unit = state.units[unit_id]
	if unit.hp <= 0:
		return "That unit is no longer alive."
	if unit.owner_id != actor:
		return "You can only move your own units."
	if unit.attacked:
		return "Cannot move after attacking this turn."
	if unit.moved:
		return "This unit has already moved this turn."
	return ""

# The same bounded BFS powers highlights, previews, and command validation.
# A parent is assigned only on first discovery; sorted neighbor IDs break ties.
func _parents(unit: GameState.Unit) -> Dictionary[int, int]:
	var blocked: Dictionary = {}
	for other: GameState.Unit in state.units.values():
		blocked[other.cell_id] = true
	for structure: GameState.Structure in state.structures.values():
		blocked[structure.cell_id] = true
	return state.grid.breadth_first(unit.cell_id, unit.movement, blocked).parents

func reachable(actor: int, unit_id: int) -> Array[int]:
	var destinations: Array[int] = []
	if not _move_error(actor, unit_id).is_empty():
		return destinations
	var unit: GameState.Unit = state.units[unit_id]
	var parents: Dictionary[int, int] = _parents(unit)
	for cell_id: int in parents:
		if cell_id != unit.cell_id:
			destinations.append(cell_id)
	return destinations

func path_to(actor: int, unit_id: int, destination: int) -> Array[int]:
	if not _move_error(actor, unit_id).is_empty():
		return []
	var unit: GameState.Unit = state.units[unit_id]
	if destination == unit.cell_id or not state.grid.contains(destination):
		return []
	return PlanetGrid.reconstruct_path(_parents(unit), unit.cell_id, destination)

func try_move(actor: int, unit_id: int, destination: int) -> Result:
	var error: String = _move_error(actor, unit_id)
	if not error.is_empty():
		return Result.new(false, error)
	var unit: GameState.Unit = state.units[unit_id]
	if not state.grid.contains(destination):
		return Result.new(false, "Choose a tile on the board.")
	if destination == unit.cell_id:
		return Result.new(false, "The unit is already on that tile.")
	if state.entity_at(destination) != null:
		return Result.new(false, "That tile is occupied.")
	var path: Array[int] = path_to(actor, unit_id, destination)
	if path.is_empty():
		return Result.new(false, "No open path within this unit's movement allowance.")
	# All rejection paths above are read-only. Apply only after validation.
	unit.cell_id = destination
	unit.moved = true
	return Result.new(true, "Moved %d step(s). Movement action spent." % (path.size() - 1), path)

func try_end_turn(actor: int) -> Result:
	var error: String = _actor_error(actor)
	if not error.is_empty():
		return Result.new(false, error)
	if state.active_player == 1:
		state.active_player = 2
	else:
		state.active_player = 1
		state.round_number += 1
	# Run authoritative per-turn start effects for the incoming player
	_start_turn()
	return Result.new(true, "Player %d's turn." % state.active_player)

func _start_turn() -> void:
	state.start_turn()

func _attack_error(actor: int, attacker_id: int, target_id: int) -> String:
	var error: String = _actor_error(actor)
	if not error.is_empty():
		return error
	# Attacker must be a living military unit
	if not state.units.has(attacker_id) or state.units[attacker_id].hp <= 0:
		return "The attacker does not exist or is no longer alive."
	# Target may be a unit or a structure
	var target_is_unit: bool = state.units.has(target_id)
	var target_is_struct: bool = state.structures.has(target_id)
	if not target_is_unit and not target_is_struct:
		return "The target does not exist or is no longer alive."
	# Reject dead unit targets (hp <= 0)
	if target_is_unit and state.units[target_id].hp <= 0:
		return "The target does not exist or is no longer alive."
	# Reject destroyed structures (hp <= 0)
	if target_is_struct and state.structures[target_id].hp <= 0:
		return "The target does not exist or is no longer alive."
	var attacker: GameState.Unit = state.units[attacker_id]
	var target_unit: GameState.Unit = state.units[target_id] if target_is_unit else null
	var target_struct: GameState.Structure = state.structures[target_id] if target_is_struct else null
	if attacker.owner_id != actor:
		return "You can only attack with your own units."
	if attacker_id == target_id:
		return "A unit cannot attack itself."
	# Disallow attacking own targets (unit or structure)
	if (target_unit != null and target_unit.owner_id == actor) or (target_struct != null and target_struct.owner_id == actor):
		return "Choose an enemy target."
	if attacker.attacked:
		return "This unit has already attacked this turn."
	var distance: int = state.grid.distance(attacker.cell_id, target_unit.cell_id) if target_unit != null else state.grid.distance(attacker.cell_id, target_struct.cell_id)
	if distance > attacker.attack_range:
		return "Target is out of range (range %d)." % attacker.attack_range
	return ""

# Returns a fresh result; queries never mutate units, actions, or match state.
# Damage is the fixed attack value, even when clamping HP prevents overkill.
func preview_attack(actor: int, attacker_id: int, target_id: int) -> Result:
	var error: String = _attack_error(actor, attacker_id, target_id)
	if not error.is_empty():
		return Result.new(false, error)
	var attacker: GameState.Unit = state.units[attacker_id]
	var result: Result
	if state.units.has(target_id):
		var target_u: GameState.Unit = state.units[target_id]
		result = Result.new(true, "%s dealt %d damage to %s." % [attacker.unit_type, attacker.attack_damage, target_u.unit_type])
		result.damage = attacker.attack_damage
		result.target_hp = maxi(0, target_u.hp - result.damage)
		result.killed = result.target_hp == 0
		if result.killed:
			result.reason += " %s eliminated." % target_u.unit_type
	else:
		var target_s: GameState.Structure = state.structures[target_id]
		result = Result.new(true, "%s dealt %d damage to %s." % [attacker.unit_type, attacker.attack_damage, target_s.structure_type])
		result.damage = attacker.attack_damage
		result.target_hp = maxi(0, target_s.hp - result.damage)
		result.killed = result.target_hp == 0
		if result.killed:
			result.reason += " %s destroyed." % target_s.structure_type
			# Headquarters destruction immediately ends the match
			if target_s.structure_type == "Headquarters":
				result.winner_id = actor
				result.reason += " Player %d wins!" % actor
	return result

func attack_targets(actor: int, attacker_id: int) -> Array[int]:
	var targets: Array[int] = []
	# Consider both unit and structure targets
	for target_id: int in state.units:
		if preview_attack(actor, attacker_id, target_id).success:
			targets.append(target_id)
	for target_id: int in state.structures:
		if preview_attack(actor, attacker_id, target_id).success:
			targets.append(target_id)
	return targets

func try_attack(actor: int, attacker_id: int, target_id: int) -> Result:
	var result: Result = preview_attack(actor, attacker_id, target_id)
	if not result.success:
		return result
	var attacker: GameState.Unit = state.units[attacker_id]
	attacker.attacked = true
	attacker.moved = true
	# Apply damage to unit or structure
	if state.units.has(target_id):
		var t_u: GameState.Unit = state.units[target_id]
		t_u.hp = result.target_hp
		if result.killed:
			state.units.erase(target_id)
	else:
		var t_s: GameState.Structure = state.structures[target_id]
		t_s.hp = result.target_hp
		if result.killed:
			state.structures.erase(target_id)
	# Update winner if any
	state.winner_id = result.winner_id
	return result

func recruit_error(actor: int, headquarters_id: int, unit_type: String) -> String:
	var error: String = _actor_error(actor)
	if not error.is_empty():
		return error
	if not state.structures.has(headquarters_id):
		return "That headquarters does not exist."
	var headquarters: GameState.Structure = state.structures[headquarters_id]
	if headquarters.structure_type != "Headquarters" or headquarters.hp <= 0:
		return "Choose a living headquarters."
	if headquarters.owner_id != actor:
		return "You do not control that headquarters."
	if not headquarters.recruit_available:
		return "This headquarters has already recruited this turn."
	var kind: String = unit_type.capitalize()
	if not UnitTypes.STATS.has(kind) or not UnitTypes.COSTS.has(kind):
		return "Unknown unit type."
	if state.materials[actor] < int(UnitTypes.COSTS[kind]):
		return "Insufficient materials."
	return ""

func recruit_destinations(actor: int, headquarters_id: int, kind: String) -> Array[int]:
	var destinations: Array[int] = []
	if not recruit_error(actor, headquarters_id, kind).is_empty():
		return destinations
	var headquarters: GameState.Structure = state.structures[headquarters_id]
	for cell_id: int in state.grid.get_neighbors(headquarters.cell_id):
		if state.grid.contains(cell_id) and state.entity_at(cell_id) == null:
			destinations.append(cell_id)
	return destinations

func try_recruit(actor: int, headquarters_id: int, unit_type: String, destination: int) -> Result:
	var error: String = recruit_error(actor, headquarters_id, unit_type)
	if not error.is_empty():
		return Result.new(false, error)
	var headquarters: GameState.Structure = state.structures[headquarters_id]
	if not state.grid.contains(destination):
		return Result.new(false, "Choose a tile on the board.")
	if state.grid.distance(headquarters.cell_id, destination) != 1:
		return Result.new(false, "Destination must be adjacent to the headquarters.")
	if state.entity_at(destination) != null:
		return Result.new(false, "Destination is occupied.")
	var kind: String = unit_type.capitalize()
	var unit := GameState.Unit.new(state.allocate_id(), actor, kind, destination)
	unit.moved = true
	unit.attacked = true
	unit.ready_next_turn = true
	state.units[unit.id] = unit
	state.materials[actor] -= int(UnitTypes.COSTS[kind])
	headquarters.recruit_available = false
	return Result.new(true, "%s recruited. Ready next turn." % kind)

func restart_match() -> void:
	state.reset_match()
	# Ensure the active player's turn-start effects are applied once
	_start_turn()

