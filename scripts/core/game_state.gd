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
	var upkeep_paid: bool=true
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
	var counter_cooldown_remaining: int=0
	var revealed_to_teams: Dictionary[int,int]={}
	var neutral_group_id: String=""
	var neutral_group_instance_id: int=-1
	var neutral_home_cell: int=-1
	var neutral_leash_distance: int=0
	var neutral_awareness_range: int=0
	var home_site_id: int=-1
	var neutral_allegiance_id: String=""
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
var combat_orders:=CombatOrderState.new()
var baumeister:=BaumeisterState.new()
var turn_state:=TurnState.new()
var next_id: int=200
var next_site_id: int=10000
var last_started_turn: int=-1
var started_controller_rounds: Dictionary[int,int]={}
var winner_id: int=0
var grid: PlanetGrid
var registry: ContentRegistry
var setup: Dictionary
var population_fingerprint: String=""
var visibility_system: VisibilitySystem
var starting_cells: Dictionary[int,int]={}
var start_diagnostics: Dictionary[int,Dictionary]={}
var public_events: Array[Dictionary]=[]
var match_started_msec: int=0
var water_cells: Dictionary[int,bool]={}
var terrain: TerracedTerrain
var _village_leash_cells: Dictionary={}

func village_guard_home(unit: Unit) -> int:
	if "village_guard" not in registry.unit(unit.definition_id).tags: return -1
	var home: WorldSiteState=world_sites.get(unit.home_site_id) as WorldSiteState
	return home.cell_id if home!=null and home.definition_id=="village" else unit.neutral_home_cell

func village_guard_cells(unit: Unit) -> Dictionary:
	var home:=village_guard_home(unit)
	if home<0: return {}
	if not _village_leash_cells.has(home):
		var allowed:={}
		for cell_id: int in grid.get_cells_within_distance(home,5): allowed[cell_id]=true
		_village_leash_cells[home]=allowed
	return _village_leash_cells[home]

func terrain_edge_allowed(unit: Unit,from_cell: int,to_cell: int) -> bool:
	if village_guard_home(unit)>=0 and not village_guard_cells(unit).has(to_cell): return false
	return terrain==null or terrain.can_cross(from_cell,to_cell,"flying" in registry.unit(unit.definition_id).tags)

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
	_village_leash_cells.clear()
	units.clear(); structures.clear(); world_sites.clear(); players.clear(); controllers.clear()
	living_migration=LivingMigrationState.new()
	combat_orders=CombatOrderState.new()
	baumeister=BaumeisterState.new()
	next_id=200; next_site_id=10000; winner_id=0; last_started_turn=-1; started_controller_rounds.clear()
	population_fingerprint=""; starting_cells.clear(); start_diagnostics.clear(); public_events.clear()
	match_started_msec=Time.get_ticks_msec()
	water_cells.clear()
	for value: Variant in setup.get("water_cells",[]): water_cells[int(value)]=true
	visibility_system.reset()
	var faction_ids: Array[String]=[]
	faction_ids.assign(setup.get("faction_ids",["blue","red"]))
	var controller_kinds: Array[String]=[]
	controller_kinds.assign(setup.get("controller_kinds",[ControllerState.HUMAN,ControllerState.PLAYER_AI]))
	var team_ids: Array[int]=[]
	team_ids.assign(setup.get("team_ids",[]))
	var player_ids: Array[int]=[]
	player_ids.assign(setup.get("player_ids",[]))
	var player_names: Array[String]=[]
	player_names.assign(setup.get("player_names",[]))
	var player_colors: Array[String]=[]
	player_colors.assign(setup.get("player_colors",[]))
	controllers[0]=ControllerState.new(0,ControllerState.WORLD,"")
	for index in range(faction_ids.size()):
		var controller_id:=player_ids[index] if index<player_ids.size() else index+1
		var kind:=controller_kinds[index] if index<controller_kinds.size() else ControllerState.PLAYER_AI
		var team_id:=team_ids[index] if index<team_ids.size() else controller_id
		controllers[controller_id]=ControllerState.new(controller_id,kind,faction_ids[index],team_id)
		var player_name:=player_names[index] if index<player_names.size() else "Player %d" % controller_id
		var player_color:=player_colors[index] if index<player_colors.size() else ""
		players[controller_id]=PlayerState.new(controller_id,controller_id,faction_ids[index],player_name,player_color)
		var faction:=registry.faction(faction_ids[index])
		assert(faction!=null,"Unknown faction: "+faction_ids[index])
		players[controller_id].resources=faction.starting_resources.duplicate(true)
	var order: Array[int]=[]; var human_order: Array[int]=[]; var enemy_order: Array[int]=[]
	for player_id: int in players:
		if bool(setup.get("simultaneous_player_turns",false)) and controllers[player_id].kind==ControllerState.HUMAN: human_order.append(player_id)
		else: enemy_order.append(player_id)
	human_order.sort(); enemy_order.sort()
	if bool(setup.get("simultaneous_player_turns",false)): order.assign(enemy_order+human_order)
	else:
		for player_id: int in players: order.append(player_id)
		order.sort()
	turn_state.simultaneous_combat_enabled=bool(setup.get("simultaneous_combat",true)); turn_state.reset(order,human_order)
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
	var homes:=_starting_homes(order)
	for player_index in range(order.size()):
		var controller_id:=order[player_index]
		var faction:=registry.faction(players[controller_id].faction_id)
		var home:=homes[player_index] if player_index<homes.size() else grid.breadth_first(homes.back()).order[-1]
		starting_cells[controller_id]=home
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
				elif "road_bound" in definition.tags: living_migration.add_road(controller_id,unit.cell_id)
		elif faction.gameplay_config is BaumeisterConfig:
			var config:=faction.gameplay_config as BaumeisterConfig
			for structure: Structure in structures.values():
				if structure.controller_id==controller_id and "pillar" in registry.structure(structure.definition_id).tags:
					structure.pillar_state=PillarState.new(config.pillar_max_integrity,true)
					baumeister.origin_pillars[controller_id]=structure.id
	_cleanup_spider_roads()

