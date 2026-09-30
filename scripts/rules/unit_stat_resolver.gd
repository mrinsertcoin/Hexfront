class_name UnitStatResolver
extends RefCounted
## Single future insertion point for faction and technology modifiers.

static func definition(unit: GameState.Unit,registry: ContentRegistry) -> UnitDefinition:
	return registry.unit(unit.definition_id)

static func movement(unit: GameState.Unit,registry: ContentRegistry) -> int:
	return unit._movement_override if unit._movement_override>=0 else definition(unit,registry).movement

static func attack_range(unit: GameState.Unit,registry: ContentRegistry) -> int:
	var value:=definition(unit,registry).attack_range
	if unit.deployed and definition(unit,registry).deployed_attack_range>0: value=definition(unit,registry).deployed_attack_range
	return value

static func attack_damage(unit: GameState.Unit,registry: ContentRegistry) -> int:
	var value:=definition(unit,registry).attack_damage
	if unit.active_disease!=null: value-=unit.active_disease.attack_damage_reduction
	if unit.deployed and definition(unit,registry).deployed_attack_damage>0: value=definition(unit,registry).deployed_attack_damage
	return maxi(0,value)

static func attack_damage_against(unit: GameState.Unit,target: RefCounted,registry: ContentRegistry) -> int:
	var value:=attack_damage(unit,registry)
	if target.designation!=null and target.designation.source_controller_id==unit.controller_id:
		value+=target.designation.damage_bonus
	return value

static func max_hp(unit: GameState.Unit,registry: ContentRegistry) -> int:
	return definition(unit,registry).max_hp
