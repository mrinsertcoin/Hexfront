class_name TestState
extends RefCounted

static func snapshot(state: GameState) -> String:
	var values: Array = [state.active_player, state.round_number, state.winner_id, state.next_id,
		state.last_started_turn, state.grid.fingerprint, state.materials.duplicate()]
	for id: int in state.units:
		var unit: GameState.Unit = state.units[id]
		values.append([id, unit.id, unit.owner_id, unit.unit_type, unit.cell_id, unit.movement,
			unit.moved, unit.attacked, unit.ready_next_turn, unit.hp, unit.max_hp, unit.attack_range, unit.attack_damage])
	for id: int in state.structures:
		var structure: GameState.Structure = state.structures[id]
		values.append([id, structure.id, structure.owner_id, structure.structure_type, structure.cell_id,
			structure.hp, structure.max_hp, structure.recruit_available])
	return var_to_str(values)
