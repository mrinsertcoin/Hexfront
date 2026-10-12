extends "res://tests/hotseat.gd"
## Run graphically as well to capture village/roads and both tactical cards.
func settle_layout() -> void:
	for _frame in range(4): await process_frame
	board._layout_hud(); await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/ux_"+name+".png")==OK,"Saved "+name)

func _run() -> void:
	root.size=Vector2i(1280,720)
	board=Main.instantiate() as PlanetBoard
	var config:=MatchConfig.new(); config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.player_faction_id="living_migration"; config.opponent_faction_id="baumeister"; config.opponent_controller="Human"
	config.world_population_preset=WorldPopulationConfig.OFF; config.villages_per_player=0
	var settings:=UserSettings.new(); settings.terrain_quality="Medium"
	board.configure_match(config,settings); root.add_child(board); board.set_process(false)
	await process_frame; await process_frame
	var worker: GameState.Unit=board.game_state.units[2]; var spider: GameState.Unit=board.game_state.units[1]
	board.selected=worker.cell_id; board.selected_unit_id=worker.id; board._focus_selected(); board._refresh_display()
	await settle_layout()
	var worker_width:=board.hud_panel.size.x; var worker_height:=board.hud_panel.size.y
	check(is_equal_approx(worker_width,340.0),"Unit overlay has a fixed width instead of expanding for preview/stat content")
	check(not board.unit_info_panel.details_label.visible,"Repeated diagnostic statistics start collapsed")
	for group: String in [UnitInfoPanel.GROUP_ATTACKS,UnitInfoPanel.GROUP_STANCES]:
		for button: Button in board.unit_info_panel.action_flows[group].get_children(): check(button.size.x>32.0,"Combat action has enough width to display its text")
	check(board.unit_info_panel.health_icon.texture!=null and board.unit_info_panel.health_icon.tooltip_text.contains("Health: %d / %d" % [worker.hp,worker.max_hp]),"Health icon exposes the current value on hover")
	check(board.unit_info_panel.squad_icon.tooltip_text.contains("Group size:"),"Group size icon explains its value")
	for icon: String in StatIcons.IDS: check(StatIcons.texture(icon)!=null,"Reusable vector icon exists: "+icon)
	for node: Node in board.unit_info_panel.stats_grid.get_children():
		if node is TextureRect: check(node.texture!=null and not node.tooltip_text.is_empty() and node.mouse_filter==Control.MOUSE_FILTER_STOP,"Each stat icon can receive hover help")
	await capture("worker")
	board.selected=spider.cell_id; board.selected_unit_id=spider.id; board._refresh_display(); await settle_layout()
	check(board.hud_panel.size.x==worker_width and board.hud_panel.size.y>worker_height,"Spider actions grow the overlay upward without moving its right edge")
	check(not board.action_panel.visible and board.recruit_box.get_child_count()==0 and board.unit_info_panel.action_sections[UnitInfoPanel.GROUP_CITY].visible,"Spider city actions live entirely inside the unit card")
	var production: Button
	for child: Node in board.unit_info_panel.action_flows[UnitInfoPanel.GROUP_CITY].get_children():
		if child is Button and child.text.begins_with("Produce Worker"): production=child
	check(production!=null and not production.disabled,"Legal nursery production is accessible in the card")
	if production!=null:
		var jobs_before:=spider.spider_state.nursery_jobs.size(); production.pressed.emit()
		check(spider.spider_state.nursery_jobs.size()==jobs_before+1,"Spider overlay production dispatches the existing authoritative action")
	await settle_layout(); await capture("spider_720")
	for viewport_size: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size=viewport_size; await settle_layout()
		check(board.hud_panel.size.x==worker_width and board.hud_panel.get_global_rect().position.y>=70.0 and board.hud_panel.get_global_rect().end.y<=viewport_size.y,"Overlay grows vertically and stays within %s" % viewport_size)
		for child: Node in board.unit_info_panel.find_children("*","Control",true,false):
			if child.is_visible_in_tree(): check(child.get_global_rect().end.x<=board.hud_panel.get_global_rect().end.x,"Overlay child stays inside its fixed right edge: "+child.name)
		await capture("spider_%dx%d" % [viewport_size.x,viewport_size.y])
	root.size=Vector2i(1280,720); await settle_layout()
	var village_cell:=-1
	for candidate: int in board.grid.get_cells_within_distance(worker.cell_id,3):
		if not board.game_state.is_cell_blocked(candidate) and not board.game_state.is_water_cell(candidate): village_cell=candidate; break
	var village:=board.game_state.add_world_site("village",village_cell,53)
	board.game_state.refresh_visibility(); board._refresh_display()
	var model:=board.site_views[village.id].get_node("VillageModel") as Node3D
	var authored: AABB=model.get_meta("authored_bounds"); var footprint: Vector2=model.get_meta("tile_footprint")
	var ratios:=Vector2(authored.size.x*model.scale.x/footprint.x,authored.size.z*model.scale.z/footprint.y)
	print("Village fit bounds=",authored," scale=",model.scale," position=",model.position," footprint=",footprint)
	check(maxf(ratios.x,ratios.y)>0.98 and maxf(ratios.x,ratios.y)<=1.01,"Village is fitted to the whole tile footprint")
	var road_cells: Dictionary[int,int]={worker.cell_id:1}
	var first_neighbor:=board.grid.get_neighbors(worker.cell_id)[0]; road_cells[first_neighbor]=1
	for neighbor: int in board.grid.get_neighbors(first_neighbor):
		if neighbor!=worker.cell_id: road_cells[neighbor]=1; break
	for cell_id: int in road_cells: board.game_state.living_migration.add_road(1,cell_id)
	board.ant_road_overlay.sync_roads(road_cells)
	for id: int in road_cells:
		var mesh: ArrayMesh=(board.ant_road_overlay.cell_views[id].get_node("Dirt") as MeshInstance3D).mesh
		var points: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point: Vector3 in points:
			var direction:=point.normalized()
			var hit: Dictionary=board.terrain_surface.picking_mesh.intersect_ray(direction*(board.planet_radius+3.0),-direction)
			check(not hit.is_empty() and absf(point.length()-Vector3(hit.position).length()-AntRoadOverlay.HEIGHT_OFFSET)<0.001,"Road hugs the actual rendered terrain at a subtle height")
	board.clear_selection(); board.visibility_omniscient=true; board._refresh_display()
	board.navigation.target_pitch=80.0; board.navigation.pitch=80.0
	board.focus_cell(village_cell,true); await settle_layout(); await capture("village_roads")
	var path_cells: Dictionary[int,int]={}
	var path_center:=-1
	for candidate_id: int in board.grid.breadth_first(village_cell).order:
		var cell:=board.grid.get_cell(candidate_id)
		if board.game_state.is_cell_blocked(cell.id) or board.game_state.is_water_cell(cell.id): continue
		var land: Array[int]=[]
		for neighbor: int in cell.neighbor_ids:
			if not board.game_state.is_cell_blocked(neighbor) and not board.game_state.is_water_cell(neighbor): land.append(neighbor)
		if land.size()>=2:
			path_center=cell.id; path_cells={cell.id:1,land[0]:1,land[1]:1}; break
	check(path_center>=0,"Found a dry branching path fixture")
	for cell_id: int in path_cells: board.game_state.living_migration.add_road(1,cell_id)
	board._refresh_display(); board.focus_cell(path_center,true)
	board.hud_panel.visible=false; board.coordinate_label.visible=false
	await settle_layout(); await capture("roads")
	board.queue_free(); await process_frame
	print("Overlay UX checks complete; failures=",failures); quit(0 if failures==0 else 1)
