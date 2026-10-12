extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func _run() -> void:
	var previous_flat:=0.0
	for level in [3,4,5]:
		var grid:=PlanetGrid.new(level,12.0*pow(2.0,level-3))
		var recipe:=PlanetGenerationConfig.new(); recipe.terraced_terrain=true; recipe.world_seed=772211
		var world:=GeneratedPlanet.generate(grid,recipe,false)
		var flat:=0
		for cell: PlanetCell in grid.cells: flat+=int(not world.terraces.is_ramp(cell.id))
		var fraction:=float(flat)/grid.cells.size()
		print("FLATLAND level=",level," flat_percent=",fraction*100.0," range_frequency=",world.terraces.range_frequency)
		check(fraction>previous_flat,"Larger planets contain a greater proportion of flat tiles"); previous_flat=fraction
		check(fraction>0.5,"Flat tiles are the majority at every supported size")
		var config:=WorldPopulationConfig.from_preset(WorldPopulationConfig.OFF); config.player_count=2; config.villages_per_player=2
		var result:=WorldPopulationGenerator.generate(world,ContentRegistry.default(),config)
		var villages:=0
		for record: Dictionary in result.site_records:
			if record.definition_id=="village": villages+=1; check(not world.terraces.is_ramp(record.cell_id),"Village spawns only on a flat tile")
		check(villages==4,"Flatland generation still supplies the requested villages")
	var grid:=PlanetGrid.new(3)
	var state:=GameState.new(grid); state.units.clear(); state.structures.clear()
	var home:=state.add_world_site("village",0,53)
	state.controllers[53]=ControllerState.new(53,ControllerState.NEUTRAL_AI,"")
	state.turn_state.neutral_phase=true
	var ring:=grid.breadth_first(home.cell_id,6); var inside:=-1; var outside:=-1
	for cell_id: int in ring.order:
		if ring.costs[cell_id]!=5: continue
		for neighbor: int in grid.get_neighbors(cell_id):
			if ring.costs.get(neighbor,-1)==6: inside=cell_id; outside=neighbor; break
		if inside>=0: break
	for id: String in ["villager","knight_of_the_land"]:
		state.units.clear()
		var guard:=GameState.Unit.new(200,53,id,inside,2,state.registry); guard.home_site_id=home.id; guard.neutral_home_cell=home.cell_id; state.units[guard.id]=guard
		var rules:=GameRules.new(state)
		check(not rules.try_move(53,guard.id,outside).success,"Authoritative movement rejects a village defender crossing radius five")
		for destination: int in rules.reachable(53,guard.id):
			var path:=rules.path_to(53,guard.id,destination)
			for step: int in path: check(grid.distance(home.cell_id,step)<=5,"Every path step remains inside the home village leash")
		guard.neutral_awareness_range=4; guard.neutral_leash_distance=5
		for action: Dictionary in NeutralAI.new().choose_actions(state,53):
			if action.type=="move": check(grid.distance(home.cell_id,action.dest)<=5,"Neutral AI remains in its own village radius")
	check(state.registry.unit("villager").squad_size==7,"Villager squads contain seven members")
	var positions:={}
	for index in range(7): positions[EntityView._formation_offset(index,7)]=true
	check(positions.size()==7,"All seven squad positions are distinct")
	var mapping:=VisualMap.new()
	for id: String in ["villager","knight_of_the_land"]: check(mapping.model_definition(id)!=null and mapping.asset_scene(id)!=null,"Supplied defender asset is mapped: "+id)
	print("Village flatlands checks complete; failures=",failures); quit(0 if failures==0 else 1)
