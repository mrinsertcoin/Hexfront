class_name WorldDressing
extends Node3D
## Deterministic composed clusters, batched by reviewed asset and supplied LOD.

var world: GeneratedPlanet
var surface: TerrainSurfaceSampler
var config: WorldDressingConfig
var exclusion_directions: Array[Vector3]=[]
var exclusion_radius: float=1.15
var instance_counts: Dictionary[String,int]={}
var variant_counts: Dictionary[String,int]={}
var instances: Dictionary[String,MultiMeshInstance3D]={}
var batch_variants: Dictionary[String,String]={}
var batch_lods: Dictionary[String,int]={}
var batch_transforms: Dictionary[String,Array]={}
var batch_directions: Dictionary[String,Array]={}
var batch_cells: Dictionary[String,PackedInt32Array]={}
var placements: Array[Dictionary]=[]
var visual_fingerprint: String=""
var build_ms: float=0.0
var candidate_count: int=0
var authored_variant_count: int=0
var last_visibility_revision: int=-1
var last_visibility_team: int=-1
var last_visibility_omniscient: bool=false
var _lake_zones: Array[Vector4]=[]
var _river_zones: Array[Vector4]=[]
var _zoom_band: String=""
var _sector_directions: Array[Vector3]=[]

func rebuild(planet: GeneratedPlanet,terrain: TerrainSurfaceSampler,settings: WorldDressingConfig) -> void:
	var started:=Time.get_ticks_usec()
	for child: Node in get_children(): child.free()
	world=planet; surface=terrain; config=settings.duplicate(true)
	instance_counts.clear(); variant_counts.clear(); instances.clear(); batch_variants.clear(); batch_lods.clear(); batch_transforms.clear(); batch_directions.clear(); batch_cells.clear(); placements.clear()
	_zoom_band=""
	_sector_directions.clear()
	var sector_grid:=PlanetGrid.new(0)
	for face: Vector3i in sector_grid._faces:
		_sector_directions.append((sector_grid.cells[face.x].up+sector_grid.cells[face.y].up+sector_grid.cells[face.z].up).normalized())
	last_visibility_revision=-1; last_visibility_team=-1; last_visibility_omniscient=false
	_lake_zones.clear(); _river_zones.clear(); visual_fingerprint=""
	assert(config.validate().is_empty(),"Invalid world dressing settings")
	for group_name in ["VegetationScatter","RockScatter","DebrisScatter"]:
		var group:=Node3D.new(); group.name=group_name; add_child(group)
	if not config.enabled:
		build_ms=(Time.get_ticks_usec()-started)/1000.0; return
	_build_water_zones()
	var catalog: Dictionary[String,DressingMeshVariant]={}
	for definition: DressingDefinition in config.definitions:
		for variant: DressingMeshVariant in definition.mesh_variants: catalog[variant.variant_id]=variant
	authored_variant_count=catalog.size()
	var resolved: Dictionary[String,Array]={}
	var transforms: Dictionary[String,Array]={}
	var directions: Dictionary[String,Array]={}
	for id: String in catalog:
		var variant: DressingMeshVariant=catalog[id]
		var lods: Array=[]
		for lod in range(3): lods.append(DressingAssetLibrary.resolve(variant,lod))
		if lods.any(func(asset: Dictionary)->bool: return asset.is_empty()):
			push_error("Rejected incomplete stylized asset at runtime: "+id); continue
		resolved[id]=lods; transforms[id]=[]; directions[id]=[]
	var direction_rng:=RandomNumberGenerator.new()
	direction_rng.seed=PlanetFieldSampler.derive_seed(world.config.world_seed,"world_dressing/%d/candidates" % config.visual_generation_version)
	candidate_count=config.candidate_count(world.grid_reference.planet_radius)
	for candidate in range(candidate_count):
		var y:=direction_rng.randf_range(-1.0,1.0)
		var azimuth:=direction_rng.randf_range(0.0,TAU)
		var center:=Vector3(sqrt(maxf(0.0,1.0-y*y))*cos(azimuth),y,sqrt(maxf(0.0,1.0-y*y))*sin(azimuth))
		var fields:=world.sample_fields(center)
		for definition: DressingDefinition in config.definitions:
			var rng:=RandomNumberGenerator.new()
			rng.seed=PlanetFieldSampler.derive_seed(world.config.world_seed,"world_dressing/%s/%d" % [definition.definition_id,candidate])
			if rng.randf()>=_density(definition,fields,center): continue
			var member_count:=rng.randi_range(definition.minimum_cluster_instances,definition.maximum_cluster_instances)
			var accepted:=0
			for member in range(member_count):
				var tangent:=PlanetCell.tangent_basis(center)
				var angle:=rng.randf_range(0.0,TAU)
				var distance:=sqrt(rng.randf())*definition.cluster_radius
				var offset:=(tangent.x*cos(angle)+tangent.z*sin(angle))*distance
				var direction:=(center*world.grid_reference.planet_radius+offset).normalized()
				var normal:=surface.sample_normal(direction)
				var slope:=rad_to_deg(acos(clampf(normal.dot(direction),-1.0,1.0)))
				var lake:=_inside_zone(direction,_lake_zones)
				var river:=_inside_zone(direction,_river_zones)
				if slope>definition.max_slope_degrees or (lake and definition.exclude_lakes) or (river and definition.exclude_rivers) or _excluded(direction): continue
				var variant:=_select_variant(definition,rng)
				if not resolved.has(variant.variant_id): continue
				var scale:=rng.randf_range(definition.minimum_scale,definition.maximum_scale)
				var visual_scale:=scale*variant.scale_multiplier
				var basis:=PlanetCell.tangent_basis(normal)*Basis(Vector3.UP,rng.randf_range(0.0,TAU))
				var transform:=Transform3D(basis.scaled(Vector3.ONE*visual_scale),surface.sample_position(direction,definition.surface_offset*visual_scale))
				transforms[variant.variant_id].append(transform)
				directions[variant.variant_id].append(direction)
				placements.append({"definition":definition.definition_id,"cluster":candidate,"member":member,
					"cluster_center":center,"direction":direction,"variant":variant.variant_id,
					"position":transform.origin,"normal":normal,"slope":slope,"scale":scale,
					"visual_scale":visual_scale,"lake":lake,"river":river})
				accepted+=1
			instance_counts[definition.definition_id]=instance_counts.get(definition.definition_id,0)+accepted
	for id: String in resolved:
		var variant: DressingMeshVariant=catalog[id]
		variant_counts[id]=transforms[id].size()
		# Each globe-wide MultiMesh previously had globe-wide bounds: even a
		# close camera submitted every tree. Small spatial batches can be culled.
		var sectors: Dictionary[int,Array]={}; var sector_directions: Dictionary[int,Array]={}
		for index in range(transforms[id].size()):
			var direction: Vector3=directions[id][index]; var sector:=0; var score:=-INF
			for candidate in range(_sector_directions.size()):
				var dot:=direction.dot(_sector_directions[candidate])
				if dot>score: sector=candidate; score=dot
			if not sectors.has(sector): sectors[sector]=[]; sector_directions[sector]=[]
			sectors[sector].append(transforms[id][index]); sector_directions[sector].append(direction)
		for sector: int in sectors:
			for lod in range(3): _create_batch(variant,lod,resolved[id][lod].mesh,sectors[sector],sector_directions[sector],sector)
	set_zoom_band("TACTICAL")
	visual_fingerprint=_fingerprint()
	build_ms=(Time.get_ticks_usec()-started)/1000.0
	print("World dressing: candidates=%d clusters=%d instances=%d assets=%d batches=%d build_ms=%.1f fingerprint=%s counts=%s" % [
		candidate_count,_cluster_count(),placements.size(),authored_variant_count,instances.size(),build_ms,visual_fingerprint.substr(0,12),str(instance_counts)])

