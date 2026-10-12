extends SceneTree
## Repeatable real-board load and busy-world benchmark; run without --headless for GPU timings.
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func mark(label: String,started: int) -> void:
	print("PERF %s ms=%.1f memory_mb=%.1f nodes=%d" % [label,(Time.get_ticks_usec()-started)/1000.0,Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
func _run() -> void:
	var disposable:=GameState.new(PlanetGrid.new(0))
	var released: WeakRef=weakref(disposable); disposable=null
	check(released.get_ref()==null,"Leaving a match releases state rather than retaining a visibility ownership cycle")
	if "--board" in OS.get_cmdline_user_args():
		await profile_board(); return
	var level:=5 if "--medium" in OS.get_cmdline_user_args() else 3
	var started:=Time.get_ticks_usec()
	var grid:=PlanetGrid.new(level,48.0 if level==5 else 12.0); mark("grid",started)
	started=Time.get_ticks_usec()
	var world:=GeneratedPlanet.generate(grid,PlanetGenerationConfig.new(),false); mark("world",started)
	var config:=TerrainRenderConfig.new(); config.terrain_subdivision_level=5
	var renderer:=PlanetTerrainRenderer.new(); root.add_child(renderer)
	started=Time.get_ticks_usec(); renderer.rebuild(world,config); mark("terrain_and_dressing",started)
	started=Time.get_ticks_usec()
	var rng:=RandomNumberGenerator.new(); rng.seed=919
	for i in range(1000):
		var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		var cell_id:=grid.find_cell(direction)
		check(grid.contains(cell_id) and grid.cells[cell_id].contains_direction(direction),"Indexed lookup returns the containing polygon")
	mark("1000_cell_queries",started)
	for i in range(100):
		var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		var best:=0; var score:=-INF
		for cell: PlanetCell in grid.cells:
			var dot:=direction.dot(cell.up)
			if dot>score: score=dot; best=cell.id
		var indexed:=int(grid._nearest_cell(grid._spatial_root,direction,0,Vector2(-INF,0)).y)
		check(indexed==best,"Spatial nearest query agrees with exhaustive lookup")
	check(renderer.triangle_count==20480,"Terrain retains authored visual resolution")
	check(Performance.get_monitor(Performance.MEMORY_STATIC)<512*1048576.0,"Terrain and scenery fit the tracked 512 MB memory budget")
	renderer.free()
	print("Planet performance checks complete; failures=",failures)
	quit(0 if failures==0 else 1)

func profile_board() -> void:
	root.size=Vector2i(1280,720)
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.MEDIUM
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	var board:=load("res://scenes/game.tscn").instantiate() as PlanetBoard
	board.configure_match(config,UserSettings.new())
	var started:=Time.get_ticks_usec(); root.add_child(board); mark("medium_board_load",started)
	board._ai_token+=1; board._ai_running=false; board.set_process(false)
	await process_frame; await process_frame
	var added:=0
	for cell: PlanetCell in board.grid.cells:
		if board.game_state.is_cell_blocked(cell.id): continue
		var definition_id: String=["worker_ant","fighter_ant","prototype_scout"][added%3]
		var unit:=GameState.Unit.new(board.game_state.allocate_id(),1,definition_id,cell.id,-1,board.game_state.registry)
		board.game_state.units[unit.id]=unit; added+=1
		if added>=300: break
	started=Time.get_ticks_usec(); board.game_state.refresh_visibility(); board._refresh_display(); mark("300_units_refresh",started)
	check(board.unit_views.size()>=300,"Busy board retains all logical units")
	check(board.debug_outlines.mesh==null and board.debug_centers.mesh==null,"Debug geometry is deferred until requested")
	board.navigation.reset(board.grid.cells[board.game_state.units[1].cell_id].up)
	board._update_entity_rendering()
	var culled:=0
	for view: EntityView in board.unit_views.values():
		if not view._render_active: culled+=1
	check(culled>0,"The busy world culls units behind the solid globe")
	for _frame in range(30):
		board._process(1.0/60.0); await process_frame
	var samples: Array[float]=[]
	var frames_started:=Time.get_ticks_usec()
	for frame in range(120):
		board.navigation.target_yaw+=0.3
		started=Time.get_ticks_usec(); board._process(1.0/60.0); samples.append((Time.get_ticks_usec()-started)/1000.0)
		await process_frame
	var rendered_fps:=120000000.0/float(Time.get_ticks_usec()-frames_started)
	samples.sort()
	print("PERF busy_board update_p95_ms=%.3f rendered_fps=%.1f draw_calls=%d primitives=%d memory_mb=%.1f textures_mb=%.1f culled=%d" % [samples[114],rendered_fps,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,culled])
	check(samples[114]<16.7,"Busy board CPU presentation update fits a 60 Hz frame budget")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/performance_medium_busy.png")
	board.free()
	print("Planet performance checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
