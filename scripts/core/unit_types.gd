class_name UnitTypes
extends RefCounted
## Transitional name adapter. Gameplay values come only from ContentRegistry.

const IDS: Array[String]=["prototype_infantry","prototype_scout","prototype_gunner"]

static func definition_id(value: String) -> String:
	if ContentRegistry.default().units.has(value): return value
	var normalized:=value.strip_edges().to_lower()
	for id: String in IDS:
		var definition:=ContentRegistry.default().unit(id)
		if definition.display_name.to_lower()==normalized: return id
	return ""

static func definition(value: String) -> UnitDefinition:
	return ContentRegistry.default().unit(definition_id(value))

static func display_name(value: String) -> String:
	var result:=definition(value)
	return result.display_name if result!=null else value

static func stats(value: String) -> Dictionary:
	var result:=definition(value)
	if result==null: return {}
	return {"hp":result.max_hp,"movement":result.movement,"range":result.attack_range,"damage":result.attack_damage}

static func material_cost(value: String) -> int:
	var result:=definition(value)
	return result.costs.get("materials",0) if result!=null else 0