func _density(definition: DressingDefinition,fields: PlanetWorldCellData,direction: Vector3) -> float:
	var affinity:=0.0
	for i in range(mini(5,fields.biome_weights.size())):
		var canonical:=StylizedTerrainMaterial.IDS.find(world.config.biomes[i].biome_id)
		if canonical>=0: affinity+=fields.biome_weights[i]*definition.biome_affinity[canonical]
	var wetland:=fields.hydrology.wetland_potential if fields.hydrology!=null else 0.0
	var value:=definition.base_density*affinity
	value*=_response(fields.effective_moisture,definition.moisture_response)
	value*=_response(fields.fertility,definition.fertility_response)
	value*=_response(fields.terrain_roughness,definition.roughness_response)
	value*=_response(wetland,definition.wetland_response)
	value*=_response(fields.height,definition.height_response)
	var cluster:=FastNoiseLite.new()
	cluster.seed=PlanetFieldSampler.derive_seed(world.config.world_seed,"world_dressing/cluster/"+definition.definition_id)
	cluster.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; cluster.frequency=definition.cluster_frequency
	var grove:=smoothstep(.2,.82,.5+.5*cluster.get_noise_3dv(direction))
	value*=lerpf(1.0,.10+1.55*grove,definition.cluster_strength)
	return clampf(value,0.0,.84)

func _response(value: float,response: float) -> float:
	return lerpf(1.0,value,response) if response>=0 else lerpf(1.0,1.0-value,-response)

func _select_variant(definition: DressingDefinition,rng: RandomNumberGenerator) -> DressingMeshVariant:
	var total:=0.0
	for variant: DressingMeshVariant in definition.mesh_variants: total+=variant.relative_weight
	var roll:=rng.randf()*total
	for variant: DressingMeshVariant in definition.mesh_variants:
		roll-=variant.relative_weight
		if roll<=0: return variant
	return definition.mesh_variants.back()

func _excluded(direction: Vector3) -> bool:
	var cosine:=cos(exclusion_radius/world.grid_reference.planet_radius)
	for occupied: Vector3 in exclusion_directions:
		if direction.dot(occupied.normalized())>=cosine: return true
	return false

