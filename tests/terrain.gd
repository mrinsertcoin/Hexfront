extends "res://tests/hotseat.gd"

func _run() -> void:
	await setup(true)
	var renderer: PlanetTerrainRenderer=board.terrain_renderer
	var fingerprint: String=board.generated_planet.generation_fingerprint
	var terrain_material: ShaderMaterial=renderer.chunks[0].material_override
	check(terrain_material!=null and terrain_material.get_meta("terrain_pipeline")=="stylized_palette_v1",
		"Stylized palette is the single active terrain material")
	check(terrain_material.shader!=null and not terrain_material.shader.code.contains("sampler2DArray"),
		"Active terrain shader has no scanned texture-array path")
	var palette: PackedColorArray=terrain_material.get_shader_parameter("biome_colors")
	check(palette.size()==5 and palette==board.terrain_config.biome_colors,
		"Five continuous biome fields bind the configured stylized palette")
	check(terrain_material.get_shader_parameter("macro_strength")==board.terrain_config.macro_strength,
		"Restrained macro variation is configured")
	check(renderer.faces.size()==20*int(pow(4,board.terrain_config.terrain_subdivision_level)), "Visual resolution has independent triangle count")
	check(renderer.vertices.size()>board.grid.cells.size()*10, "Visual vertices independent of cell count")
	var edges: Dictionary={}
	for face: Vector3i in renderer.faces:
		for id: int in [face.x,face.y,face.z]: check(id>=0 and id<renderer.vertices.size(), "Mesh indices in bounds")
		for edge: Vector2i in [Vector2i(face.x,face.y),Vector2i(face.y,face.z),Vector2i(face.z,face.x)]:
			var key:=Vector2i(mini(edge.x,edge.y),maxi(edge.x,edge.y))
			edges[key]=int(edges.get(key,0))+1
	for count: int in edges.values(): check(count==2,"Watertight welded terrain: two triangles per edge")
	var minimum: float=INF; var maximum: float=-INF
	for id in range(renderer.vertices.size()):
		var point: Vector3=renderer.vertices[id]
		check(point.is_finite() and renderer.normals[id].is_finite(),"Finite terrain geometry")
		check(renderer.normals[id].dot(point.normalized())>0.0,"Smooth normals point outward")
		check(absf(point.length()-board.terrain_surface.radius_at(point))<0.0001,"Canonical height remapping matches rendered radius")
		minimum=minf(minimum,point.length()); maximum=maxf(maximum,point.length())
	check(maximum-minimum>0.8,"Visible height variation")
	# Shared chunk corners have identical positions AND normals.
	var shared: Dictionary={}
	for chunk: MeshInstance3D in renderer.chunks:
		var arrays: Array=chunk.mesh.surface_get_arrays(0)
		for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
			var point: Vector3=arrays[Mesh.ARRAY_VERTEX][i]
			var key:=Vector3i((point*100000.0).round())
			if shared.has(key): check(shared[key].is_equal_approx(arrays[Mesh.ARRAY_NORMAL][i]),"Chunk normals share no seams")
			shared[key]=arrays[Mesh.ARRAY_NORMAL][i]
	for cell: PlanetWorldCellData in board.generated_planet.cell_world_data:
		var sample: PlanetWorldCellData=board.generated_planet.sample_fields(board.grid.cells[cell.cell_id].up)
		check(absf(sample.effective_moisture-cell.effective_moisture)<0.00001,"Continuous hydrology agrees at cell centers")
		for i in range(sample.biome_weights.size()): check(absf(sample.biome_weights[i]-cell.biome_weights[i])<0.00001,"Canonical continuous biome sampler includes 8C wetland weights")
	for lake: LakeData in board.generated_planet.hydrology.lakes:
		var arrays: Array=renderer.water.lake_meshes[lake.id].mesh.surface_get_arrays(0)
		var radius: float=board.planet_radius+board.terrain_config.mapped_height(lake.surface_height)+board.terrain_config.water_offset
		check(not arrays[Mesh.ARRAY_VERTEX].is_empty(),"Every authoritative lake produces merged water")
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: check(point.is_finite() and absf(point.length()-radius)<0.0001,"Lake uses a common authoritative surface radius")
	var water_arrays: Array=renderer.water.river_mesh.mesh.surface_get_arrays(0)
	for segment: RiverSegment in board.generated_planet.hydrology.river_segments:
		check(renderer.water.segment_ranges.has(segment.from_cell_id),"Every river segment creates ribbon geometry")
		check(renderer.water.width_for(segment)>=board.terrain_config.river_min_width,"River widths follow configuration")
		var span: Vector2i=renderer.water.segment_ranges[segment.from_cell_id]
		var actual_width: float=water_arrays[Mesh.ARRAY_VERTEX][span.x].distance_to(water_arrays[Mesh.ARRAY_VERTEX][span.x+2])
		check(actual_width>=renderer.water.width_for(segment)*0.8 and actual_width<=renderer.water.width_for(segment)*1.8,"Ribbon has real width matching hydrology, without twists")
		var ceiling: float=0.0
		for id: int in [segment.from_cell_id,segment.to_cell_id]:
			var lake_id: int=board.generated_planet.hydrology.cells[id].lake_id
			if lake_id>=0: ceiling=maxf(ceiling,board.planet_radius+board.terrain_config.mapped_height(board.generated_planet.hydrology.lakes[lake_id].surface_height))
		for i in range(span.x,span.x+span.y):
			var point: Vector3=water_arrays[Mesh.ARRAY_VERTEX][i]
			var floor_radius: float=board.terrain_surface.radius_at(point)
			check(point.length()>=floor_radius-0.001 and point.length()<=maxf(floor_radius,ceiling)+board.terrain_config.water_offset+0.001,"Water ribbons follow terrain or an adjacent lake surface")
	for point: Vector3 in water_arrays[Mesh.ARRAY_VERTEX]: check(point.is_finite() and point.length()>board.planet_radius,"River geometry finite and outside sphere")
	# Detailed motion across a multi-edge path samples the same presentation field.
	var path: Array[int]=board.grid.find_path(0,board.grid.breadth_first(0).order[-1])
	var entity: EntityView=board.unit_views[2]
	entity.play_path(path,board.grid,board.SURFACE_OFFSET)
	for i in range(180):
		entity.advance_movement(0.033)
		var contact:=board.terrain_surface.ground_position(entity.position.normalized(),0.0)
		var contact_normal:=board.terrain_surface.ground_normal(entity.position.normalized())
		check(absf((entity.position-contact).dot(contact_normal)-board.SURFACE_OFFSET)<0.001,"Movement contacts the rendered terrain without clipping")
	entity.cancel_movement()
	var original: PackedVector3Array=renderer.vertices.duplicate()
	var masks: PackedColorArray=renderer.colors.duplicate()
	board.rebuild_terrain()
	check(renderer.vertices==original and renderer.colors==masks,"Same recipe rebuild produces identical geometry and biome masks")
	check(board.generated_planet.generation_fingerprint==fingerprint,"Rendering never mutates world data")
	check(not board.debug_outlines.visible,"Idle terrain has no persistent tile grid")
	# Real displaced picking at every cell, including all pentagons, both poles,
	# hills and lake cells. Vary close/regional/overview rays and camera direction.
	for altitude: float in [4.0,16.0,60.0]:
		board.navigation.distance=altitude
		for cell: PlanetCell in board.grid.cells:
			board.focus_cell(cell.id,true)
			check(board.pick_cell(_screen(cell.id,false))==cell.id,"Displaced center selection at all cell heights and zooms")
	# Off-axis rays target triangle interiors to avoid ambiguity on a silhouette.
	# Independent segment visibility determines which projected targets are hidden.
	var off_axis_checks: int=0
	for yaw: float in [0.0,90.0,180.0,237.0]:
		for pitch: float in [-89.9,-40.0,0.0,53.0,89.9]:
			_globe_pose(yaw, pitch, 8)
			for i in range(0,renderer.faces.size(),71):
				var f: Vector3i=renderer.faces[i]
				var point: Vector3=(renderer.vertices[f.x]+renderer.vertices[f.y]+renderer.vertices[f.z])/3.0
				var toward: Vector3=(board.camera.position-point).normalized()
				var normal: Vector3=(renderer.vertices[f.y]-renderer.vertices[f.x]).cross(renderer.vertices[f.z]-renderer.vertices[f.x]).normalized()
				if normal.dot(toward)<0.12: continue
				if not renderer.surface.picking_mesh.intersect_segment(point+toward*0.001,board.camera.position).is_empty(): continue
				var screen: Vector2=board.camera.unproject_position(point)
				if not root.get_visible_rect().has_point(screen): continue
				var expected: int=board.grid.find_cell(point)
				var picked: int=board.pick_cell(screen)
				var valid: bool=picked==expected
				# A shared logical polygon boundary can select either incident cell
				# within the subpixel edge tolerance; interiors must match exactly.
				if not valid and picked>=0:
					valid=true
					for boundary: Vector3 in board.grid.cells[picked].boundary_normals:
						if boundary.dot(point.normalized()) < -0.0001: valid=false
				check(valid,"Off-axis terrain hit maps back to authoritative cell: expected %d actual %d" % [expected,picked])
				off_axis_checks+=1
	check(off_axis_checks>200,"Substantial displaced camera/orbit picking matrix exercised")
	print("Terrain geometry checks: vertices=",original.size()," triangles=",renderer.faces.size()," chunks=",renderer.chunks.size())
	await finish("Terrain")
