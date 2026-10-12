extends SceneTree

var failures:=0
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(message)

func generated(seed: int,players: int,villages_per_player: int) -> Dictionary:
	var grid:=PlanetGrid.new(3)
	var recipe:=PlanetGenerationConfig.new(); recipe.world_seed=seed; recipe.region_count=12; recipe.minimum_region_size=2
	var world:=GeneratedPlanet.generate(grid,recipe,false)
	var config:=WorldPopulationConfig.from_preset(WorldPopulationConfig.STANDARD)
	config.player_count=players; config.villages_per_player=villages_per_player
	config.start_cells=[0,grid.breadth_first(0).order[-1]]
	return {"grid":grid,"world":world,"config":config,"result":WorldPopulationGenerator.generate(world,ContentRegistry.default(),config)}

func test_road_topology_and_refresh() -> void:
	var grid:=PlanetGrid.new(2); var pentagon:=-1; var hexagon:=-1
	for cell: PlanetCell in grid.cells:
		if cell.is_pentagon and pentagon<0: pentagon=cell.id
		elif not cell.is_pentagon and hexagon<0: hexagon=cell.id
	for cell_id: int in [pentagon,hexagon]:
		var across: Array[int]=[]
		for edge in range(grid.get_cell(cell_id).polygon_vertices.size()): across.append(grid.neighbor_across_edge(cell_id,edge))
		var unique:=across.duplicate(); unique.sort()
		check(-1 not in across and unique.size()==grid.get_neighbors(cell_id).size(),"Every pentagon/hexagon edge resolves its actual neighbor")
	var overlay:=AntRoadOverlay.new(); overlay.grid=grid; overlay.world_seed=91
	overlay.visible_roads={pentagon:1,grid.get_neighbors(pentagon)[0]:1}
	var record:=overlay.connection_record(pentagon)
	check(record.connected_neighbors.size()==1 and record.exposed_edges.size()==4,"Pentagon road opens one connector and borders four exposed edges")
	overlay.visible_roads={hexagon:1,grid.get_neighbors(hexagon)[0]:1,grid.get_neighbors(hexagon)[1]:1}
	record=overlay.connection_record(hexagon)
	check(record.connected_neighbors.size()==2 and record.exposed_edges.size()==4,"Hex road connectivity is procedural")
	var recipe:=PlanetGenerationConfig.new(); recipe.world_seed=91
	var world:=GeneratedPlanet.generate(grid,recipe,false); var surface:=TerrainSurfaceSampler.new(world,TerrainRenderConfig.new())
	overlay.configure(grid,surface,91); overlay.visible_roads.clear(); overlay.sync_roads({hexagon:1})
	var neighbor:=grid.get_neighbors(hexagon)[0]; overlay.sync_roads({hexagon:1,neighbor:1})
	check(hexagon in overlay.last_refreshed_cells and neighbor in overlay.last_refreshed_cells,"Adding a road locally refreshes it and its connected neighbor")
	check(overlay.cell_views.has(hexagon) and overlay.cell_views.has(neighbor),"Painted road geometry builds without gameplay dependencies")
	var mesh: ArrayMesh=(overlay.cell_views[hexagon].get_node("Dirt") as MeshInstance3D).mesh
	var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(not vertices.is_empty() and vertices[0].normalized().dot(grid.get_cell(hexagon).up)>0.98,"Road mesh follows spherical terrain orientation")
	overlay.free()