func _cleanup_spider_roads() -> void:
	for unit: Unit in units.values():
		if unit.spider_state!=null:
			living_migration.remove_road(unit.controller_id,unit.cell_id)

func _starting_homes(order: Array[int]) -> Array[int]:
	var homes: Array[int]=[]
	if order.is_empty() or grid.cells.is_empty(): return homes
	var suitability: Dictionary=setup.get("start_suitability",{})
	# Offline prototype states keep their historical anchors. Generated matches
	# provide faction-aware suitability arrays and use graph-distance maximin.
	if suitability.is_empty():
		homes.append(0)
		if order.size()>1: homes.append(grid.breadth_first(0).order[-1])
	var start_seed:=int(setup.get("start_seed",0))
	while homes.size()<order.size():
		var player_id:=order[homes.size()]
		var best_cell:=-1
		var best_score:=-INF
		for cell: PlanetCell in grid.cells:
			if cell.id in homes: continue
			var minimum:=grid.get_cell_count() if homes.is_empty() else 2147483647
			# Keep the selected home as the traversal origin so PlanetGrid's bounded
			# distance cache performs one BFS per home instead of one per candidate.
			for home: int in homes: minimum=mini(minimum,grid.distance(home,cell.id))
			var local_score:=_start_suitability_value(suitability,player_id,cell.id)
			var tie_break:=float(posmod(cell.id*1103515245+start_seed,104729))/104729000.0
			var score:=float(minimum)*100.0+local_score*10.0+tie_break
			if score>best_score:
				best_score=score; best_cell=cell.id
		if best_cell<0: break
		homes.append(best_cell)
	return homes

func _start_suitability_value(values: Dictionary,player_id: int,cell_id: int) -> float:
	var row: Variant=values.get(player_id,values.get(str(player_id),[]))
	if row is Array and cell_id<(row as Array).size(): return float((row as Array)[cell_id])
	if row is PackedFloat32Array and cell_id<(row as PackedFloat32Array).size(): return float((row as PackedFloat32Array)[cell_id])
	return 0.0

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

