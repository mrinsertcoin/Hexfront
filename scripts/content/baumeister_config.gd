class_name BaumeisterConfig
extends Resource
## Provisional Milestone 14B tuning. Source-defined mechanics remain in rules/state.

@export var max_bridge_distance: int=4
@export var bridge_material_cost_per_edge: int=2
@export var bridge_construction_turns: int=2
@export var bridge_max_hp: int=12
@export var bridge_maintenance_materials: int=1
@export var pillar_max_integrity: int=20
@export var neglected_integrity_loss: int=1
@export var pillar_repair_amount: int=4
@export var bridge_repair_amount: int=4
@export var unit_repair_amount: int=3
@export var repair_material_cost: int=1
@export var supplied_repair_bonus: int=1
@export var integrity_damage_divisor: int=2
@export var bridge_edge_cost: int=1
@export var ordinary_edge_cost: int=2
@export var designation_range: int=3
@export var designation_duration_turns: int=2
@export var designation_damage_bonus: int=1
@export var research_per_civic_monument: int=1
@export var hero_limit: int=1
@export var efficient_bridge_cost_reduction: int=1
@export var improved_bridge_hp_bonus: int=4
@export var improved_bridge_build_reduction: int=1
@export var district_production_bonus: int=1
@export var improved_repair_bonus: int=2
@export var improved_integrity_bonus: int=5
@export var improved_neglect_reduction: int=1

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	for value: int in [max_bridge_distance,bridge_material_cost_per_edge,bridge_construction_turns,
			bridge_max_hp,bridge_maintenance_materials,pillar_max_integrity,neglected_integrity_loss,
			pillar_repair_amount,bridge_repair_amount,unit_repair_amount,repair_material_cost,
			supplied_repair_bonus,integrity_damage_divisor,bridge_edge_cost,ordinary_edge_cost,designation_range,
			designation_duration_turns,designation_damage_bonus,research_per_civic_monument,hero_limit,
			efficient_bridge_cost_reduction,improved_bridge_hp_bonus,improved_bridge_build_reduction,
			district_production_bonus,improved_repair_bonus,improved_integrity_bonus,improved_neglect_reduction]:
		if value<0: errors.append("Baumeister configuration contains a negative value.")
	if max_bridge_distance<=0 or bridge_construction_turns<=0 or bridge_max_hp<=0 or pillar_max_integrity<=0:
		errors.append("Baumeister infrastructure limits must be positive.")
	if bridge_edge_cost<=0 or ordinary_edge_cost<bridge_edge_cost or integrity_damage_divisor<=0: errors.append("Invalid bridge movement or Integrity configuration.")
	return errors

func gameplay_record() -> String:
	return var_to_str([
		max_bridge_distance,bridge_material_cost_per_edge,bridge_construction_turns,bridge_max_hp,
		bridge_maintenance_materials,pillar_max_integrity,neglected_integrity_loss,pillar_repair_amount,
		bridge_repair_amount,unit_repair_amount,repair_material_cost,supplied_repair_bonus,
		integrity_damage_divisor,bridge_edge_cost,ordinary_edge_cost,designation_range,designation_duration_turns,
		designation_damage_bonus,research_per_civic_monument,hero_limit,efficient_bridge_cost_reduction,
		improved_bridge_hp_bonus,improved_bridge_build_reduction,district_production_bonus,
		improved_repair_bonus,improved_integrity_bonus,improved_neglect_reduction])
