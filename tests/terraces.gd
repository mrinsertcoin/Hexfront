extends SceneTree
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func _run() -> void:
	var grid:=PlanetGrid.new(3)
	for seed_value in [48293617,42,-731]:
		for preset: String in ["None","Rare","Experimental"]:
			var terrain:=TerracedTerrain.generate(grid,seed_value,preset)
			var counts:={}
			for level: int in terrain.levels: counts[level]=true
			check(counts.size()==4,"Every seed has four terrace levels")
			for cell: PlanetCell in grid.cells:
				for neighbor: int in cell.neighbor_ids: check(absi(terrain.levels[cell.id]-terrain.levels[neighbor])<=1,"No multi-level jumps")
			check(is_equal_approx(terrain.elevation_step/terrain.ramp_run,tan(deg_to_rad(35.0))),"Ramps use the steeper fixed 35-degree rise/run angle")
			check(terrain.elevation_step>0.60,"Elevation layers remain visibly separated at the normal tile scale")
			check(terrain.ramp_run<grid.cells[0].up.distance_to(grid.cells[grid.cells[0].neighbor_ids[0]].up)*grid.planet_radius,"Ramp transition fits inside a tile")
			check(grid.breadth_first(0,-1,{},terrain.blocked_edges).order.size()==grid.cells.size(),"Cliffs preserve global ground connectivity")
			if preset=="None": check(terrain.blocked_edges.is_empty(),"None produces no cliffs")
			if preset=="Rare": check(terrain.blocked_edges.size()<terrain.boundaries.size()*0.10,"Default cliffs are rare")
			check(terrain.fingerprint==TerracedTerrain.generate(grid,seed_value,preset).fingerprint,"Terrain and cliffs reproduce deterministically")
	var terrain:=TerracedTerrain.generate(grid,42,"Experimental")
	check(not terrain.blocked_edges.is_empty(),"Experimental fixture has cliffs")
	var edge: Vector2i=terrain.blocked_edges.keys()[0]
	var state:=GameState.new(grid,{"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_combat":false})
	state.terrain=terrain; state.units.clear(); state.structures.clear()
	var walker:=GameState.Unit.new(1,1,"prototype_infantry",edge.x,1,state.registry); state.units[1]=walker
	state.refresh_visibility(); var rules:=GameRules.new(state)
	check(not rules.try_move(1,1,edge.y).success,"Ground movement cannot cross a cliff")
	state.units.clear(); var flier:=GameState.Unit.new(2,1,"dragonfly",edge.x,1,state.registry); state.units[2]=flier; state.refresh_visibility()
	check(rules.try_move(1,2,edge.y).success,"Flying units can cross cliff edges")
	var config:=MatchConfig.new(); config.cliff_generation="None"
	check(config.copy().cliff_generation=="None" and MatchConfig.from_network_dictionary(config.public_network_dictionary()).cliff_generation=="None","Cliff setting survives copying and network setup")
	var app:=AppController.new(); root.add_child(app); await process_frame
	app.show_match_setup()
	check(app.setup_cliffs.item_count==6 and app.setup_cliffs.get_item_text(app.setup_cliffs.selected)=="Rare","Advanced setup exposes the full None-to-Experimental range with Rare as default")
	app.setup_cliffs.select(0)
	check(app.setup_config().cliff_generation=="None","Advanced selection enters the actual match configuration")
	app.show_host_setup()
	check(app.network_cliffs.item_count==6,"Host setup exposes the same terrain controls")
	app.free()
	print("Terraces checks complete; failures=",failures); quit(0 if failures==0 else 1)
