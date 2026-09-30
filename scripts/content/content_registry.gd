class_name ContentRegistry
extends RefCounted
## Authoritative, deterministic lookup for immutable gameplay definitions.

const ROOT:="res://content"
const DEV_ROOT:="res://content_dev"
static var _default_registry: ContentRegistry

var resources: Dictionary[String,ResourceDefinition]={}
var units: Dictionary[String,UnitDefinition]={}
var structures: Dictionary[String,StructureDefinition]={}
var factions: Dictionary[String,FactionDefinition]={}
var technologies: Dictionary[String,TechnologyDefinition]={}
var world_sites: Dictionary[String,WorldSiteDefinition]={}
var neutral_groups: Dictionary[String,NeutralGroupDefinition]={}
var trade_recipes: Dictionary[String,TradeRecipeDefinition]={}
var modifiers: Dictionary[String,ModifierDefinition]={}
var biological_recipes: Dictionary[String,BiologicalRecipeDefinition]={}
var diseases: Dictionary[String,DiseaseDefinition]={}
var districts: Dictionary[String,DistrictDefinition]={}
var fingerprint: String=""
var loaded_paths: PackedStringArray=[]
var _duplicate_errors:=PackedStringArray()

func _init(load_content: bool=true,include_dev: bool=false) -> void:
	if load_content:
		_load_tree(ROOT)
		if include_dev: _load_tree(DEV_ROOT)
		_refresh_fingerprint()

static func default() -> ContentRegistry:
	if _default_registry==null:
		_default_registry=ContentRegistry.new(true,false)
		var errors:=_default_registry.validate()
		assert(errors.is_empty(),"Invalid gameplay content: "+"; ".join(errors))
	return _default_registry

static func reset_default_for_tests() -> void:
	_default_registry=null

static func valid_id(value: String) -> bool:
	if value.is_empty() or value!=value.to_lower() or value.begins_with("_") or value.ends_with("_") or value.contains("__"):
		return false
	for character in value:
		if not (character>="a" and character<="z") and not (character>="0" and character<="9") and character!="_":
			return false
	return true

func _load_tree(root: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)): return
	var paths:=PackedStringArray()
	_collect_paths(root,paths)
	paths.sort()
	for path: String in paths:
		var definition:=load(path)
		if definition is Resource:
			add_definition(definition,path)

func _collect_paths(directory: String,result: PackedStringArray) -> void:
	var files:=PackedStringArray(DirAccess.get_files_at(directory)); files.sort()
	for file: String in files:
		if file.ends_with(".tres"): result.append(directory.path_join(file))
	var directories:=PackedStringArray(DirAccess.get_directories_at(directory)); directories.sort()
	for child: String in directories: _collect_paths(directory.path_join(child),result)

func add_definition(definition: Resource,path: String="memory") -> void:
	var table: Dictionary
	if definition is ResourceDefinition: table=resources
	elif definition is UnitDefinition: table=units
	elif definition is StructureDefinition: table=structures
	elif definition is FactionDefinition: table=factions
	elif definition is TechnologyDefinition: table=technologies
	elif definition is WorldSiteDefinition: table=world_sites
	elif definition is NeutralGroupDefinition: table=neutral_groups
	elif definition is TradeRecipeDefinition: table=trade_recipes
	elif definition is ModifierDefinition: table=modifiers
	elif definition is BiologicalRecipeDefinition: table=biological_recipes
	elif definition is DiseaseDefinition: table=diseases
	elif definition is DistrictDefinition: table=districts
	else:
		_duplicate_errors.append("Unsupported content resource: "+path); return
	var content_id: String=definition.id
	if table.has(content_id): _duplicate_errors.append("Duplicate content ID %s in %s" % [content_id,path])
	else:
		table[content_id]=definition
		loaded_paths.append(path)
	_refresh_fingerprint()

func resource(id: String) -> ResourceDefinition: return resources.get(id)
func unit(id: String) -> UnitDefinition: return units.get(id)
func structure(id: String) -> StructureDefinition: return structures.get(id)
func faction(id: String) -> FactionDefinition: return factions.get(id)
func technology(id: String) -> TechnologyDefinition: return technologies.get(id)
func world_site(id: String) -> WorldSiteDefinition: return world_sites.get(id)
func neutral_group(id: String) -> NeutralGroupDefinition: return neutral_groups.get(id)
func trade_recipe(id: String) -> TradeRecipeDefinition: return trade_recipes.get(id)
func modifier(id: String) -> ModifierDefinition: return modifiers.get(id)
func biological_recipe(id: String) -> BiologicalRecipeDefinition: return biological_recipes.get(id)
func disease(id: String) -> DiseaseDefinition: return diseases.get(id)
func district(id: String) -> DistrictDefinition: return districts.get(id)