func combat_target(target_id: int) -> RefCounted:
	if units.has(target_id): return units[target_id]
	if structures.has(target_id): return structures[target_id]
	return world_sites.get(target_id) as WorldSiteState

func relationship_for_site(player_id: int,site: WorldSiteState) -> RelationshipState.Kind:
	if site.controller_id>0 and relationships.is_site_hostile(player_id,site.controller_id,site.id): return RelationshipState.Kind.HOSTILE
	return relationships.between(player_id,site.controller_id) if site.controller_id>0 else RelationshipState.Kind.NEUTRAL

func entities_are_hostile(a: RefCounted,b: RefCounted) -> bool:
	if a is Unit and a.home_site_id>=0 and players.has(b.controller_id):
		return relationships.is_site_hostile(b.controller_id,a.controller_id,a.home_site_id)
	if b is Unit and b.home_site_id>=0 and players.has(a.controller_id):
		return relationships.is_site_hostile(a.controller_id,b.controller_id,b.home_site_id)
	if a is WorldSiteState and players.has(b.controller_id): return relationship_for_site(b.controller_id,a)==RelationshipState.Kind.HOSTILE
	if b is WorldSiteState and players.has(a.controller_id): return relationship_for_site(a.controller_id,b)==RelationshipState.Kind.HOSTILE
	return relationships.is_hostile(a.controller_id,b.controller_id)

func provoke_village(player_id: int,site_id: int) -> void:
	if not world_sites.has(site_id): return
	var site: WorldSiteState=world_sites[site_id]
	var definition:=registry.world_site(site.definition_id)
	if definition==null or definition.category!="village": return
	relationships.set_site_hostile(player_id,site.controller_id,site.id)
	var hostile: Dictionary=site.runtime_state.get("hostile_players",{})
	hostile[player_id]=true; site.runtime_state.hostile_players=hostile
	public_events.append({"kind":"village_hostile","site_id":site.id,"player_id":player_id,"round":round_number})

func provoke_village_for_target(player_id: int,target: RefCounted) -> void:
	if target is WorldSiteState: provoke_village(player_id,target.id)
	elif target is Unit and target.home_site_id>=0: provoke_village(player_id,target.home_site_id)

func player_can_attack_target(player_id: int,target: RefCounted) -> bool:
	if not players.has(player_id) or target==null or target.hp<=0: return false
	if target is WorldSiteState:
		var definition:=registry.world_site(target.definition_id)
		return definition!=null and definition.category=="village" and not target.runtime_state.get("destroyed",false)
	if not (target is Unit or target is Structure) or target.controller_id==player_id: return false
	var relationship:=relationships.between(player_id,target.controller_id)
	return relationship!=RelationshipState.Kind.SELF and relationship!=RelationshipState.Kind.ALLIED

func provoke_attack_target(player_id: int,target: RefCounted) -> void:
	if target==null or not players.has(player_id): return
	if target is WorldSiteState or (target is Unit and target.home_site_id>=0):
		provoke_village_for_target(player_id,target); return
	if target.controller_id>0 and relationships.between(player_id,target.controller_id)==RelationshipState.Kind.NEUTRAL:
		relationships.set_relationship(player_id,target.controller_id,RelationshipState.Kind.HOSTILE)
		public_events.append({"kind":"controller_provoked","controller_id":target.controller_id,"player_id":player_id,"round":round_number})

func destroy_world_site(site_id: int,attacker_id: int=0) -> void:
	if not world_sites.has(site_id): return
	var site: WorldSiteState=world_sites[site_id]
	site.hp=0; site.runtime_state.destroyed=true; site.runtime_state.loot_available=true
	site.runtime_state.destroyed_by=attacker_id
	public_events.append({"kind":"site_destroyed","site_id":site.id,"attacker_id":attacker_id,"round":round_number})

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

