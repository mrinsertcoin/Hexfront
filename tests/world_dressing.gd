extends "res://tests/hotseat.gd"

func state_snapshot() -> String:
	var rows:=PackedStringArray([str(board.game_state.active_player),str(board.game_state.round_number),str(board.game_state.materials)])
	for id: int in board.game_state.units:
		var unit: GameState.Unit=board.game_state.units[id]
		if not unit.neutral_group_id.is_empty(): continue
		rows.append("u:%d:%d:%d:%d:%s:%s" % [id,unit.owner_id,unit.cell_id,unit.hp,unit.moved,unit.attacked])
	for id: int in board.game_state.structures:
		var structure: GameState.Structure=board.game_state.structures[id]
		rows.append("s:%d:%d:%d:%d:%s" % [id,structure.owner_id,structure.cell_id,structure.hp,structure.recruit_available])
	return "|".join(rows)

func _run() -> void:
	await setup(false)
	var dressing: WorldDressing=board.terrain_renderer.dressing
	dressing.apply_visibility(board.view_observation,board.grid)
	check(dressing!=null,"Terrain owns one world-dressing system")
	check(dressing.get_node_or_null("VegetationScatter")!=null and dressing.get_node_or_null("RockScatter")!=null
		and dressing.get_node_or_null("DebrisScatter")!=null,"Dressing keeps category hierarchy")
	check(dressing.config.definitions.size()==5,"Five composed landscape cluster rules replace independent scatter")
	check(dressing.authored_variant_count==8,"Eight reviewed stylized assets are active")
	check(dressing.instances.size()>0 and dressing.instances.size()<=8*20*3 and dressing.instances.size()%3==0,"Scenery uses bounded spatial batches with three explicit LODs")
	var variant_ids:={}
	for definition: DressingDefinition in dressing.config.definitions:
		check(definition.minimum_cluster_instances>=1 and definition.maximum_cluster_instances>=definition.minimum_cluster_instances,
			"Cluster composition has bounded member counts")
		for variant: DressingMeshVariant in definition.mesh_variants:
			variant_ids[variant.variant_id]=true
			check(variant.scene_paths.size()==3 and variant.mesh_node_names.size()==3,"Asset maps all three supplied LODs")
			for lod in range(3):
				check(ResourceLoader.exists(variant.scene_paths[lod]),"Runtime stylized GLB resolves: %s LOD%d" % [variant.variant_id,lod])
	check(variant_ids.size()==8,"Definitions reuse one cohesive eight-asset catalog")
	for batch_id: String in dressing.instances:
		var batch: MultiMeshInstance3D=dressing.instances[batch_id]
		check(batch.multimesh!=null and batch.multimesh.mesh!=null,"Every LOD batch has authored geometry")
		check(batch.multimesh.mesh.has_meta("dressing_source"),"Primitive fallback is absent from active dressing")
		check(batch.multimesh.mesh.get_meta("stylized_lod")==dressing.batch_lods[batch_id],"Batch binds its supplied LOD")
		var permitted:=0
		for cell_id: int in dressing.batch_cells[batch_id]:
			if board.view_observation.is_explored(cell_id): permitted+=1
		check(batch.multimesh.visible_instance_count==permitted,"Unexplored props are excluded from submitted instance counts: %s submitted=%d permitted=%d" % [batch_id,batch.multimesh.visible_instance_count,permitted])
		for surface in range(batch.multimesh.mesh.get_surface_count()):
			var material:=batch.multimesh.mesh.surface_get_material(surface)
			check(material!=null,"Authored material survives normalization")
			if material is BaseMaterial3D:
				check(is_zero_approx((material as BaseMaterial3D).metallic),"Stylized assets are non-metallic")
				check((material as BaseMaterial3D).roughness>=.82,"Stylized assets share restrained roughness")
	check(dressing.placements.size()>20 and dressing.placements.size()<dressing.candidate_count*10,
		"Clustered dressing is populated and bounded")
	var definitions: Dictionary[String,DressingDefinition]={}
	for definition: DressingDefinition in dressing.config.definitions: definitions[definition.definition_id]=definition
	var cell_centers:=0
	var clusters:={}
	var occupied:=dressing.exclusion_directions
	var exclusion_cos:=cos(dressing.exclusion_radius/board.planet_radius)
	for placement: Dictionary in dressing.placements:
		var definition: DressingDefinition=definitions[placement.definition]
		check(placement.slope<=definition.max_slope_degrees+.001,"Cluster member respects slope")
		check(not (placement.lake and definition.exclude_lakes),"Lake exclusion is respected")
		check(not (placement.river and definition.exclude_rivers),"River exclusion is respected")
		var expected:=dressing.surface.sample_position(placement.direction,definition.surface_offset*placement.visual_scale)
		check(expected.distance_to(placement.position)<.0001,"Prop contacts displaced terrain")
		check(placement.normal.dot(placement.position.normalized())>0.8,"Prop local up follows the radial surface")
		for direction: Vector3 in occupied:
			check(placement.direction.dot(direction)<exclusion_cos,"Opening units and HQs retain a readable clearing")
		var cell_id:=board.grid.find_cell(placement.direction)
		if board.grid.cells[cell_id].center_direction.dot(placement.direction)>.9999999: cell_centers+=1
		var cluster_id: String=str(placement.definition)+":"+str(placement.cluster)
		clusters[cluster_id]=int(clusters.get(cluster_id,0))+1
	check(cell_centers==0,"Placement does not reveal gameplay cell centers")
	var composed:=0
	for count: int in clusters.values():
		if count>1: composed+=1
	check(composed>0 and clusters.size()<dressing.placements.size(),"Props form multi-member landscape clusters")
	for band in ["TACTICAL","REGIONAL","STRATEGIC"]:
		dressing.set_zoom_band(band)
		var desired:=["TACTICAL","REGIONAL","STRATEGIC"].find(band)
		for batch_id: String in dressing.instances:
			var variant:=dressing._variant_by_id(dressing.batch_variants[batch_id])
			var expected_visible: bool=dressing.batch_lods[batch_id]==desired and desired<=variant.maximum_detail_band
			check(dressing.instances[batch_id].visible==expected_visible,"Zoom band selects exactly one supplied asset LOD")
	dressing.set_zoom_band("PLANET")
	for batch: MultiMeshInstance3D in dressing.instances.values(): check(not batch.visible,"Planet zoom hides dressing")
	var blank:=TeamObservation.new(); blank.team_id=999; blank.revision=1
	blank.explored_cells.resize(board.grid.get_cell_count()); blank.explored_cells.fill(0)
	dressing.apply_visibility(blank,board.grid)
	for batch: MultiMeshInstance3D in dressing.instances.values(): check(batch.multimesh.visible_instance_count==0,"A fresh observer submits no hidden scenery")
	dressing.apply_visibility(board.view_observation,board.grid,true)
	for batch: MultiMeshInstance3D in dressing.instances.values(): check(batch.multimesh.visible_instance_count==batch.multimesh.instance_count,"Omniscient display restores every scenery instance")
	dressing.apply_visibility(board.view_observation,board.grid)
	var visual_before:=dressing.visual_fingerprint
	var counts_before:=dressing.variant_counts.duplicate(true)
	var world_before:=board.generated_planet.generation_fingerprint
	var state_before:=state_snapshot()
	board.rebuild_terrain()
	dressing=board.terrain_renderer.dressing
	check(dressing.visual_fingerprint==visual_before and dressing.variant_counts==counts_before,
		"Same seed and visual config reproduce identical clusters")
	check(board.generated_planet.generation_fingerprint==world_before,"Dressing does not mutate GeneratedPlanet")
	check(state_snapshot()==state_before,"Dressing rebuild does not modify GameState")
	board.regenerate_world(board.generation_config.world_seed+1)
	check(board.terrain_renderer.dressing.visual_fingerprint!=visual_before,"Different seed changes visual clusters")
	check(state_snapshot()==state_before,"Visual regeneration does not modify GameState")
	var medium:=WorldDressingConfig.new()
	check(medium.candidate_count(48.0)<=medium.maximum_candidates,"Medium profile obeys an explicit cluster-center cap")
	print("World dressing checks: instances=",counts_before," clusters=",clusters.size()," fingerprint=",visual_before)
	await finish("World dressing")