func _build_water_zones() -> void:
	if world.hydrology==null: return
	for cell: PlanetCell in world.grid_reference.cells:
		var hydro: HydrologyCellData=world.hydrology.cells[cell.id]
		if hydro.surface_water_type==HydrologyCellData.SurfaceWater.NONE and hydro.river_class<HydrologyCellData.RiverClass.RIVER: continue
		var angular_radius:=0.0
		for neighbor: int in cell.neighbor_ids:
			angular_radius=maxf(angular_radius,acos(clampf(cell.center_direction.dot(world.grid_reference.cells[neighbor].center_direction),-1.0,1.0))*.58)
		var zone:=Vector4(cell.center_direction.x,cell.center_direction.y,cell.center_direction.z,cos(angular_radius))
		if hydro.surface_water_type!=HydrologyCellData.SurfaceWater.NONE: _lake_zones.append(zone)
		if hydro.river_class>=HydrologyCellData.RiverClass.RIVER: _river_zones.append(zone)

func _inside_zone(direction: Vector3,zones: Array[Vector4]) -> bool:
	for zone: Vector4 in zones:
		if direction.dot(Vector3(zone.x,zone.y,zone.z))>=zone.w: return true
	return false

func _create_batch(variant: DressingMeshVariant,lod: int,mesh: Mesh,source: Array,directions: Array,sector: int) -> void:
	var batch:=MultiMeshInstance3D.new()
	var id:="%s/sector%d/lod%d" % [variant.variant_id,sector,lod]
	batch.name=(variant.variant_id+"_sector%d_lod%d" % [sector,lod]).validate_node_name()
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D; multimesh.instance_count=source.size(); multimesh.mesh=mesh
	batch.multimesh=multimesh
	batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if variant.casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_category_node(variant.category).add_child(batch)
	var data:=PackedFloat32Array()
	for value: Variant in source:
		var transform: Transform3D=value
		data.append_array(PackedFloat32Array([
			transform.basis.x.x,transform.basis.y.x,transform.basis.z.x,transform.origin.x,
			transform.basis.x.y,transform.basis.y.y,transform.basis.z.y,transform.origin.y,
			transform.basis.x.z,transform.basis.y.z,transform.basis.z.z,transform.origin.z]))
	multimesh.buffer=data
	instances[id]=batch; batch_variants[id]=variant.variant_id; batch_lods[id]=lod
	batch_transforms[id]=source.duplicate(); batch_directions[id]=directions.duplicate()
	if lod==0:
		var cells:=PackedInt32Array()
		for direction: Vector3 in directions: cells.append(world.grid_reference.find_cell(direction))
		batch_cells[id]=cells
	else: batch_cells[id]=batch_cells["%s/sector%d/lod0" % [variant.variant_id,sector]]

func apply_visibility(observation: TeamObservation,grid: PlanetGrid,omniscient: bool=false) -> void:
	if last_visibility_revision==observation.revision and last_visibility_team==observation.team_id and last_visibility_omniscient==omniscient: return
	last_visibility_revision=observation.revision; last_visibility_team=observation.team_id; last_visibility_omniscient=omniscient
	for id: String in instances:
		var transforms: Array=batch_transforms[id]; var cells: PackedInt32Array=batch_cells[id]
		var visible_count:=0
		for index in range(transforms.size()):
			var cell_id:=cells[index]
			if not omniscient and not observation.is_explored(cell_id): continue
			instances[id].multimesh.set_instance_transform(visible_count,transforms[index])
			visible_count+=1
		# Zero-scale instances still submitted all mesh indices to every pass.
		# Compact permitted props into the visible prefix instead.
		instances[id].multimesh.visible_instance_count=visible_count

func _category_node(category: int) -> Node3D:
	if category==DressingDefinition.Category.ROCK: return get_node("RockScatter")
	if category==DressingDefinition.Category.DEBRIS: return get_node("DebrisScatter")
	return get_node("VegetationScatter")

func set_zoom_band(band: String) -> void:
	if band==_zoom_band: return
	_zoom_band=band
	var level:=0
	if band=="REGIONAL": level=1
	elif band=="STRATEGIC": level=2
	for id: String in instances:
		var variant:=_variant_by_id(batch_variants[id])
		instances[id].visible=band!="PLANET" and batch_lods[id]==level and level<=variant.maximum_detail_band

func _variant_by_id(id: String) -> DressingMeshVariant:
	for definition: DressingDefinition in config.definitions:
		for variant: DressingMeshVariant in definition.mesh_variants:
			if variant.variant_id==id: return variant
	return null

func _cluster_count() -> int:
	var ids:={}
	for placement: Dictionary in placements: ids[placement.definition+":"+str(placement.cluster)]=true
	return ids.size()

func _fingerprint() -> String:
	var rows:=PackedStringArray(["world-dressing-v%d-assets-v%d" % [config.visual_generation_version,WorldDressingConfig.ASSET_VERSION],str(world.config.world_seed)])
	for placement: Dictionary in placements:
		var direction: Vector3=placement.direction
		rows.append("%s:%s:%d:%d:%d:%d" % [placement.definition,placement.variant,roundi(direction.x*1000000.0),roundi(direction.y*1000000.0),roundi(direction.z*1000000.0),roundi(placement.scale*10000.0)])
	return "|".join(rows).sha256_text()