func test_village_generation() -> void:
	var first:=generated(772211,4,2); var repeated:=generated(772211,4,2)
	var villages: Array[Dictionary]=[]
	for record: Dictionary in first.result.site_records:
		if record.definition_id=="village": villages.append(record)
	check(first.result.site_records==repeated.result.site_records,"Village generation is deterministic")
	check(villages.size()==8,"Default target is two villages per player")
	var cells: Array=[]
	for village: Dictionary in villages:
		check(not first.world.get_cell(village.cell_id).hydrology or first.world.get_cell(village.cell_id).hydrology.surface_water_type==HydrologyCellData.SurfaceWater.NONE,"Village uses valid dry terrain")
		for start: int in first.config.start_cells: check(first.grid.distance(village.cell_id,start)>=first.config.village_start_distance,"Village respects start exclusions")
		for other: int in cells: check(first.grid.distance(village.cell_id,other)>=first.config.village_spacing,"Villages respect spacing")
		cells.append(village.cell_id)
	var off:=generated(772211,4,0); var off_count:=0
	for record: Dictionary in off.result.site_records: off_count+=int(record.definition_id=="village")
	check(off_count==0,"Village setting zero produces no villages")
	var state:=GameState.new(first.grid,{"simultaneous_combat":false}); state.apply_population(first.result)
	var knight_counts: Dictionary={}
	for unit: GameState.Unit in state.units.values():
		if unit.definition_id=="knight_of_the_land": knight_counts[unit.home_site_id]=int(knight_counts.get(unit.home_site_id,0))+1
	for site: WorldSiteState in state.world_sites.values():
		if site.definition_id=="village": check(knight_counts.get(site.id,0)==1,"Every generated village has exactly one Knight of the Land")

func village_fixture() -> Dictionary:
	var state:=GameState.new(PlanetGrid.new(1),{"faction_ids":["living_migration","baumeister"],"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_combat":false})
	var player_unit: GameState.Unit=state.units[2]
	var cell:=-1
	for candidate: int in state.grid.get_neighbors(player_unit.cell_id):
		if not state.is_cell_blocked(candidate): cell=candidate; break
	state.controllers[53]=ControllerState.new(53,ControllerState.NEUTRAL_AI,"")
	state.relationships.set_relationship(1,53,RelationshipState.Kind.NEUTRAL); state.relationships.set_relationship(2,53,RelationshipState.Kind.NEUTRAL)
	var site:=state.add_world_site("village",cell,53)
	var guard_cell:=-1
	for candidate: int in state.grid.get_neighbors(cell):
		if not state.is_cell_blocked(candidate) and candidate!=player_unit.cell_id: guard_cell=candidate; break
	var guard:=GameState.Unit.new(state.allocate_id(),53,"villager",guard_cell,-1,state.registry)
	guard.home_site_id=site.id; guard.neutral_home_cell=cell; guard.neutral_leash_distance=3; guard.neutral_awareness_range=4; guard.neutral_allegiance_id="free_villages"; state.units[guard.id]=guard
	state.refresh_visibility()
	return {"state":state,"rules":GameRules.new(state),"site":site,"unit":player_unit,"guard":guard}

func test_village_interaction_and_allegiance() -> void:
	var fixture:=village_fixture(); var state: GameState=fixture.state; var rules: GameRules=fixture.rules
	var site: WorldSiteState=fixture.site; var unit: GameState.Unit=fixture.unit; var guard: GameState.Unit=fixture.guard
	var offers:=rules.available_site_interactions(1,site.id)
	check(offers.size()==1 and offers[0].id=="food_for_silk","Peaceful village exposes faction-compatible trade")
	var food:=state.players[1].resource_amount("food"); var silk:=state.players[1].resource_amount("silk")
	check(rules.try_site_interaction(1,site.id,"food_for_silk",unit.id).success and state.players[1].resource_amount("food")==food-4 and state.players[1].resource_amount("silk")==silk+2,"Village trade is authoritative")
	unit.attacked=false; unit.moved=false; state.players[1].resources.food=food
	check(not rules.try_site_interaction(1,site.id,"food_for_silk",unit.id).success,"Village trade respects its per-turn usage limit")
	unit.attacked=false; unit.moved=false; state.players[1].resources.food=0
	check(not rules.try_site_interaction(1,site.id,"food_for_silk",unit.id).success,"Insufficient village trade resources are rejected")
	unit.attacked=false; unit.moved=false
	check(rules.try_attack(1,unit.id,guard.id).success and state.relationships.is_site_hostile(1,53,site.id),"Attacking a villager provokes its home village")
	check(not state.relationships.is_hostile(1,53),"Village hostility remains scoped instead of becoming planet-wide")
	var second:=state.add_world_site("village",state.grid.breadth_first(site.cell_id).order[-1],53)
	check(state.relationship_for_site(1,second)==RelationshipState.Kind.NEUTRAL,"A separate allied village remains neutral")
	var allied_guard:=GameState.Unit.new(state.allocate_id(),53,"knight_of_the_land",state.grid.get_neighbors(second.cell_id)[0],-1,state.registry)
	allied_guard.home_site_id=second.id
	check(not state.entities_are_hostile(guard,allied_guard),"Villagers and Knights across villages share friendly allegiance")
	state.turn_state.neutral_phase=true
	check(not NeutralAI.new().choose_actions(state,53).is_empty(),"Hostile village defenders respond inside their leash")

	state.turn_state.neutral_phase=false; unit.attacked=false; unit.moved=false; state.refresh_visibility()
	site.hp=unit.attack_damage
	check(rules.try_attack(1,unit.id,site.id).success and site.runtime_state.destroyed,"Village destruction uses standard unit damage")
	unit.attacked=false; unit.moved=false
	check(rules.available_site_interactions(1,site.id).size()==1 and rules.available_site_interactions(1,site.id)[0].id==SiteRules.CLAIM_LOOT,"Destroyed village replaces trade with loot")
	var loot_food:=state.players[1].resource_amount("food")
	check(rules.try_site_interaction(1,site.id,SiteRules.CLAIM_LOOT,unit.id).success and state.players[1].resource_amount("food")==loot_food+8,"Village loot is faction-compatible and claimable once")
	unit.attacked=false; unit.moved=false
	check(not rules.try_site_interaction(1,site.id,SiteRules.CLAIM_LOOT,unit.id).success,"Village loot cannot be duplicated")
	check(rules.available_site_interactions(1,site.id).is_empty(),"Destroyed village never trades again")

