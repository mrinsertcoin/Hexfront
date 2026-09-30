class_name GameState
extends RefCounted
## Serializable logical state. Immutable gameplay data resolves by stable IDs.

class Unit extends RefCounted:
	var id: int
	var controller_id: int
	var definition_id: String
	var cell_id: int
	var moved: bool=false
	var attacked: bool=false
	var ready_next_turn: bool=false
	var hp: int
	var spider_state: SpiderState
	var development: BiologicalProductionState
	var remaining_lifetime_turns: int=0
	var disconnected_turns: int=0
	var road_segments_built_this_turn: int=0
	var selected_disease_id: String="tracking"
	var active_disease: DiseaseState
	var disease_immunities: Dictionary[String,int]={}
	var deployed: bool=false
	var designation: DesignationState
	var revealed_to_teams: Dictionary[int,int]={}
	var neutral_group_id: String=""
	var neutral_group_instance_id: int=-1
	var neutral_home_cell: int=-1
	var neutral_leash_distance: int=0
	var neutral_awareness_range: int=0
	var _movement_override: int=-1
	var _registry: ContentRegistry

	var owner_id: int:
		get: return controller_id
		set(value): controller_id=value
	var unit_type: String:
		get:
			var definition:=_registry.unit(definition_id)
			return definition.display_name if definition!=null else definition_id
	var movement: int:
		get:
			return _movement_override if _movement_override>=0 else UnitStatResolver.movement(self,_registry)
	var max_hp: int:
		get: return UnitStatResolver.max_hp(self,_registry)
	var attack_range: int:
		get: return UnitStatResolver.attack_range(self,_registry)
	var attack_damage: int:
		get: return UnitStatResolver.attack_damage(self,_registry)

	func _init(unit_id: int,controller: int,kind: String,coordinate: int,allowance: int=-1,
			content: ContentRegistry=null) -> void:
		id=unit_id; controller_id=controller; definition_id=UnitTypes.definition_id(kind)
		if definition_id.is_empty(): definition_id=kind
		cell_id=coordinate; _movement_override=allowance
		_registry=content if content!=null else ContentRegistry.default()
		var definition:=_registry.unit(definition_id)
		assert(definition!=null,"Unknown unit definition: "+definition_id)
		hp=definition.max_hp
		remaining_lifetime_turns=definition.temporary_lifetime_turns
		if "mobile_headquarters" in definition.tags: spider_state=SpiderState.new()

class Structure extends RefCounted:
	var id: int
	var controller_id: int
	var definition_id: String
	var cell_id: int
	var hp: int
	var recruit_available: bool=true
	var pillar_state: PillarState
	var designation: DesignationState
	var _max_hp_override: int=-1
	var _registry: ContentRegistry

	var owner_id: int:
		get: return controller_id
		set(value): controller_id=value
	var structure_type: String:
		get:
			var definition:=_registry.structure(definition_id)
			return definition.display_name if definition!=null else definition_id
	var max_hp: int:
		get:
			if _max_hp_override>0: return _max_hp_override
			var definition:=_registry.structure(definition_id)
			return definition.max_hp if definition!=null else 0

	func _init(structure_id: int,controller: int,kind: String,coordinate: int,hp_value: int=-1,
			content: ContentRegistry=null) -> void:
		id=structure_id; controller_id=controller
		definition_id="prototype_headquarters" if kind.to_lower() in ["headquarters","prototype_headquarters"] else kind
		cell_id=coordinate; _max_hp_override=hp_value
		_registry=content if content!=null else ContentRegistry.default()
		assert(_registry.structure(definition_id)!=null,"Unknown structure definition: "+definition_id)
		hp=max_hp

var units: Dictionary[int,Unit]={}
var structures: Dictionary[int,Structure]={}
var world_sites: Dictionary[int,WorldSiteState]={}
var players: Dictionary[int,PlayerState]={}
var controllers: Dictionary[int,ControllerState]={}
var relationships:=RelationshipState.new()
var living_migration:=LivingMigrationState.new()
var baumeister:=BaumeisterState.new()
var turn_state:=TurnState.new()
var next_id: int=200
var next_site_id: int=10000
var last_started_turn: int=-1
var winner_id: int=0
var grid: PlanetGrid
var registry: ContentRegistry
var setup: Dictionary
var population_fingerprint: String=""
var visibility_system: VisibilitySystem

var active_player: int:
	get: return turn_state.active_controller_id
	set(value):
		var found:=turn_state.order.find(value)
		if found>=0: turn_state.index=found
var round_number: int:
	get: return turn_state.round_number
	set(value): turn_state.round_number=value
