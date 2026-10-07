class_name BalanceAnalysis
extends RefCounted
## Deterministic Alpha 0.1 comparison. It reports timings; it does not make balance decisions.

const REPRESENTATIVE_ARMIES: Dictionary={
	"living_migration":["fighter_ant","fighter_ant","fire_ant","dragonfly","poison_dart_frog","ant_queen"],
	"baumeister":["scout_trike","bridgewright","conqueror_squad","conqueror_squad","assault_tank","long_range_tank","medic_squad"],
}

static func development_timings(registry: ContentRegistry) -> Dictionary:
	var living:=registry.faction("living_migration")
	var builder:=registry.faction("baumeister")
	var lm_config:=living.gameplay_config as LivingMigrationConfig
	var bm_config:=builder.gameplay_config as BaumeisterConfig
	var fighter_recipe:=registry.biological_recipe("fighter_ant_brood")
	var barracks:=registry.district("barracks")
	var lm_research:=registry.technology("lm_symbiotic_foundations")
	var bm_research:=registry.technology("bm_industrial_foundations")
	return {
		"living_migration":{
			"first_additional_production_turn":lm_config.internal_construction_turns+1,
			"first_military_recruit_turn":fighter_recipe.development_turns+1,
			"first_researched_upgrade_turn":lm_config.internal_construction_turns+lm_research.research_cost-1,
			"first_expansion_turn":int(ceil(float(lm_config.spider_base_silk_cost+lm_config.spider_silk_cost_per_owned-living.starting_resources.silk)/float(lm_config.spider_silk_production)))+lm_config.spider_construction_turns,
			"representative_army":_army_record(registry,REPRESENTATIVE_ARMIES.living_migration),
		},
		"baumeister":{
			"first_additional_production_turn":registry.district("mine").construction_turns+1,
			"first_military_recruit_turn":barracks.construction_turns+1,
			"first_researched_upgrade_turn":registry.district("civic_monument").construction_turns+bm_research.research_cost-1,
			"first_expansion_turn":bm_config.bridge_construction_turns+1,
			"representative_army":_army_record(registry,REPRESENTATIVE_ARMIES.baumeister),
		},
	}

static func generate_report(registry: ContentRegistry) -> String:
	var lines:=PackedStringArray([
		"# Hexfront Balance Report — Alpha 0.1",
		"",
		"> All numbers are **provisional Alpha 0.1 values**. This file is generated from gameplay content by `scripts/tools/generate_balance_report.gd`.",
		"",
	])
	var timings:=development_timings(registry)
	for faction: FactionDefinition in registry.playable_factions():
		if faction.id not in ["living_migration","baumeister"]: continue
		lines.append("## "+faction.display_name)
		lines.append("")
		lines.append("- Starting resources: "+resource_record(faction.starting_resources))
		var economy:=_base_economy(registry,faction)
		lines.append("- Base production: "+resource_record(economy.production))
		lines.append("- Starting upkeep: "+resource_record(economy.upkeep))
		lines.append("- Expansion: "+_expansion_record(registry,faction))
		lines.append("- Research: %d technologies; %s" % [faction.technology_ids.size(),_research_cost_record(registry,faction)])
		lines.append("")
		lines.append("| Unit | Cost | Upkeep | HP | Move | Range | Damage | Important ability | Research requirement |")
		lines.append("|---|---:|---:|---:|---:|---:|---:|---|---|")
		for unit_id: String in faction.unit_roster_ids:
			var unit:=registry.unit(unit_id)
			lines.append("| %s | %s | %s | %d | %d | %d | %d | %s | %s |" % [unit.display_name,
				resource_record(unit.costs),resource_record(unit.upkeep),unit.max_hp,unit.movement,unit.attack_range,
				unit.attack_damage,_ability_record(unit),_research_requirement(registry,faction,unit_id)])
		lines.append("")
		var result: Dictionary=timings[faction.id]
		var army: Dictionary=result.representative_army
		lines.append("### Deterministic development comparison")
		lines.append("")
		lines.append("| Measure | Approximate turn/value |")
		lines.append("|---|---:|")
		lines.append("| First additional production | Turn %d |" % result.first_additional_production_turn)
		lines.append("| First military recruit | Turn %d |" % result.first_military_recruit_turn)
		lines.append("| First researched upgrade | Turn %d |" % result.first_researched_upgrade_turn)
		lines.append("| First expansion operational | Turn %d |" % result.first_expansion_turn)
		lines.append("| Representative midgame army | %s; upkeep %s |" % [resource_record(army.cost),resource_record(army.upkeep)])
		lines.append("")
	lines.append("## Simulation assumptions")
	lines.append("")
	lines.append("Timings assume an uncontested opening, one relevant construction started as soon as affordable, no neutral rewards, no combat losses, and one research producer. They are deterministic comparison markers rather than predicted player outcomes.")
	lines.append("")
	return "\n".join(lines)

