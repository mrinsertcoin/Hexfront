class_name WorldPopulationGenerator
extends RefCounted
## Deterministic logical population generated after the immutable planet.

static func generate(world: GeneratedPlanet,registry: ContentRegistry,
		config: WorldPopulationConfig) -> WorldPopulationResult:
	var started:=Time.get_ticks_usec()
	var result:=WorldPopulationResult.new()
	result.generation_version=config.generation_version
	result.world_fingerprint=world.generation_fingerprint
	result.config_fingerprint=config.fingerprint_record().sha256_text()
	var errors:=config.validate(registry)
	if not errors.is_empty():
		push_error("Invalid world-population config: "+"; ".join(errors))
		result.refresh_fingerprint(); return result
	if not config.enabled and config.villages_per_player<=0:
		result.generation_ms=(Time.get_ticks_usec()-started)/1000.0
		result.refresh_fingerprint(); return result
	var occupied:={}
	var major_regions:={}
	_generate_villages(world,registry,config,result,occupied,major_regions)
	if config.enabled and not config.site_definition_ids.is_empty():
		_generate_explicit_sites(world,registry,config,result,occupied,major_regions)
	elif config.enabled:
		_generate_category_sites(world,registry,config,result,occupied,major_regions)
	if config.enabled or config.villages_per_player>0: _generate_neutrals(world,registry,config,result,occupied)
	result.site_records.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return a.definition_id<b.definition_id or (a.definition_id==b.definition_id and a.cell_id<b.cell_id))
	result.neutral_group_records.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return a.definition_id<b.definition_id or (a.definition_id==b.definition_id and a.cell_id<b.cell_id))
	result.generation_ms=(Time.get_ticks_usec()-started)/1000.0
	result.refresh_fingerprint()
	return result

static func _generate_explicit_sites(world: GeneratedPlanet,registry: ContentRegistry,config: WorldPopulationConfig,
		result: WorldPopulationResult,occupied: Dictionary,major_regions: Dictionary) -> void:
	var ids:=config.site_definition_ids.duplicate(); ids.sort()
	for definition_id: String in ids:
		var definition:=registry.world_site(definition_id)
		if definition==null: continue
		_place_sites(world,config,result,occupied,major_regions,definition,config.site_counts.get(definition_id,0),
			"explicit/"+definition_id)

static func _generate_category_sites(world: GeneratedPlanet,registry: ContentRegistry,config: WorldPopulationConfig,
		result: WorldPopulationResult,occupied: Dictionary,major_regions: Dictionary) -> void:
	var categories: Array[Dictionary]=[
		{"category":"trade","density":config.trade_posts_per_1000_cells,"cap":config.maximum_trade_posts,"stream":"trade_posts"},
		{"category":"resource","density":config.resource_sites_per_1000_cells,"cap":config.maximum_resource_sites,"stream":"resource_sites"},
		{"category":"ruin","density":config.ruins_per_1000_cells,"cap":config.maximum_ruins,"stream":"ruins"}]
	for row: Dictionary in categories:
		var definitions: Array[WorldSiteDefinition]=[]
		for id: String in ContentRegistry._sorted_keys(registry.world_sites):
			var definition: WorldSiteDefinition=registry.world_sites[id]
			if definition.category==row.category: definitions.append(definition)
		if definitions.is_empty(): continue
		var count:=mini(int(row.cap),ceili(world.grid_reference.get_cell_count()*float(row.density)/1000.0))
		_place_category_sites(world,config,result,occupied,major_regions,definitions,count,row.stream)

static func _generate_villages(world: GeneratedPlanet,registry: ContentRegistry,config: WorldPopulationConfig,
		result: WorldPopulationResult,occupied: Dictionary,major_regions: Dictionary) -> void:
	if config.villages_per_player<=0 or config.player_count<=0: return
	var definition:=registry.world_site("village")
	if definition==null: return
	var candidates:=_ranked_candidates(world,"village",_rng(world,config,"villages"))
	var target:=config.villages_per_player*config.player_count
	var placed:=0
	for candidate: Dictionary in candidates:
		if placed>=target: break
		var cell_id: int=candidate.cell_id
		if occupied.has(cell_id) or not _far_from(world.grid_reference,cell_id,occupied.keys(),config.village_spacing): continue
		if not _far_from(world.grid_reference,cell_id,config.start_cells,config.village_start_distance): continue
		var data:=world.get_cell(cell_id)
		if data.terrain_roughness>0.72: continue
		if world.terraces!=null and world.terraces.is_ramp(cell_id): continue
		occupied[cell_id]=true; major_regions[data.region_id]=true
		result.site_records.append(_site_record(definition.id,cell_id,data,"villages"))
		placed+=1