func playable_factions() -> Array[FactionDefinition]:
	var result: Array[FactionDefinition]=[]
	for id: String in _sorted_keys(factions):
		if factions[id].playable: result.append(factions[id])
	return result

func validate() -> PackedStringArray:
	var errors:=_duplicate_errors.duplicate()
	for table: Dictionary in [resources,units,structures,factions,technologies,world_sites,neutral_groups,trade_recipes,modifiers,biological_recipes,diseases,districts]:
		for id: String in _sorted_keys(table): errors.append_array(table[id].validate())
	for id: String in _sorted_keys(units):
		var definition: UnitDefinition=units[id]
		for values: Dictionary in [definition.costs,definition.upkeep,definition.turn_production]:
			for resource_id: String in values:
				if not resources.has(resource_id): errors.append("Unit %s references missing resource %s" % [id,resource_id])
	for id: String in _sorted_keys(structures):
		var definition: StructureDefinition=structures[id]
		for values: Dictionary in [definition.costs,definition.upkeep,definition.turn_production]:
			for resource_id: String in values:
				if not resources.has(resource_id): errors.append("Structure %s references missing resource %s" % [id,resource_id])
	for id: String in _sorted_keys(districts):
		var definition: DistrictDefinition=districts[id]
		for values: Dictionary in [definition.costs,definition.upkeep,definition.turn_production]:
			for resource_id: String in values:
				if not resources.has(resource_id): errors.append("District %s references missing resource %s" % [id,resource_id])
	for id: String in _sorted_keys(factions): _validate_faction(factions[id],errors)
	for id: String in _sorted_keys(technologies): _validate_technology(technologies[id],errors)
	for id: String in _sorted_keys(neutral_groups):
		var group: NeutralGroupDefinition=neutral_groups[id]
		for unit_id: String in group.unit_ids:
			if not units.has(unit_id): errors.append("Neutral group %s references missing unit %s" % [id,unit_id])
		for unit_id: String in group.composition:
			if not units.has(unit_id): errors.append("Neutral group %s references missing unit %s" % [id,unit_id])
	for id: String in _sorted_keys(trade_recipes):
		var trade: TradeRecipeDefinition=trade_recipes[id]
		for values: Dictionary in [trade.input_costs,trade.output_rewards]:
			for resource_id: String in values:
				if not resources.has(resource_id): errors.append("Trade recipe %s references missing resource %s" % [id,resource_id])
		_validate_refs(id,"allowed faction",trade.allowed_faction_ids,factions,errors)
	_validate_direct_trade_cycles(errors)
	for id: String in _sorted_keys(world_sites):
		var site: WorldSiteDefinition=world_sites[id]
		_validate_refs(id,"trade recipe",site.trade_recipe_ids,trade_recipes,errors)
		if not site.guardian_group_id.is_empty() and not neutral_groups.has(site.guardian_group_id):
			errors.append("World site %s references missing guardian group %s" % [id,site.guardian_group_id])
		for resource_id: String in site.reward_resources:
			if not resources.has(resource_id): errors.append("World site %s references missing reward resource %s" % [id,resource_id])
	for id: String in _sorted_keys(biological_recipes):
		var recipe: BiologicalRecipeDefinition=biological_recipes[id]
		_validate_refs(id,"outcome unit",recipe.outcome_unit_ids,units,errors)
		for resource_id: String in recipe.costs:
			if not resources.has(resource_id): errors.append("Recipe %s references missing resource %s" % [id,resource_id])
	var order:=technology_order()
	if technologies.size()>0 and order.size()!=technologies.size(): errors.append("Technology prerequisites contain a cycle")
	return errors