func test_fog_and_authority() -> void:
	var fixture:=village_fixture(); var state: GameState=fixture.state; var site: WorldSiteState=fixture.site
	var snapshot:=ObservationCodec.encode(state,1,1)
	var seen:=false
	for row: Dictionary in snapshot.observed_sites: seen=seen or int(row.id)==site.id
	check(seen,"Discovered villages synchronize through permitted site observations")
	var far:=state.add_world_site("village",state.grid.breadth_first(site.cell_id).order[-1],53); state.refresh_visibility()
	snapshot=ObservationCodec.encode(state,1,2); seen=false
	for row: Dictionary in snapshot.observed_sites: seen=seen or int(row.id)==far.id
	check(not seen,"Undiscovered villages are absent from client snapshots")
	var dispatcher:=CommandDispatcher.new(state,fixture.rules); dispatcher.register_peer(101,1)
	var unit: GameState.Unit=fixture.unit; unit.attacked=false; unit.moved=false
	var response:=dispatcher.dispatch(101,GameplayCommand.create(1,CommandDispatcher.SITE_INTERACTION,{"site_id":site.id,"interaction_id":"food_for_silk","unit_id":unit.id}))
	check(response.accepted,"Host command dispatch owns village trade")
	unit.attacked=false; unit.moved=false; site.hp=unit.attack_damage
	response=dispatcher.dispatch(101,GameplayCommand.create(2,CommandDispatcher.ATTACK,{"attacker_id":unit.id,"target_id":site.id}))
	check(response.accepted and site.runtime_state.destroyed,"Host command dispatch owns village destruction")
	unit.attacked=false; unit.moved=false
	response=dispatcher.dispatch(101,GameplayCommand.create(3,CommandDispatcher.SITE_INTERACTION,{"site_id":site.id,"interaction_id":SiteRules.CLAIM_LOOT,"unit_id":unit.id}))
	check(response.accepted,"Host command dispatch owns village loot")
	unit.attacked=false; unit.moved=false
	response=dispatcher.dispatch(101,GameplayCommand.create(4,CommandDispatcher.SITE_INTERACTION,{"site_id":site.id,"interaction_id":SiteRules.CLAIM_LOOT,"unit_id":unit.id}))
	check(not response.accepted,"Authoritative command path prevents duplicate village loot")

func _init() -> void:
	test_road_topology_and_refresh(); test_village_generation(); test_village_interaction_and_allegiance(); test_fog_and_authority()
	print("Milestone 22 checks: %d; failures=%d" % [checks,failures])
	quit(1 if failures else 0)
