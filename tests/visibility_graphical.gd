extends "res://tests/hotseat.gd"

var size_label:="small"

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/m17_%s_%s.png" % [size_label,label])==OK,"Visibility capture saved: "+label)

func cell_at_distance(start: int,distance: int) -> int:
	var search:=board.grid.breadth_first(start)
	for id: int in search.order:
		if int(search.costs[id])==distance and not board.game_state.is_cell_blocked(id): return id
	return -1

func _run() -> void:
	var level:=5 if "--medium" in OS.get_cmdline_user_args() else 4
	size_label="medium" if level==5 else "small"
	await setup(false,level)
	check(board.fog_overlay!=null and board.fog_overlay.get_child_count()==1,"Fog uses one spherical mesh node rather than per-cell nodes")
	check(board.view_observation.visible_cells.size()==board.grid.get_cell_count(),"Rendered observation matches planet topology")
	board.focus_cell(board.game_state.units[2].cell_id,true); board.navigation.distance=8.0; board.navigation.target_distance=8.0; board._update_camera_transform(0)
	await capture("fresh_match")

	var scout: GameState.Unit=board.game_state.units[2]
	var origin:=scout.cell_id
	var enemy: GameState.Unit=board.game_state.units[3]
	var explored_center:=cell_at_distance(origin,7)
	scout.cell_id=explored_center
	enemy.cell_id=cell_at_distance(explored_center,2); board.game_state.refresh_visibility(); board._refresh_display()
	check(board.unit_views[enemy.id].visible,"Currently observed enemy renders")
	board.select_at(_screen(enemy.cell_id)); check(board.selected_unit_id==enemy.id,"Currently observed enemy can be inspected")
	await capture("observed_enemy_and_partial_world")

	var former_enemy_cell:=enemy.cell_id
	scout.cell_id=origin; board.game_state.refresh_visibility(); board._refresh_display()
	check(not board.unit_views[enemy.id].visible and board.contact_views.has(enemy.id),"Hidden enemy is replaced by a historical marker")
	board.focus_cell(former_enemy_cell,true); board.navigation.distance=5.0; board.navigation.target_distance=5.0; board._update_camera_transform(0)
	await capture("explored_and_last_known")

	# Common detection path: Scout Trike reveals test-only concealment without a special renderer.
	var concealed_definition:=UnitDefinition.new(); concealed_definition.id="graphical_concealed"; concealed_definition.display_name="Concealed QA"; concealed_definition.concealed=true
	board.game_state.registry.add_definition(concealed_definition)
	var recon:=GameState.Unit.new(9001,1,"scout_trike",origin,-1,board.game_state.registry); board.game_state.units[recon.id]=recon
	var concealed:=GameState.Unit.new(9002,2,"graphical_concealed",cell_at_distance(origin,2),-1,board.game_state.registry); board.game_state.units[concealed.id]=concealed
	concealed.active_disease=DiseaseState.new("tracking",2,1)
	var trade:=board.game_state.add_world_site("trade_post",cell_at_distance(origin,3))
	board.game_state.controllers[70]=ControllerState.new(70,ControllerState.NEUTRAL_AI,"")
	board.game_state.relationships.set_relationship(1,70,RelationshipState.Kind.NEUTRAL)
	var neutral:=GameState.Unit.new(9003,70,"wild_grazer",cell_at_distance(origin,1),-1,board.game_state.registry); board.game_state.units[neutral.id]=neutral
	board.game_state.refresh_visibility(); board._refresh_display()
	check(board.unit_views[concealed.id].visible and board.unit_views[neutral.id].visible,"Detection, Tracking, and neutral encounters use normal entity visibility")
	check(board.site_views[trade.id].visible,"Discovered trade post renders")
	board.focus_cell(origin,true); board.navigation.distance=6.5; board.navigation.target_distance=6.5; board._update_camera_transform(0)
	await capture("tracking_recon_site_neutral")

	board.navigation.distance=board.navigation.max_distance(); board.navigation.target_distance=board.navigation.distance; board.navigation.pitch=80.0; board.navigation.target_pitch=80.0; board._update_camera_transform(0)
	await capture("whole_planet")

	# Direct authoritative reset is sufficient for the graphical privacy regression.
	board.clear_selection(); board.request_end_turn()
	check(board.privacy_overlay.visible and board.view_team_id==board.game_state.controllers[2].team_id,"Hotseat transition obscures the switched perspective")
	await capture("hotseat_handoff")
	print("Fog profile size=%s cells=%d geometry_ms=%.1f revision_ms=%.1f visibility_ms=%.2f contacts=%d" % [size_label,board.grid.get_cell_count(),
		board.fog_overlay.geometry_build_ms,board.fog_overlay.build_ms,board.game_state.visibility_system.last_recalculation_ms,board.contact_views.size()])
	await finish("Visibility graphical "+size_label)
