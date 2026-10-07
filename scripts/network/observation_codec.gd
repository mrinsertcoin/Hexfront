class_name ObservationCodec
extends RefCounted
## Converts permitted observations into versioned primitive snapshots.

static func encode(state: GameState,controller_id: int,sync_revision: int,events: Array=[]) -> Dictionary:
	var observation:=state.visibility_system.observation_for_controller(controller_id)
	var player: PlayerState=state.players.get(controller_id)
	var controller: ControllerState=state.controllers.get(controller_id)
	var public_players: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.players):
		var entry: PlayerState=state.players[id]
		public_players.append({"player_id":id,"player_name":entry.player_name,"faction_id":entry.faction_id,
			"team_id":state.controllers[id].team_id,"player_color":entry.ownership_color,
			"connected":entry.connected,"defeated":entry.eliminated})
	var result:={
		"protocol_version":NetworkProtocol.NETWORK_PROTOCOL_VERSION,
		"schema_version":NetworkProtocol.SNAPSHOT_SCHEMA_VERSION,
		"sync_revision":sync_revision,
		"visibility_revision":observation.revision,
		"recipient_player_id":controller_id,
		"recipient_team_id":controller.team_id if controller!=null else controller_id,
		"turn":{"active_player":state.active_player,"round_number":state.round_number,"serial":state.turn_state.serial,
			"neutral_phase":state.turn_state.neutral_phase,"phase":state.turn_state.phase,"winner_id":state.winner_id,
			"match_duration_seconds":state.match_duration_seconds()},
		"players":public_players,
		"own_player":_player_snapshot(player),
		"visible_cells":Array(observation.visible_cells),
		"explored_cells":Array(observation.explored_cells),
		"detection_cells":Array(observation.detection_cells),
		"visible_entities":_dictionary_values(observation.visible_entities),
		"known_contacts":_dictionary_values(observation.known_contacts),
		"observed_sites":_dictionary_values(observation.observed_sites),
		"newly_observed_entity_ids":observation.newly_observed_entity_ids.duplicate(),
		"lost_entity_ids":observation.lost_entity_ids.duplicate(),
		"newly_discovered_site_ids":observation.newly_discovered_site_ids.duplicate(),
		"owned_entities":_owned_entity_snapshots(state,controller_id),
		"owned_faction_state":_owned_faction_state(state,controller_id),
		"visible_world_state":_visible_world_state(state,observation,controller_id),
		"combat_planning":state.combat_planning.snapshot_for(controller_id),
		"events":state.public_events.duplicate(true) if events.is_empty() else events.duplicate(true),
	}
	return result

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "Snapshot is not a dictionary."
	var data:=value as Dictionary
	if int(data.get("protocol_version",-1))!=NetworkProtocol.NETWORK_PROTOCOL_VERSION: return "Snapshot protocol does not match."
	if int(data.get("schema_version",-1))!=NetworkProtocol.SNAPSHOT_SCHEMA_VERSION: return "Unsupported snapshot schema."
	for key: String in ["sync_revision","recipient_player_id","turn","own_player","visible_cells","explored_cells",
		"visible_entities","known_contacts","observed_sites"]:
		if not data.has(key): return "Snapshot is missing "+key+"."
	return ""

static func decode_observation(data: Dictionary) -> TeamObservation:
	if not validation_error(data).is_empty(): return null
	var result:=TeamObservation.new()
	result.team_id=int(data.get("recipient_team_id",-1)); result.revision=int(data.get("visibility_revision",0))
	result.visible_cells=PackedByteArray(data.visible_cells); result.explored_cells=PackedByteArray(data.explored_cells)
	result.detection_cells=PackedByteArray(data.get("detection_cells",[]))
	for item: Dictionary in data.visible_entities: result.visible_entities[int(item.id)]=item.duplicate(true)
	for item: Dictionary in data.known_contacts: result.known_contacts[int(item.contact_id)]=item.duplicate(true)
	for item: Dictionary in data.observed_sites: result.observed_sites[int(item.id)]=item.duplicate(true)
	result.newly_observed_entity_ids.assign(data.get("newly_observed_entity_ids",[]))
	result.lost_entity_ids.assign(data.get("lost_entity_ids",[]))
	result.newly_discovered_site_ids.assign(data.get("newly_discovered_site_ids",[]))
	return result

static func contains_forbidden_hidden_id(snapshot: Dictionary,entity_id: int) -> bool:
	for key: String in ["visible_entities","owned_entities"]:
		for row: Dictionary in snapshot.get(key,[]):
			if int(row.get("id",-1))==entity_id: return true
	for row: Dictionary in snapshot.get("known_contacts",[]):
		if int(row.get("contact_id",-1))==entity_id: return true
	return false

static func _player_snapshot(player: PlayerState) -> Dictionary:
	if player==null: return {}
	return {"player_id":player.player_id,"controller_id":player.controller_id,"faction_id":player.faction_id,
		"resources":player.resources.duplicate(true),"research":{"completed_ids":Array(player.research.completed_ids),
		"current_technology_id":player.research.current_technology_id,"accumulated_progress":player.research.accumulated_progress}}