var materials: Dictionary:
	get:
		var result:={}
		for player_id: int in players: result[player_id]=players[player_id].resource_amount("materials")
		return result

func _init(topology: PlanetGrid=null,match_setup: Dictionary={},content: ContentRegistry=null) -> void:
	grid=topology if topology!=null else PlanetGrid.new()
	registry=content if content!=null else ContentRegistry.default()
	setup=match_setup.duplicate(true)
	visibility_system=VisibilitySystem.new(self)
	reset_match()

func reset_match() -> void:
	units.clear(); structures.clear(); world_sites.clear(); players.clear(); controllers.clear()
	living_migration=LivingMigrationState.new()
	baumeister=BaumeisterState.new()
	next_id=200; next_site_id=10000; winner_id=0; last_started_turn=-1
	population_fingerprint=""
	visibility_system.reset()
	var faction_ids: Array[String]=[]
	faction_ids.assign(setup.get("faction_ids",["blue","red"]))
	var controller_kinds: Array[String]=[]
	controller_kinds.assign(setup.get("controller_kinds",[ControllerState.HUMAN,ControllerState.PLAYER_AI]))
	var team_ids: Array[int]=[]
	team_ids.assign(setup.get("team_ids",[]))
	controllers[0]=ControllerState.new(0,ControllerState.WORLD,"")
	for index in range(faction_ids.size()):
		var controller_id:=index+1
		var kind:=controller_kinds[index] if index<controller_kinds.size() else ControllerState.PLAYER_AI
		var team_id:=team_ids[index] if index<team_ids.size() else controller_id
		controllers[controller_id]=ControllerState.new(controller_id,kind,faction_ids[index],team_id)
		players[controller_id]=PlayerState.new(controller_id,controller_id,faction_ids[index])
		var faction:=registry.faction(faction_ids[index])
		assert(faction!=null,"Unknown faction: "+faction_ids[index])
		players[controller_id].resources=faction.starting_resources.duplicate(true)
	var order: Array[int]=[]
	for player_id: int in players: order.append(player_id)
	order.sort(); turn_state.reset(order)
	relationships=RelationshipState.new()
	for a: int in order:
		for b: int in order:
			if a<b:
				var relation:=RelationshipState.Kind.ALLIED if controllers[a].team_id==controllers[b].team_id else RelationshipState.Kind.HOSTILE
				relationships.set_relationship(a,b,relation)
	_spawn_starting_content(order)
	_initialize_faction_state(order)
	start_turn()
	refresh_visibility()

func _spawn_starting_content(order: Array[int]) -> void:
	var homes:=_starting_homes(order.size())
	for player_index in range(order.size()):
		var controller_id:=order[player_index]
		var faction:=registry.faction(players[controller_id].faction_id)
		var home:=homes[player_index] if player_index<homes.size() else grid.breadth_first(homes.back()).order[-1]
		var neighbors:=grid.get_neighbors(home)
		var legacy_ids: Array[int]=[]
		if controller_id==1: legacy_ids.assign([1,2,5])
		elif controller_id==2: legacy_ids.assign([3,4,6])
		for index in range(faction.starting_unit_ids.size()):
			var entity_id:=legacy_ids[index] if index<legacy_ids.size() else allocate_id()
			var definition:=registry.unit(faction.starting_unit_ids[index])
			var cell_id: int=home if "mobile_headquarters" in definition.tags else neighbors[index%neighbors.size()]
			units[entity_id]=Unit.new(entity_id,controller_id,definition.id,cell_id,-1,registry)
		for structure_id: String in faction.starting_structure_ids:
			var entity_id:=99+controller_id if structure_id=="prototype_headquarters" and controller_id<=2 else allocate_id()
			structures[entity_id]=Structure.new(entity_id,controller_id,structure_id,home,-1,registry)

func _initialize_faction_state(order: Array[int]) -> void:
	for controller_id: int in order:
		var faction:=registry.faction(players[controller_id].faction_id)
		if faction.gameplay_config is LivingMigrationConfig:
			var config:=faction.gameplay_config as LivingMigrationConfig
			for unit: Unit in units.values():
				if unit.controller_id!=controller_id: continue
				var definition:=registry.unit(unit.definition_id)
				if unit.spider_state!=null:
					unit.spider_state.slot_limit=config.internal_slot_count
					if not config.starting_nursery_branch.is_empty():
						unit.spider_state.nursery_branch=config.starting_nursery_branch
						unit.spider_state.slots.append(config.starting_nursery_branch)
					living_migration.add_road(controller_id,unit.cell_id)
				elif "road_bound" in definition.tags: living_migration.add_road(controller_id,unit.cell_id)
		elif faction.gameplay_config is BaumeisterConfig:
			var config:=faction.gameplay_config as BaumeisterConfig
			for structure: Structure in structures.values():
				if structure.controller_id==controller_id and "pillar" in registry.structure(structure.definition_id).tags:
					structure.pillar_state=PillarState.new(config.pillar_max_integrity,true)
					baumeister.origin_pillars[controller_id]=structure.id

