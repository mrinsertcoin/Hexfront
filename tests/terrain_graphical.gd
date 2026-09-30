extends "res://tests/hotseat.gd"

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/stylized_"+label+".png")==OK,"Capture saved")

func focus_biome(index: int) -> void:
	var representative:=PackedStringArray(["grassland_copses","forest_groves","dryland_scrub","rock_fields","wetland_growth"])[index]
	for placement: Dictionary in board.terrain_renderer.dressing.placements:
		if placement.definition==representative:
			board.navigation.focus(placement.cluster_center,true)
			return
	var best:=-1
	var weight:=-1.0
	for cell: PlanetCell in board.grid.cells:
		var value: float=board.generated_planet.get_cell(cell.id).biome_weights[index]
		if value>weight: weight=value; best=cell.id
	board.focus_cell(best,true)

func show_view(label: String,distance: float,band: String) -> void:
	board.navigation.distance=distance; board.navigation.target_distance=distance
	board.navigation.pitch=55.0 if band in ["TACTICAL","REGIONAL"] else 80.0
	board.navigation.target_pitch=board.navigation.pitch
	board._update_camera_transform(0)
	board.terrain_renderer.dressing.set_zoom_band(band)
	await capture(label)

func _run() -> void:
	var level:=5 if "--medium" in OS.get_cmdline_user_args() else 4
	await setup(true,level)
	var material: ShaderMaterial=board.terrain_renderer.chunks[0].material_override
	check(material!=null and material.get_meta("terrain_pipeline")=="stylized_palette_v1",
		"Graphical run uses stylized terrain")
	check(board.terrain_renderer.dressing.authored_variant_count==8,"Graphical run uses reviewed Meshy catalog")
	var names:=PackedStringArray(["grassland","forest","dryland","rocky","wetland"])
	for index in range(5):
		focus_biome(index)
		await show_view(names[index]+"_tactical",4.5,"TACTICAL")
		if index in [0,1]: await show_view(names[index]+"_regional",9.0,"REGIONAL")
	var mixed_cell:=-1
	var mixed_score:=-1.0
	for cell: PlanetCell in board.grid.cells:
		var weights=board.generated_planet.get_cell(cell.id).biome_weights
		var sorted: Array=Array(weights); sorted.sort(); sorted.reverse()
		var score: float=sorted[1] if sorted.size()>1 else 0.0
		if score>mixed_score: mixed_score=score; mixed_cell=cell.id
	board.focus_cell(mixed_cell,true)
	await show_view("mixed_transition",5.5,"TACTICAL")
	await show_view("strategic",18.0,"STRATEGIC")
	await show_view("planet",42.0,"PLANET")
	# Readability around the opening state and overlays.
	var occupied_cell: int=board.game_state.units[2].cell_id
	board.focus_cell(occupied_cell,true)
	board.select_at(_screen(occupied_cell))
	await show_view("unit_overlay_readability",4.5,"TACTICAL")
	board.clear_selection()
	var frames: Array[float]=[]
	board.terrain_renderer.dressing.set_zoom_band("REGIONAL")
	for i in range(180):
		var started:=Time.get_ticks_usec()
		board.navigation.yaw+=.5; board._update_camera_transform(0)
		await process_frame
		frames.append((Time.get_ticks_usec()-started)/1000.0)
	frames.sort()
	print("Stylized profile size=%s cells=%d triangles=%d instances=%d batches_total=%d batches_visible=%d dressing_build_ms=%.1f median_ms=%.3f p95_ms=%.3f draw_calls=%d" % [
		"Medium" if level==5 else "Small",board.grid.cells.size(),board.terrain_renderer.triangle_count,
		board.terrain_renderer.dressing.placements.size(),board.terrain_renderer.dressing.instances.size(),
		_visible_batches(),board.terrain_renderer.dressing.build_ms,frames[90],frames[171],
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	var before:=root.get_texture().get_image().get_data()
	var fingerprint:=board.terrain_renderer.dressing.visual_fingerprint
	board.regenerate_world(board.generated_planet.config.world_seed)
	board.feedback_label.text=""
	board.terrain_renderer.dressing.set_zoom_band("REGIONAL")
	board.focus_cell(occupied_cell,true)
	await process_frame; await RenderingServer.frame_post_draw
	check(board.terrain_renderer.dressing.visual_fingerprint==fingerprint,"Graphical same-seed clusters are deterministic")
	material=board.terrain_renderer.chunks[0].material_override
	material.set_shader_parameter("wet_strength",0.0)
	await process_frame; await RenderingServer.frame_post_draw
	check(before!=root.get_texture().get_image().get_data(),"Stylized wetland darkening affects rendered terrain")
	await finish("Terrain graphical")

func _visible_batches() -> int:
	var result:=0
	for batch: MultiMeshInstance3D in board.terrain_renderer.dressing.instances.values():
		if batch.visible and batch.multimesh.instance_count>0: result+=1
	return result