func _validate_faction(definition: FactionDefinition,errors: PackedStringArray) -> void:
	_validate_refs(definition.id,"resource",definition.resource_ids,resources,errors)
	_validate_refs(definition.id,"unit roster",definition.unit_roster_ids,units,errors)
	_validate_refs(definition.id,"structure roster",definition.structure_roster_ids,structures,errors)
	_validate_refs(definition.id,"starting unit",definition.starting_unit_ids,units,errors)
	_validate_refs(definition.id,"starting structure",definition.starting_structure_ids,structures,errors)
	_validate_refs(definition.id,"technology",definition.technology_ids,technologies,errors)
	for resource_id: String in definition.starting_resources:
		if not resources.has(resource_id): errors.append("Faction %s starts with missing resource %s" % [definition.id,resource_id])
	for resource_id: String in definition.turn_resource_income:
		if not resources.has(resource_id): errors.append("Faction %s gains missing resource %s" % [definition.id,resource_id])
	for unit_id: String in definition.starting_unit_ids:
		if unit_id not in definition.unit_roster_ids: errors.append("Faction %s starts with unit outside roster: %s" % [definition.id,unit_id])
	for structure_id: String in definition.starting_structure_ids:
		if structure_id not in definition.structure_roster_ids: errors.append("Faction %s starts with structure outside roster: %s" % [definition.id,structure_id])

func _validate_technology(definition: TechnologyDefinition,errors: PackedStringArray) -> void:
	_validate_refs(definition.id,"prerequisite",definition.prerequisite_ids,technologies,errors)
	_validate_refs(definition.id,"unit unlock",definition.unlock_unit_ids,units,errors)
	_validate_refs(definition.id,"structure unlock",definition.unlock_structure_ids,structures,errors)
	_validate_refs(definition.id,"modifier",definition.modifier_ids,modifiers,errors)

func _validate_direct_trade_cycles(errors: PackedStringArray) -> void:
	var ids:=_sorted_keys(trade_recipes)
	for left_index in range(ids.size()):
		var left: TradeRecipeDefinition=trade_recipes[ids[left_index]]
		if left.input_costs.size()!=1 or left.output_rewards.size()!=1: continue
		var left_in: String=left.input_costs.keys()[0]; var left_out: String=left.output_rewards.keys()[0]
		for right_index in range(left_index+1,ids.size()):
			var right: TradeRecipeDefinition=trade_recipes[ids[right_index]]
			if right.input_costs.size()!=1 or right.output_rewards.size()!=1: continue
			if right.input_costs.keys()[0]!=left_out or right.output_rewards.keys()[0]!=left_in: continue
			var returned: int=left.output_rewards[left_out]*right.output_rewards[left_in]
			var spent: int=left.input_costs[left_in]*right.input_costs[left_out]
			if returned>spent: errors.append("Trade recipes %s and %s create a profitable direct cycle" % [left.id,right.id])

func _validate_refs(owner: String,label: String,ids: PackedStringArray,table: Dictionary,errors: PackedStringArray) -> void:
	var seen:={}
	for id: String in ids:
		if seen.has(id): errors.append("%s %s repeats %s" % [owner,label,id])
		elif not table.has(id): errors.append("%s %s references missing ID %s" % [owner,label,id])
		seen[id]=true

func technology_order() -> PackedStringArray:
	var indegree:={}
	var dependents:={}
	for id: String in _sorted_keys(technologies):
		indegree[id]=0; dependents[id]=PackedStringArray()
	for id: String in _sorted_keys(technologies):
		for prerequisite: String in technologies[id].prerequisite_ids:
			if not technologies.has(prerequisite): continue
			indegree[id]=int(indegree[id])+1
			dependents[prerequisite].append(id)
	var ready:=PackedStringArray()
	for id: String in _sorted_keys(technologies):
		if indegree[id]==0: ready.append(id)
	var result:=PackedStringArray()
	while not ready.is_empty():
		ready.sort()
		var id:=ready[0]; ready.remove_at(0); result.append(id)
		var next_ids: PackedStringArray=dependents[id]; next_ids.sort()
		for dependent: String in next_ids:
			indegree[dependent]=int(indegree[dependent])-1
			if indegree[dependent]==0: ready.append(dependent)
	return result