func _starting_homes(count: int) -> Array[int]:
	var homes: Array[int]=[]
	if count<=0 or grid.cells.is_empty(): return homes
	# Preserve the prototype anchors exactly, then spread additional factions by
	# maximizing their minimum graph distance from every already selected home.
	homes.append(0)
	if count>1: homes.append(grid.breadth_first(0).order[-1])
	while homes.size()<count:
		var best_cell:=-1
		var best_distance:=-1
		for cell: PlanetCell in grid.cells:
			if cell.id in homes: continue
			var minimum:=2147483647
			for home: int in homes: minimum=mini(minimum,grid.distance(cell.id,home))
			if minimum>best_distance:
				best_distance=minimum; best_cell=cell.id
		if best_cell<0: break
		homes.append(best_cell)
	return homes

func player_for_controller(controller_id: int) -> PlayerState:
	return players.get(controller_id)

func unit_at(cell_id: int) -> Unit:
	for unit: Unit in units.values():
		if unit.cell_id==cell_id: return unit
	return null

func structure_at(cell_id: int) -> Structure:
	for structure: Structure in structures.values():
		if structure.cell_id==cell_id: return structure
	return null

func site_at(cell_id: int) -> WorldSiteState:
	for site: WorldSiteState in world_sites.values():
		if site.cell_id==cell_id: return site
	return null

func entity_at(cell_id: int) -> RefCounted:
	var unit:=unit_at(cell_id)
	if unit!=null: return unit
	return structure_at(cell_id)

func is_cell_blocked(cell_id: int,ignore_entity_id: int=-1) -> bool:
	var unit:=unit_at(cell_id)
	if unit!=null and unit.id!=ignore_entity_id: return true
	var structure:=structure_at(cell_id)
	if structure!=null and structure.id!=ignore_entity_id: return true
	var site:=site_at(cell_id)
	if site!=null:
		var definition:=registry.world_site(site.definition_id)
		return definition!=null and definition.blocks_movement
	return false

func allocate_id() -> int:
	while units.has(next_id) or structures.has(next_id): next_id+=1
	var result:=next_id; next_id+=1; return result

func allocate_site_id() -> int:
	while world_sites.has(next_site_id): next_site_id+=1
	var result:=next_site_id; next_site_id+=1; return result

func remove_unit(unit_id: int,leave_corpse: bool=true) -> Unit:
	if not units.has(unit_id): return null
	var unit: Unit=units[unit_id]
	if leave_corpse:
		var definition:=registry.unit(unit.definition_id)
		if definition!=null and definition.corpse_food_value>0:
			living_migration.add_corpse(unit.definition_id,unit.cell_id,definition.corpse_food_value)
	units.erase(unit_id)
	return unit

func remove_structure(structure_id: int) -> Structure:
	if not structures.has(structure_id): return null
	var structure: Structure=structures[structure_id]
	structures.erase(structure_id)
	var removed_bridges: Array[int]=[]
	for bridge: BridgeState in baumeister.bridges.values():
		if bridge.endpoint_a==structure_id or bridge.endpoint_b==structure_id: removed_bridges.append(bridge.id)
	for bridge_id: int in removed_bridges: baumeister.bridges.erase(bridge_id)
	var removed_districts: Array[int]=[]
	for district: DistrictState in baumeister.districts.values():
		if district.pillar_id==structure_id: removed_districts.append(district.id)
	for district_id: int in removed_districts: baumeister.districts.erase(district_id)
	_recalculate_baumeister_supply_state(structure.controller_id)
	return structure

func _recalculate_baumeister_supply_state(controller_id: int) -> void:
	for pillar: Structure in structures.values():
		if pillar.controller_id==controller_id and pillar.pillar_state!=null: pillar.pillar_state.supplied=false
	var origin_id: int=baumeister.origin_pillars.get(controller_id,-1)
	if not structures.has(origin_id): return
	var supplied: Array[int]=[origin_id]; structures[origin_id].pillar_state.supplied=true
	var cursor:=0
	while cursor<supplied.size():
		var current:=supplied[cursor]; cursor+=1
		for bridge: BridgeState in baumeister.bridges.values():
			if bridge.controller_id!=controller_id or not bridge.operational: continue
			var other:=-1
			if bridge.endpoint_a==current: other=bridge.endpoint_b
			elif bridge.endpoint_b==current: other=bridge.endpoint_a
			if other>=0 and structures.has(other) and other not in supplied:
				supplied.append(other); structures[other].pillar_state.supplied=true