static func _place_category_sites(world: GeneratedPlanet,config: WorldPopulationConfig,result: WorldPopulationResult,
		occupied: Dictionary,major_regions: Dictionary,definitions: Array[WorldSiteDefinition],count: int,stream: String) -> void:
	var category:=definitions[0].category
	var candidates:=_ranked_candidates(world,category,_rng(world,config,stream))
	var major:=category in ["trade","ruin"]
	var placed:=0
	for candidate: Dictionary in candidates:
		if placed>=count: break
		var cell_id: int=candidate.cell_id
		if occupied.has(cell_id) or not _far_from(world.grid_reference,cell_id,occupied.keys(),config.major_site_spacing if major else config.site_spacing): continue
		if not _far_from(world.grid_reference,cell_id,config.start_cells,config.safe_start_distance): continue
		var data:=world.get_cell(cell_id)
		if major and major_regions.has(data.region_id) and major_regions.size()<world.regions.size(): continue
		var definition:=definitions[placed%definitions.size()]
		occupied[cell_id]=true
		if major: major_regions[data.region_id]=true
		result.site_records.append(_site_record(definition.id,cell_id,data,stream))
		placed+=1

static func _place_sites(world: GeneratedPlanet,config: WorldPopulationConfig,result: WorldPopulationResult,
		occupied: Dictionary,major_regions: Dictionary,definition: WorldSiteDefinition,count: int,stream: String) -> void:
	var rng:=_rng(world,config,stream)
	var candidates:=_ranked_candidates(world,definition.category,rng)
	var major:=definition.category in ["trade","ruin"] and not stream.begins_with("explicit/")
	for candidate: Dictionary in candidates:
		if count<=0: break
		var cell_id: int=candidate.cell_id
		if occupied.has(cell_id) or not _far_from(world.grid_reference,cell_id,occupied.keys(),config.major_site_spacing if major else config.site_spacing): continue
		if not _far_from(world.grid_reference,cell_id,config.start_cells,config.safe_start_distance): continue
		var data:=world.get_cell(cell_id)
		if major and major_regions.has(data.region_id) and major_regions.size()<world.regions.size(): continue
		occupied[cell_id]=true
		if major: major_regions[data.region_id]=true
		result.site_records.append(_site_record(definition.id,cell_id,data,stream))
		count-=1

static func _ranked_candidates(world: GeneratedPlanet,category: String,rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for cell_id in range(world.grid_reference.get_cell_count()):
		var data:=world.get_cell(cell_id)
		if data.hydrology!=null and data.hydrology.surface_water_type!=HydrologyCellData.SurfaceWater.NONE: continue
		var score:=rng.randf()*0.18
		match category:
			"trade": score+=0.45*(1.0-data.terrain_roughness)+0.25*data.fertility+0.2*data.effective_moisture
			"village": score+=0.42*(1.0-data.terrain_roughness)+0.32*data.fertility+0.2*data.effective_moisture
			"resource": score+=0.35*data.fertility+0.25*data.terrain_roughness+0.2*data.effective_moisture
			"ruin": score+=0.45*data.terrain_roughness+0.15*(1.0-data.fertility)
			_: score+=0.2*data.fertility
		result.append({"cell_id":cell_id,"score":score})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return a.score>b.score or (is_equal_approx(a.score,b.score) and a.cell_id<b.cell_id))
	return result

static func _generate_neutrals(world: GeneratedPlanet,registry: ContentRegistry,config: WorldPopulationConfig,
		result: WorldPopulationResult,occupied: Dictionary) -> void:
	var groups: Array[NeutralGroupDefinition]=[]
	var ids:=config.neutral_group_ids.duplicate()
	if ids.is_empty():
		for id: String in ContentRegistry._sorted_keys(registry.neutral_groups):
			if not registry.neutral_groups[id].site_guardian: ids.append(id)
	else: ids.sort()
	for id: String in ids:
		var group:=registry.neutral_group(id)
		if group!=null and not group.site_guardian: groups.append(group)
	var count:=mini(config.maximum_neutral_groups,ceili(world.grid_reference.get_cell_count()*config.neutral_groups_per_1000_cells/1000.0))
	var candidate_sets: Dictionary={}; var cursors: Dictionary={}
	for definition: NeutralGroupDefinition in groups:
		candidate_sets[definition.id]=_ranked_group_candidates(world,definition,_rng(world,config,"neutral_wildlife/"+definition.id))
		cursors[definition.id]=0
	for index in range(count):
		if groups.is_empty(): break
		var definition:=groups[index%groups.size()]
		var candidates: Array=candidate_sets[definition.id]
		while cursors[definition.id]<candidates.size():
			var candidate: Dictionary=candidates[cursors[definition.id]]; cursors[definition.id]+=1
			var cell_id: int=candidate.cell_id
			if occupied.has(cell_id) or not _far_from(world.grid_reference,cell_id,config.start_cells,config.neutral_start_distance): continue
			var homes: Array=[]
			for record: Dictionary in result.neutral_group_records: homes.append(record.cell_id)
			if not _far_from(world.grid_reference,cell_id,homes,config.neutral_spacing): continue
			_append_group(world,definition,cell_id,-1,result,occupied)
			break
	# Site guardians use a separate semantic stream and never affect wildlife placement.
	for site: Dictionary in result.site_records:
		var site_definition:=registry.world_site(site.definition_id)
		if site_definition==null or site_definition.guardian_group_id.is_empty(): continue
		var guardian:=registry.neutral_group(site_definition.guardian_group_id)
		if guardian!=null: _append_group(world,guardian,site.cell_id,site.cell_id,result,occupied)