func is_water_cell(cell_id: int) -> bool: return bool(water_cells.get(cell_id,false))

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
	site.max_hp=definition.max_hp; site.hp=definition.max_hp
	site.runtime_state={"remaining_charges":definition.initial_charges,"exhausted":false,
		"regeneration_remaining":0,"explored":false,"trade_usage":{},"destroyed":false,
		"loot_available":false,"loot_claimed":false,"hostile_players":{}}
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
			unit.neutral_allegiance_id=String(record.get("neutral_allegiance_id",""))
			if int(record.get("site_cell_id",-1))>=0:
				var home_site:=site_at(int(record.site_cell_id)); unit.home_site_id=home_site.id if home_site!=null else -1
			if "village_guard" in registry.unit(unit.definition_id).tags:
				unit.neutral_leash_distance=5
				if world_sites.has(unit.home_site_id): unit.neutral_home_cell=world_sites[unit.home_site_id].cell_id
			units[entity_id]=unit
		group_instance+=1
	turn_state.neutral_phase_enabled=not result.neutral_group_records.is_empty()
	turn_state.begin_initial_enemy_phase()
	if turn_state.neutral_phase: prepare_neutral_actions()
	_calculate_start_diagnostics()
	refresh_visibility()

func clear_population() -> void:
	_village_leash_cells.clear()
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

func is_player_alive(controller_id: int) -> bool:
	return players.has(controller_id) and not players[controller_id].eliminated

func alive_player_ids() -> Array[int]:
	var result: Array[int]=[]
	for controller_id: int in players:
		if is_player_alive(controller_id): result.append(controller_id)
	result.sort(); return result

func has_survival_anchor(controller_id: int) -> bool:
	for unit: Unit in units.values():
		var definition:=registry.unit(unit.definition_id)
		if unit.controller_id==controller_id and unit.hp>0 and definition!=null and "headquarters" in definition.tags: return true
	for structure: Structure in structures.values():
		var definition:=registry.structure(structure.definition_id)
		if structure.controller_id==controller_id and structure.hp>0 and definition!=null and "headquarters" in definition.tags: return true
	return false

func evaluate_player_survival(controller_id: int,reason: String="Headquarters lost") -> bool:
	if not players.has(controller_id) or players[controller_id].eliminated or has_survival_anchor(controller_id): return false
	eliminate_player(controller_id,reason)
	return true

func eliminate_player(controller_id: int,reason: String="Eliminated") -> void:
	if not players.has(controller_id) or players[controller_id].eliminated: return
	var player: PlayerState=players[controller_id]
	player.eliminated=true; player.elimination_round=round_number; turn_state.set_eliminated(controller_id)
	for unit_id: int in combat_orders.intents.keys().duplicate():
		if combat_orders.intents[unit_id].controller_id==controller_id: combat_orders.intents.erase(unit_id)
	var removed_units: Array[int]=[]
	for unit: Unit in units.values():
		if unit.controller_id==controller_id: removed_units.append(unit.id)
	for unit_id: int in removed_units: remove_unit(unit_id,false)
	var removed_structures: Array[int]=[]
	for structure: Structure in structures.values():
		if structure.controller_id==controller_id: removed_structures.append(structure.id)
	for structure_id: int in removed_structures: remove_structure(structure_id)
	living_migration.roads.erase(controller_id)
	baumeister.origin_pillars.erase(controller_id)
	for district_id: int in baumeister.districts.keys():
		if baumeister.districts[district_id].controller_id==controller_id: baumeister.districts.erase(district_id)
	for bridge_id: int in baumeister.bridges.keys():
		if baumeister.bridges[bridge_id].controller_id==controller_id: baumeister.bridges.erase(bridge_id)
	add_public_event("player_eliminated",{"player_id":controller_id,"player_name":player.player_name,"reason":reason})
	var alive:=alive_player_ids()
	if alive.size()==1 and players.size()>=NetworkProtocol.MIN_PLAYERS:
		winner_id=alive[0]; turn_state.neutral_phase=false
		add_public_event("match_won",{"player_id":winner_id,"player_name":players[winner_id].player_name,
			"faction_id":players[winner_id].faction_id,"round":round_number,"duration_seconds":match_duration_seconds()})
	elif active_player==controller_id:
		advance_turn()
	refresh_visibility()