func add_world_site(definition_id: String,cell_id: int,controller_id: int=0) -> WorldSiteState:
	var definition:=registry.world_site(definition_id)
	assert(definition!=null,"Unknown world site: "+definition_id)
	var site:=WorldSiteState.new(allocate_site_id(),definition_id,cell_id,controller_id)
	site.runtime_state={"remaining_charges":definition.initial_charges,"exhausted":false,
		"regeneration_remaining":0,"explored":false,"trade_usage":{}}
	world_sites[site.id]=site
	return site

func apply_population(result: WorldPopulationResult) -> void:
	population_fingerprint=result.fingerprint
	for record: Dictionary in result.site_records:
		add_world_site(record.definition_id,record.cell_id,record.get("controller_id",0))
	var group_instance:=0
	for record: Dictionary in result.neutral_group_records:
		var controller_id: int=record.get("controller_id",50)
		if not controllers.has(controller_id): controllers[controller_id]=ControllerState.new(controller_id,ControllerState.NEUTRAL_AI,"")
		for player_id: int in players:
			var relationship:=RelationshipState.Kind.HOSTILE if record.get("relationship_policy","neutral")=="hostile" else RelationshipState.Kind.NEUTRAL
			relationships.set_relationship(player_id,controller_id,relationship)
		for unit_record: Dictionary in record.get("unit_records",[]):
			if is_cell_blocked(unit_record.cell_id): continue
			var entity_id:=allocate_id()
			var unit:=Unit.new(entity_id,controller_id,unit_record.definition_id,unit_record.cell_id,-1,registry)
			unit.neutral_group_id=record.definition_id; unit.neutral_group_instance_id=group_instance
			unit.neutral_home_cell=record.cell_id; unit.neutral_leash_distance=record.get("leash_distance",3)
			unit.neutral_awareness_range=record.get("awareness_range",3)
			units[entity_id]=unit
		group_instance+=1
	turn_state.neutral_phase_enabled=not result.neutral_group_records.is_empty()
	refresh_visibility()

func clear_population() -> void:
	world_sites.clear(); population_fingerprint=""; next_site_id=10000
	var neutral_ids: Array[int]=[]
	for unit: Unit in units.values():
		if not unit.neutral_group_id.is_empty(): neutral_ids.append(unit.id)
	for id: int in neutral_ids: units.erase(id)
	var controller_ids: Array[int]=[]
	for id: int in controllers:
		if controllers[id].kind==ControllerState.NEUTRAL_AI: controller_ids.append(id)
	for id: int in controller_ids:
		controllers.erase(id); relationships.clear_controller(id)
	turn_state.neutral_phase_enabled=false; turn_state.neutral_phase=false
	refresh_visibility()

func start_turn() -> void:
	if winner_id!=0 or last_started_turn==turn_state.serial: return
	last_started_turn=turn_state.serial
	var controller_id:=active_player
	if players.has(controller_id):
		var player: PlayerState=players[controller_id]
		player.add_resources(registry.faction(player.faction_id).turn_resource_income)
		_process_unit_economy_and_status(controller_id,player)
	for unit: Unit in units.values():
		var is_active_neutral:=turn_state.neutral_phase and controllers.has(unit.controller_id) and controllers[unit.controller_id].kind==ControllerState.NEUTRAL_AI
		if unit.controller_id==controller_id or is_active_neutral:
			unit.moved=false; unit.attacked=false; unit.road_segments_built_this_turn=0; unit.ready_next_turn=false
	for structure: Structure in structures.values():
		if structure.controller_id==controller_id: structure.recruit_available=true
	_process_designations(controller_id)

func advance_turn() -> int:
	turn_state.advance()
	if turn_state.index==0 and living_migration.last_regrowth_round<turn_state.round_number:
		living_migration.last_regrowth_round=turn_state.round_number
		for terrain_state: TerrainConsumptionState in living_migration.terrain.values(): terrain_state.advance()
		_process_world_site_regeneration()
	start_turn()
	refresh_visibility()
	return active_player

func refresh_visibility() -> void:
	if visibility_system!=null and grid!=null: visibility_system.recalculate_all()