static func _ranked_group_candidates(world: GeneratedPlanet,definition: NeutralGroupDefinition,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for cell_id in range(world.grid_reference.get_cell_count()):
		var data:=world.get_cell(cell_id)
		if data.hydrology!=null and data.hydrology.surface_water_type!=HydrologyCellData.SurfaceWater.NONE: continue
		var affinity: float=definition.biome_affinities.get(data.dominant_biome,0.15)
		var score:=affinity+0.2*data.fertility+0.12*rng.randf()
		result.append({"cell_id":cell_id,"score":score})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return a.score>b.score or (is_equal_approx(a.score,b.score) and a.cell_id<b.cell_id))
	return result

static func _append_group(world: GeneratedPlanet,definition: NeutralGroupDefinition,home: int,site_cell: int,
		result: WorldPopulationResult,occupied: Dictionary) -> void:
	var controller_id:=53 if not definition.neutral_allegiance_id.is_empty() else (52 if definition.site_guardian else (51 if definition.relationship_policy=="hostile" else 50))
	var composition:=definition.composition.duplicate()
	if composition.is_empty():
		for unit_id: String in definition.unit_ids: composition[unit_id]=composition.get(unit_id,0)+1
	var available: Array[int]=[home]
	var local_traversal:=world.grid_reference.breadth_first(home,2)
	available.append_array(local_traversal.order)
	var unique: Array[int]=[]
	for cell_id: int in available:
		if cell_id not in unique and not occupied.has(cell_id): unique.append(cell_id)
	unique.sort_custom(func(a: int,b: int)->bool:
		var da: int=local_traversal.costs[a]; var db: int=local_traversal.costs[b]
		return da<db or (da==db and a<b))
	var units: Array[Dictionary]=[]
	var cursor:=0
	for unit_id: String in ContentRegistry._sorted_keys(composition):
		for _copy in range(composition[unit_id]):
			if cursor>=unique.size(): break
			var cell_id:=unique[cursor]; cursor+=1; occupied[cell_id]=true
			units.append({"definition_id":unit_id,"cell_id":cell_id})
	if units.is_empty(): return
	result.neutral_group_records.append({"definition_id":definition.id,"cell_id":home,"controller_id":controller_id,
		"relationship_policy":definition.relationship_policy,"awareness_range":definition.awareness_range,
		"leash_distance":definition.leash_distance,"site_cell_id":site_cell,"neutral_allegiance_id":definition.neutral_allegiance_id,"unit_records":units})

static func _site_record(definition_id: String,cell_id: int,data: PlanetWorldCellData,stream: String) -> Dictionary:
	return {"definition_id":definition_id,"cell_id":cell_id,"controller_id":53 if definition_id=="village" else 0,"stream":stream,
		"biome_weights":data.biome_weights.duplicate(),"height":data.height,"moisture":data.effective_moisture,
		"fertility":data.fertility,"roughness":data.terrain_roughness,"region_id":data.region_id}

static func _far_from(grid: PlanetGrid,cell_id: int,others: Array,distance: int) -> bool:
	if distance<=0: return true
	# Spacing asks only about a small exclusion radius, not world-wide distances.
	var nearby:=grid.breadth_first(cell_id,distance-1).costs
	for other in others:
		if nearby.has(int(other)): return false
	return true

static func _rng(world: GeneratedPlanet,config: WorldPopulationConfig,stream: String) -> RandomNumberGenerator:
	var rng:=RandomNumberGenerator.new()
	var seed_source:=config.population_seed if config.population_seed!=0 else world.config.world_seed
	rng.seed=PlanetFieldSampler.derive_seed(seed_source,"world_population/%d/%s" % [config.generation_version,stream])
	return rng