func set_player_connected(controller_id: int,value: bool) -> void:
	if players.has(controller_id): players[controller_id].connected=value

func add_public_event(event_type: String,data: Dictionary={}) -> void:
	var event:=data.duplicate(true); event.type=event_type; event.round=round_number; event.serial=turn_state.serial
	public_events.append(event)
	if public_events.size()>32: public_events.pop_front()

func match_duration_seconds() -> int:
	return maxi(0,int((Time.get_ticks_msec()-match_started_msec)/1000))

func _calculate_start_diagnostics() -> void:
	start_diagnostics.clear()
	for player_id: int in starting_cells:
		var start_cell: int=starting_cells[player_id]
		var nearest:=2147483647
		for opponent_id: int in starting_cells:
			if opponent_id!=player_id: nearest=mini(nearest,grid.distance(start_cell,starting_cells[opponent_id]))
		var nearby_sites:=0; var hostile_strength:=0
		for site: WorldSiteState in world_sites.values(): nearby_sites+=int(grid.distance(start_cell,site.cell_id)<=4)
		for unit: Unit in units.values():
			if controllers.has(unit.controller_id) and controllers[unit.controller_id].kind==ControllerState.NEUTRAL_AI and relationships.is_hostile(player_id,unit.controller_id) and grid.distance(start_cell,unit.cell_id)<=5:
				hostile_strength+=maxi(1,unit.attack_damage)
		var suitability:=_start_suitability_value(setup.get("start_suitability",{}),player_id,start_cell)
		start_diagnostics[player_id]={"start_cell":start_cell,"nearest_opponent_distance":nearest,
			"local_terrain_suitability":suitability,"nearby_site_count":nearby_sites,"nearby_hostile_neutral_strength":hostile_strength}

func start_turn() -> Array[int]:
	var started: Array[int]=[]
	if winner_id!=0 or turn_state.phase!=TurnState.MANAGEMENT: return started
	var controller_ids: Array[int]=[]
	if turn_state.simultaneous_player_turns_enabled and turn_state.simultaneous_stage_started: controller_ids=turn_state.simultaneous_player_ids()
	else: controller_ids.append(active_player)
	for controller_id: int in controller_ids:
		if int(started_controller_rounds.get(controller_id,0))==round_number: continue
		started_controller_rounds[controller_id]=round_number; started.append(controller_id)
		if players.has(controller_id):
			var player: PlayerState=players[controller_id]
			player.add_resources(registry.faction(player.faction_id).turn_resource_income)
			_process_unit_economy_and_status(controller_id,player)
		for unit: Unit in units.values():
			if unit.controller_id==controller_id:
				unit.moved=false; unit.attacked=false; unit.road_segments_built_this_turn=0; unit.ready_next_turn=false
		for structure: Structure in structures.values():
			if structure.controller_id==controller_id: structure.recruit_available=true
		_process_designations(controller_id)
	last_started_turn=turn_state.serial
	return started

func advance_turn(controller_id: int=-1) -> int:
	turn_state.advance_controller(active_player if controller_id<0 else controller_id)
	process_round_boundary()
	start_turn()
	refresh_visibility()
	return active_player

func process_round_boundary() -> void:
	if (turn_state.index==0 or (turn_state.simultaneous_player_turns_enabled and turn_state.neutral_phase)) and living_migration.last_regrowth_round<turn_state.round_number:
		living_migration.last_regrowth_round=turn_state.round_number
		for terrain_state: TerrainConsumptionState in living_migration.terrain.values(): terrain_state.advance()
		_process_world_site_regeneration()