func _process_world_site_regeneration() -> void:
	for site: WorldSiteState in world_sites.values():
		var definition:=registry.world_site(site.definition_id)
		if definition==null or definition.regeneration_turns<=0 or not site.runtime_state.get("exhausted",false): continue
		var remaining: int=site.runtime_state.get("regeneration_remaining",definition.regeneration_turns)-1
		site.runtime_state.regeneration_remaining=remaining
		if remaining<=0:
			site.runtime_state.remaining_charges=definition.initial_charges
			site.runtime_state.exhausted=false

func _process_unit_economy_and_status(controller_id: int,player: PlayerState) -> void:
	var production: Dictionary[String,int]={}
	var upkeep: Dictionary[String,int]={}
	var expired: Array[int]=[]
	for unit: Unit in units.values():
		if unit.controller_id!=controller_id: continue
		var definition:=registry.unit(unit.definition_id)
		for resource_id: String in definition.turn_production:
			production[resource_id]=production.get(resource_id,0)+definition.turn_production[resource_id]
		for resource_id: String in definition.upkeep:
			upkeep[resource_id]=upkeep.get(resource_id,0)+definition.upkeep[resource_id]
		if unit.spider_state!=null:
			var faction:=registry.faction(player.faction_id)
			if faction.gameplay_config is LivingMigrationConfig:
				var config:=faction.gameplay_config as LivingMigrationConfig
				production["food"]=production.get("food",0)+config.spider_food_production+unit.spider_state.building_count("food_production")*config.food_per_food_building
				production["silk"]=production.get("silk",0)+config.spider_silk_production
				production["synapse"]=production.get("synapse",0)+unit.spider_state.building_count("synapse_production")*config.synapse_per_synapse_building
		if unit.remaining_lifetime_turns>0 and not unit.ready_next_turn:
			unit.remaining_lifetime_turns-=1
			if unit.remaining_lifetime_turns==0: expired.append(unit.id)
		_process_disease_turn(unit,expired)
	for structure: Structure in structures.values():
		if structure.controller_id!=controller_id: continue
		var structure_definition:=registry.structure(structure.definition_id)
		for resource_id: String in structure_definition.turn_production:
			production[resource_id]=production.get(resource_id,0)+structure_definition.turn_production[resource_id]
		for resource_id: String in structure_definition.upkeep:
			upkeep[resource_id]=upkeep.get(resource_id,0)+structure_definition.upkeep[resource_id]
	for district: DistrictState in baumeister.districts.values():
		if district.controller_id!=controller_id or not district.completed: continue
		var district_definition:=registry.district(district.definition_id)
		for resource_id: String in district_definition.turn_production:
			production[resource_id]=production.get(resource_id,0)+district_definition.turn_production[resource_id]
		for resource_id: String in district_definition.upkeep:
			upkeep[resource_id]=upkeep.get(resource_id,0)+district_definition.upkeep[resource_id]
	player.add_resources(production)
	var unpaid: Dictionary[String,int]={}
	for resource_id: String in upkeep:
		var paid:=mini(player.resource_amount(resource_id),upkeep[resource_id])
		player.resources[resource_id]=player.resource_amount(resource_id)-paid
		if paid<upkeep[resource_id]: unpaid[resource_id]=upkeep[resource_id]-paid
	living_migration.unpaid_upkeep[controller_id]=unpaid
	for unit_id: int in expired: remove_unit(unit_id,true)

func _process_designations(controller_id: int) -> void:
	for unit: Unit in units.values():
		if unit.designation!=null and unit.designation.source_controller_id==controller_id:
			unit.designation.remaining_turns-=1
			if unit.designation.remaining_turns<=0: unit.designation=null
	for structure: Structure in structures.values():
		if structure.designation!=null and structure.designation.source_controller_id==controller_id:
			structure.designation.remaining_turns-=1
			if structure.designation.remaining_turns<=0: structure.designation=null

func _process_disease_turn(unit: Unit,expired: Array[int]) -> void:
	var immunity_ids: Array[String]=[]
	for id: String in unit.disease_immunities:
		unit.disease_immunities[id]=maxi(0,unit.disease_immunities[id]-1)
		if unit.disease_immunities[id]==0: immunity_ids.append(id)
	for id: String in immunity_ids: unit.disease_immunities.erase(id)
	if unit.active_disease==null: return
	if unit.active_disease.damage_per_turn>0:
		unit.hp=maxi(0,unit.hp-unit.active_disease.damage_per_turn)
		if unit.hp==0 and unit.id not in expired: expired.append(unit.id)
	unit.active_disease.remaining_turns-=1
	if unit.active_disease.remaining_turns<=0:
		var disease:=registry.disease(unit.active_disease.definition_id)
		if disease!=null and disease.immunity_turns>0:
			unit.disease_immunities[disease.id]=disease.immunity_turns
		unit.active_disease=null
