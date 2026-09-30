class_name TestState
extends RefCounted

static func snapshot(state: GameState) -> String:
	var values: Array = [state.active_player, state.round_number, state.winner_id, state.next_id,
		state.last_started_turn, state.grid.fingerprint, state.materials.duplicate()]
	for id: int in state.players:
		var player: PlayerState=state.players[id]
		values.append(["p",id,player.controller_id,player.faction_id,player.resources.duplicate(),
			player.research.completed_ids,player.research.current_technology_id,player.research.accumulated_progress])
	for id: int in state.units:
		var unit: GameState.Unit = state.units[id]
		values.append([id, unit.id, unit.controller_id, unit.definition_id, unit.cell_id, unit.movement,
			unit.moved, unit.attacked, unit.ready_next_turn, unit.hp, unit.max_hp, unit.attack_range, unit.attack_damage,
			unit.remaining_lifetime_turns,unit.disconnected_turns,unit.road_segments_built_this_turn,unit.selected_disease_id,
			unit.disease_immunities.duplicate(),unit.active_disease.snapshot() if unit.active_disease!=null else {},
			unit.spider_state.snapshot() if unit.spider_state!=null else {},unit.development.snapshot() if unit.development!=null else {},
			unit.deployed,unit.designation.snapshot() if unit.designation!=null else {}])
	for id: int in state.structures:
		var structure: GameState.Structure = state.structures[id]
		values.append([id, structure.id, structure.controller_id, structure.definition_id, structure.cell_id,
			structure.hp, structure.max_hp, structure.recruit_available,
			structure.pillar_state.snapshot() if structure.pillar_state!=null else {},
			structure.designation.snapshot() if structure.designation!=null else {}])
	for id: int in state.world_sites:
		var site: WorldSiteState=state.world_sites[id]
		values.append(["site",id,site.definition_id,site.cell_id,site.controller_id,site.runtime_state.duplicate()])
	var terrain_ids: Array[int]=[]
	for id: int in state.living_migration.terrain: terrain_ids.append(id)
	terrain_ids.sort()
	for id: int in terrain_ids: values.append(["terrain",id,state.living_migration.terrain[id].snapshot()])
	var controller_ids: Array[int]=[]
	for id: int in state.living_migration.roads: controller_ids.append(id)
	controller_ids.sort()
	for id: int in controller_ids: values.append(["roads",id,state.living_migration.road_cells(id)])
	var corpse_ids: Array[int]=[]
	for id: int in state.living_migration.corpses: corpse_ids.append(id)
	corpse_ids.sort()
	for id: int in corpse_ids:
		var corpse: CorpseState=state.living_migration.corpses[id]
		values.append(["corpse",id,corpse.source_definition_id,corpse.cell_id,corpse.food_value,corpse.consumed])
	values.append(["living_meta",state.living_migration.next_corpse_id,state.living_migration.last_regrowth_round,
		state.living_migration.unpaid_upkeep.duplicate(true)])
	values.append(["baumeister",state.baumeister.snapshot()])
	return var_to_str(values)
