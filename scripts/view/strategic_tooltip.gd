class_name StrategicTooltip
extends RefCounted
## Shared plain-language tooltip formatting for strategic UI controls.

static func resource(definition: ResourceDefinition,current: int,income: int,upkeep: int) -> String:
	return "%s\n%s\nCurrent: %d\nIncome: %+d\nUpkeep: -%d\nNet next owner turn: %+d" % [
		definition.display_name,definition.description,current,income,upkeep,income-upkeep]

static func unit(definition: UnitDefinition) -> String:
	return "%s\n%s\nCost: %s\nUpkeep: %s\nHP %d | Move %d | Damage %d | Range %d" % [
		definition.display_name,definition.description,record(definition.costs),record(definition.upkeep),
		definition.max_hp,definition.movement,definition.attack_damage,definition.attack_range]

static func technology(definition: TechnologyDefinition,registry: ContentRegistry) -> String:
	var unlocks:=PackedStringArray()
	for id: String in definition.unlock_unit_ids:
		var item:=registry.unit(id); unlocks.append(item.display_name if item!=null else pretty(id))
	for id: String in definition.unlock_structure_ids:
		var item:=registry.structure(id); unlocks.append(item.display_name if item!=null else pretty(id))
	for tag: String in definition.unlock_tags: unlocks.append(pretty(tag))
	return "%s\n%s\nResearch: %d\nUnlocks: %s" % [definition.display_name,definition.description,
		definition.research_cost,", ".join(unlocks) if not unlocks.is_empty() else "No roster unlock"]

static func district(definition: DistrictDefinition) -> String:
	return "%s\n%s\nCost: %s\nBuild time: %d owner turns\nProduction: %s\nUpkeep: %s" % [
		definition.display_name,definition.description,record(definition.costs),definition.construction_turns,
		record(definition.turn_production),record(definition.upkeep)]

static func record(values: Dictionary) -> String:
	if values.is_empty(): return "None"
	var ids: Array[String]=[]
	for id: String in values: ids.append(id)
	ids.sort()
	var parts:=PackedStringArray()
	for id: String in ids: parts.append("%s %d" % [pretty(id),values[id]])
	return ", ".join(parts)

static func pretty(id: String) -> String:
	return id.replace("_"," ").capitalize()