func _refresh_fingerprint() -> void:
	var rows:=PackedStringArray(["hexfront-content-v1"])
	for id: String in _sorted_keys(resources): rows.append("resource:%s" % id)
	for id: String in _sorted_keys(units):
		var d: UnitDefinition=units[id]
		rows.append("unit:%s:%d:%d:%d:%d:%s:%s:%s:%d:%d:%d:%d:%d:%d:%s:%s" % [id,d.max_hp,d.movement,d.attack_range,d.attack_damage,
			_dict_record(d.costs),_dict_record(d.upkeep),_dict_record(d.turn_production),d.corpse_food_value,d.temporary_lifetime_turns,
			d.deployed_attack_range,d.deployed_attack_damage,d.vision_range,d.detection_range,str(d.concealed),",".join(d.tags)])
	for id: String in _sorted_keys(structures):
		var d: StructureDefinition=structures[id]
		rows.append("structure:%s:%d:%s:%s:%s:%s:%d:%d:%s" % [id,d.max_hp,str(d.can_recruit),_dict_record(d.costs),
			_dict_record(d.upkeep),_dict_record(d.turn_production),d.vision_range,d.detection_range,",".join(d.tags)])
	for id: String in _sorted_keys(factions):
		var d: FactionDefinition=factions[id]
		var config_record: String=d.gameplay_config.gameplay_record() if d.gameplay_config!=null and d.gameplay_config.has_method("gameplay_record") else ""
		rows.append("faction:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [id,",".join(d.resource_ids),",".join(d.unit_roster_ids),
			",".join(d.structure_roster_ids),_dict_record(d.starting_resources),_dict_record(d.turn_resource_income),
			",".join(d.starting_unit_ids),",".join(d.starting_structure_ids),config_record])
	for id: String in _sorted_keys(technologies):
		var d: TechnologyDefinition=technologies[id]
		rows.append("technology:%s:%d:%s:%s:%s:%s:%s" % [id,d.research_cost,",".join(d.prerequisite_ids),
			",".join(d.unlock_unit_ids),",".join(d.unlock_structure_ids),",".join(d.unlock_tags),",".join(d.modifier_ids)])
	for id: String in _sorted_keys(world_sites):
		var d: WorldSiteDefinition=world_sites[id]
		rows.append("site:%s:%s:%s:%s:%s:%s:%s:%d:%d:%s:%s" % [id,d.category,d.interaction_type,
			str(d.blocks_movement),",".join(d.trade_recipe_ids),_dict_record(d.reward_resources),str(d.research_progress_reward),
			d.initial_charges,d.regeneration_turns,str(d.remove_when_exhausted),d.guardian_group_id])
	for id: String in _sorted_keys(neutral_groups):
		var d: NeutralGroupDefinition=neutral_groups[id]
		rows.append("neutral:%s:%s:%s:%s:%d:%d:%d:%s" % [id,",".join(d.unit_ids),_dict_record(d.composition),d.relationship_policy,d.difficulty,d.awareness_range,d.leash_distance,str(d.site_guardian)])
	for id: String in _sorted_keys(trade_recipes):
		var d: TradeRecipeDefinition=trade_recipes[id]
		rows.append("trade:%s:%s:%s:%s:%d" % [id,_dict_record(d.input_costs),_dict_record(d.output_rewards),",".join(d.allowed_faction_ids),d.usage_limit_per_turn])
	for id: String in _sorted_keys(modifiers):
		var d: ModifierDefinition=modifiers[id]
		rows.append("modifier:%s:%s:%s:%s" % [id,d.stat_id,d.operation,str(d.value)])
	for id: String in _sorted_keys(biological_recipes):
		var d: BiologicalRecipeDefinition=biological_recipes[id]
		rows.append("recipe:%s:%s:%s:%d:%d:%s" % [id,d.branch_id,_dict_record(d.costs),d.development_turns,d.nutrient_requirement,",".join(d.outcome_unit_ids)])
	for id: String in _sorted_keys(diseases):
		var d: DiseaseDefinition=diseases[id]
		rows.append("disease:%s:%d:%d:%d:%d:%s" % [id,d.duration_turns,d.immunity_turns,d.damage_per_turn,d.attack_damage_reduction,d.unlock_tag])
	for id: String in _sorted_keys(districts):
		var d: DistrictDefinition=districts[id]
		rows.append("district:%s:%s:%s:%s:%d:%s:%s" % [id,_dict_record(d.costs),_dict_record(d.upkeep),
			_dict_record(d.turn_production),d.construction_turns,d.required_unlock_tag,",".join(d.tags)])
	fingerprint="|".join(rows).sha256_text()

static func _sorted_keys(table: Dictionary) -> Array[String]:
	var result: Array[String]=[]
	for key: String in table.keys(): result.append(key)
	result.sort()
	return result

static func _dict_record(values: Dictionary) -> String:
	var parts:=PackedStringArray()
	for key: String in _sorted_keys(values): parts.append("%s=%s" % [key,str(values[key])])
	return ",".join(parts)