func prepare_neutral_actions() -> void:
	for unit: Unit in units.values():
		if controllers.has(unit.controller_id) and controllers[unit.controller_id].kind==ControllerState.NEUTRAL_AI:
			unit.moved=false; unit.attacked=false; unit.road_segments_built_this_turn=0; unit.ready_next_turn=false

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
	var structure_upkeep: Dictionary[String,int]={}
	var expired: Array[int]=[]
	var owned_units: Array[Unit]=[]
	for unit: Unit in units.values():
		if unit.controller_id!=controller_id: continue
		owned_units.append(unit)
	owned_units.sort_custom(func(a: Unit,b: Unit)->bool: return a.id<b.id)
	for unit: Unit in owned_units:
		var definition:=registry.unit(unit.definition_id)
		if unit.upkeep_paid:
			for resource_id: String in definition.turn_production:
				production[resource_id]=production.get(resource_id,0)+definition.turn_production[resource_id]
		if unit.spider_state!=null and unit.upkeep_paid:
			var faction:=registry.faction(player.faction_id)
			if faction.gameplay_config is LivingMigrationConfig:
				var config:=faction.gameplay_config as LivingMigrationConfig
				var food_per:=config.food_per_food_building+(config.improved_food_building_bonus if _has_unlock_tag(player,"abundant_organs") else 0)
				production["food"]=production.get("food",0)+config.spider_food_production+unit.spider_state.building_count("food_production")*food_per
				production["silk"]=production.get("silk",0)+config.spider_silk_production+(config.improved_spider_silk_bonus if _has_unlock_tag(player,"silk_glands") else 0)
				var synapse_per:=config.synapse_per_synapse_building
				if _has_unlock_tag(player,"synapse_improvement"): synapse_per+=config.improved_synapse_building_bonus
				production["synapse"]=production.get("synapse",0)+unit.spider_state.building_count("synapse_production")*synapse_per
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
			structure_upkeep[resource_id]=structure_upkeep.get(resource_id,0)+structure_definition.upkeep[resource_id]
	for district: DistrictState in baumeister.districts.values():
		if district.controller_id!=controller_id or not district.completed: continue
		var district_definition:=registry.district(district.definition_id)
		if district.maintenance_paid:
			var district_bonus:=0
			if _has_unlock_tag(player,"district_specialization") and not district_definition.turn_production.is_empty():
				var faction:=registry.faction(player.faction_id)
				if faction.gameplay_config is BaumeisterConfig: district_bonus=(faction.gameplay_config as BaumeisterConfig).district_production_bonus
			for resource_id: String in district_definition.turn_production:
				production[resource_id]=production.get(resource_id,0)+district_definition.turn_production[resource_id]+district_bonus
	player.add_resources(production)
	var unpaid: Dictionary[String,int]={}
	for resource_id: String in structure_upkeep:
		var paid:=mini(player.resource_amount(resource_id),structure_upkeep[resource_id])
		player.resources[resource_id]=player.resource_amount(resource_id)-paid
		if paid<structure_upkeep[resource_id]: unpaid[resource_id]=unpaid.get(resource_id,0)+structure_upkeep[resource_id]-paid
	for unit: Unit in owned_units:
		var unit_upkeep:=registry.unit(unit.definition_id).upkeep
		unit.upkeep_paid=player.can_afford(unit_upkeep)
		if unit.upkeep_paid: player.apply_cost(unit_upkeep)
		else:
			for resource_id: String in unit_upkeep: unpaid[resource_id]=unpaid.get(resource_id,0)+unit_upkeep[resource_id]
	var owned_districts: Array[DistrictState]=[]
	for district: DistrictState in baumeister.districts.values():
		if district.controller_id==controller_id and district.completed: owned_districts.append(district)
	owned_districts.sort_custom(func(a: DistrictState,b: DistrictState)->bool: return a.id<b.id)
	for district: DistrictState in owned_districts:
		var district_upkeep:=registry.district(district.definition_id).upkeep
		district.maintenance_paid=player.can_afford(district_upkeep)
		if district.maintenance_paid: player.apply_cost(district_upkeep)
		else:
			for resource_id: String in district_upkeep: unpaid[resource_id]=unpaid.get(resource_id,0)+district_upkeep[resource_id]
	living_migration.unpaid_upkeep[controller_id]=unpaid
	for unit_id: int in expired: remove_unit(unit_id,true)

func _has_unlock_tag(player: PlayerState,tag: String) -> bool:
	for technology_id: String in player.research.completed_ids:
		var technology:=registry.technology(technology_id)
		if technology!=null and tag in technology.unlock_tags: return true
	return false

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