static func resource_record(values: Dictionary) -> String:
	if values.is_empty(): return "—"
	var parts:=PackedStringArray()
	for id: String in ContentRegistry._sorted_keys(values): parts.append("%d %s" % [values[id],id.capitalize()])
	return ", ".join(parts)

static func _base_economy(registry: ContentRegistry,faction: FactionDefinition) -> Dictionary:
	var production:={}; var upkeep:={}
	for unit_id: String in faction.starting_unit_ids:
		_add(production,registry.unit(unit_id).turn_production); _add(upkeep,registry.unit(unit_id).upkeep)
	for structure_id: String in faction.starting_structure_ids:
		_add(production,registry.structure(structure_id).turn_production); _add(upkeep,registry.structure(structure_id).upkeep)
	if faction.gameplay_config is LivingMigrationConfig:
		var config:=faction.gameplay_config as LivingMigrationConfig
		production.food=production.get("food",0)+config.spider_food_production
		production.silk=production.get("silk",0)+config.spider_silk_production
	return {"production":production,"upkeep":upkeep}

static func _expansion_record(registry: ContentRegistry,faction: FactionDefinition) -> String:
	if faction.gameplay_config is LivingMigrationConfig:
		var config:=faction.gameplay_config as LivingMigrationConfig
		return "additional Spider costs %d Silk, then +%d Silk per owned Spider; %d turns" % [config.spider_base_silk_cost+config.spider_silk_cost_per_owned,config.spider_silk_cost_per_owned,config.spider_construction_turns]
	var config:=faction.gameplay_config as BaumeisterConfig
	return "Pillar costs %d Materials plus %d per bridge edge; %d turns; %d Materials/turn maintenance" % [registry.structure("pillar_city").costs.materials,config.bridge_material_cost_per_edge,config.bridge_construction_turns,config.bridge_maintenance_materials]

static func _research_cost_record(registry: ContentRegistry,faction: FactionDefinition) -> String:
	var parts:=PackedStringArray()
	for id: String in faction.technology_ids:
		var technology:=registry.technology(id)
		parts.append("%s %d" % [technology.display_name,technology.research_cost])
	return "; ".join(parts)

static func _research_requirement(registry: ContentRegistry,faction: FactionDefinition,unit_id: String) -> String:
	for technology_id: String in faction.technology_ids:
		var technology:=registry.technology(technology_id)
		if unit_id in technology.unlock_unit_ids: return technology.display_name
	return "Available at start"

static func _ability_record(unit: UnitDefinition) -> String:
	var important:=PackedStringArray()
	for tag: String in unit.tags:
		if tag in ["mobile_headquarters","terrain_harvester","road_builder","queen_connection_source","disease_carrier",
			"temporary","synaptic","engineer","reconnaissance","capture","armored","deployable_artillery","anti_air",
			"healer","designator","hero"]: important.append(tag.replace("_"," "))
	if unit.deployed_attack_range>0: important.append("deployed range %d / damage %d" % [unit.deployed_attack_range,unit.deployed_attack_damage])
	if unit.temporary_lifetime_turns>0: important.append("%d-turn lifespan" % unit.temporary_lifetime_turns)
	return ", ".join(important) if not important.is_empty() else "standard combatant"

static func _army_record(registry: ContentRegistry,unit_ids: Array) -> Dictionary:
	var cost:={}; var upkeep:={}
	for unit_id: String in unit_ids:
		var unit:=registry.unit(unit_id); _add(cost,unit.costs); _add(upkeep,unit.upkeep)
	return {"units":unit_ids.duplicate(),"cost":cost,"upkeep":upkeep}

static func _add(target: Dictionary,source: Dictionary) -> void:
	for id: String in source: target[id]=target.get(id,0)+int(source[id])