static func _owned_entity_snapshots(state: GameState,controller_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.units):
		var unit: GameState.Unit=state.units[id]
		if unit.controller_id!=controller_id: continue
		result.append({"id":unit.id,"kind":"unit","definition_id":unit.definition_id,"controller_id":controller_id,
			"cell_id":unit.cell_id,"hp":unit.hp,"max_hp":unit.max_hp,"movement":unit.movement,"moved":unit.moved,
			"attacked":unit.attacked,"ready_next_turn":unit.ready_next_turn,"upkeep_paid":unit.upkeep_paid,"deployed":unit.deployed,
			"counter_cooldown_remaining":unit.counter_cooldown_remaining,
			"spider_state":unit.spider_state.snapshot() if unit.spider_state!=null else {},
			"development":unit.development.snapshot() if unit.development!=null else {},
			"active_disease":unit.active_disease.snapshot() if unit.active_disease!=null else {}})
	for id: int in _sorted_int_keys(state.structures):
		var structure: GameState.Structure=state.structures[id]
		if structure.controller_id!=controller_id: continue
		result.append({"id":structure.id,"kind":"structure","definition_id":structure.definition_id,
			"controller_id":controller_id,"cell_id":structure.cell_id,"hp":structure.hp,"max_hp":structure.max_hp,
			"recruit_available":structure.recruit_available,
			"pillar_state":structure.pillar_state.snapshot() if structure.pillar_state!=null else {}})
	return result

static func _owned_faction_state(state: GameState,controller_id: int) -> Dictionary:
	var roads: Array=[]
	if state.living_migration.roads.has(controller_id): roads=Array(state.living_migration.road_cells(controller_id))
	var districts: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.baumeister.districts):
		var district: DistrictState=state.baumeister.districts[id]
		if district.controller_id==controller_id: districts.append(district.snapshot())
	var bridges: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.baumeister.bridges):
		var bridge: BridgeState=state.baumeister.bridges[id]
		if bridge.controller_id==controller_id: bridges.append(bridge.snapshot())
	var larvae: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.living_migration.larvae):
		var larva: LarvaState=state.living_migration.larvae[id]
		if larva.owner==controller_id: larvae.append(larva.snapshot())
	return {"road_cells":roads,"larvae":larvae,"districts":districts,"bridges":bridges}

static func _visible_world_state(state: GameState,observation: TeamObservation,controller_id: int) -> Dictionary:
	var corpses: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.living_migration.corpses):
		var corpse: CorpseState=state.living_migration.corpses[id]
		if observation.is_visible(corpse.cell_id): corpses.append({"id":corpse.id,"source_definition_id":corpse.source_definition_id,
			"cell_id":corpse.cell_id,"food_value":corpse.food_value,"consumed":corpse.consumed})
	var terrain: Array[Dictionary]=[]
	for cell_id: int in _sorted_int_keys(state.living_migration.terrain):
		if observation.is_visible(cell_id): terrain.append({"cell_id":cell_id,"state":state.living_migration.terrain[cell_id].snapshot()})
	var roads: Array[Dictionary]=[]
	var larvae: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.living_migration.larvae):
		var larva: LarvaState=state.living_migration.larvae[id]
		if larva.owner==controller_id: larvae.append(larva.snapshot())
		elif observation.is_visible(larva.cell_id): larvae.append({"id":larva.id,"owner":larva.owner,"source_species":larva.source_species,
			"cell_id":larva.cell_id,"created_round":larva.created_round,"maturation_round":larva.maturation_round,"ready_to_emerge":larva.ready_to_emerge})
	for owner_id: int in _sorted_int_keys(state.living_migration.roads):
		var cells: Array[int]=[]
		for cell_id: int in state.living_migration.road_cells(owner_id):
			if owner_id==controller_id or observation.is_visible(cell_id): cells.append(cell_id)
		if not cells.is_empty(): roads.append({"controller_id":owner_id,"cells":cells})
	var districts: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.baumeister.districts):
		var district: DistrictState=state.baumeister.districts[id]
		if district.controller_id==controller_id or observation.is_visible(district.cell_id): districts.append(district.snapshot())
	var bridges: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(state.baumeister.bridges):
		var bridge: BridgeState=state.baumeister.bridges[id]
		if bridge.controller_id==controller_id:
			bridges.append(bridge.snapshot()); continue
		var visible_path: Array[int]=[]
		for cell_id: int in bridge.path:
			if observation.is_visible(cell_id): visible_path.append(cell_id)
		if not visible_path.is_empty(): bridges.append({"id":bridge.id,"controller_id":bridge.controller_id,
			"visible_path":visible_path,"completed":bridge.completed,"operational":bridge.operational,"hp":bridge.hp,"max_hp":bridge.max_hp})
	return {"corpses":corpses,"terrain":terrain,"roads":roads,"larvae":larvae,"districts":districts,"bridges":bridges}

static func _dictionary_values(values: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: int in _sorted_int_keys(values): result.append((values[id] as Dictionary).duplicate(true))
	return result

static func _sorted_int_keys(values: Dictionary) -> Array[int]:
	var result: Array[int]=[]
	for key: Variant in values: result.append(int(key))
	result.sort(); return result

static func _has_headquarters(state: GameState,controller_id: int) -> bool:
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id and "headquarters" in state.registry.unit(unit.definition_id).tags: return true
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller_id and "headquarters" in state.registry.structure(structure.definition_id).tags: return true
	return false
