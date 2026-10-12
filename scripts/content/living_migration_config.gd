class_name LivingMigrationConfig
extends Resource
## Provisional, authorable tuning for Living Migration mechanics.

@export var internal_slot_count: int=9
@export var nursery_slot_count: int=9
@export var spider_food_production: int=3
@export var spider_silk_production: int=2
@export var terrain_food_yield: int=4
@export var terrain_regrowth_turns: int=3
@export var caterpillar_nutrients_per_harvest: int=2
@export var spider_base_silk_cost: int=10
@export var spider_silk_cost_per_owned: int=5
@export var spider_construction_turns: int=2
@export var internal_construction_turns: int=2
@export var internal_building_food_cost: int=3
@export var mite_production_interval: int=3
@export var improved_mite_interval: int=2
@export var ant_hill_connection_range: int=2
@export var queen_connection_range: int=2
@export var road_segments_per_turn: int=3
@export var road_food_cost_per_cell: int=0
@export var disconnection_limit: int=2
@export var research_per_building: int=1
@export var food_per_food_building: int=2
@export var synapse_per_synapse_building: int=1
@export var improved_harvest_bonus: int=1
@export var improved_regrowth_reduction: int=1
@export var nursery_development_reduction: int=1
@export var caterpillar_nutrient_bonus: int=1
@export var caterpillar_requirement_reduction: int=1
@export var temporary_lifetime_bonus: int=1
@export var improved_connection_range_bonus: int=1
@export var improved_road_segments_bonus: int=1
@export var improved_synapse_building_bonus: int=1
@export var improved_food_building_bonus: int=1
@export var improved_spider_silk_bonus: int=1
@export var improved_research_building_bonus: int=1
@export var starting_nursery_branch: String="ant_hill"
@export var larva_maturation_rounds: int=5
@export_range(0,100) var larva_success_percent: int=25
@export var larva_interaction_range: int=1
@export var caterpillar_transformation_rounds: int=5
@export var vegetation_nutrients: Dictionary[String,int]={"food":4,"matter":0}
@export var corpse_nutrients: Dictionary[String,int]={"food":0,"matter":4}

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	for value: int in [internal_slot_count,nursery_slot_count,spider_food_production,spider_silk_production,
			terrain_food_yield,terrain_regrowth_turns,caterpillar_nutrients_per_harvest,spider_base_silk_cost,
			spider_silk_cost_per_owned,spider_construction_turns,internal_construction_turns,
			internal_building_food_cost,mite_production_interval,improved_mite_interval,
			ant_hill_connection_range,queen_connection_range,road_segments_per_turn,
			road_food_cost_per_cell,disconnection_limit,research_per_building,
			food_per_food_building,synapse_per_synapse_building,improved_harvest_bonus,
			improved_regrowth_reduction,nursery_development_reduction,caterpillar_nutrient_bonus,caterpillar_requirement_reduction,
			temporary_lifetime_bonus,improved_connection_range_bonus,improved_road_segments_bonus,
			improved_synapse_building_bonus,improved_food_building_bonus,improved_spider_silk_bonus,improved_research_building_bonus,
			larva_maturation_rounds,larva_success_percent,larva_interaction_range,
			caterpillar_transformation_rounds]:
		if value<0: errors.append("Living Migration configuration contains a negative value")
	if internal_slot_count<=0 or nursery_slot_count<=0 or mite_production_interval<=0:
		errors.append("Living Migration slot counts and mite interval must be positive")
	if starting_nursery_branch not in ["","ant_hill","marsh","caterpillar_foliage"]:
		errors.append("Invalid Living Migration starting nursery branch")
	if larva_success_percent>100: errors.append("Larva success percent must be 0..100")
	return errors

func gameplay_record() -> String:
	return var_to_str([
		internal_slot_count,nursery_slot_count,spider_food_production,spider_silk_production,
		terrain_food_yield,terrain_regrowth_turns,caterpillar_nutrients_per_harvest,
		spider_base_silk_cost,spider_silk_cost_per_owned,spider_construction_turns,
		internal_construction_turns,internal_building_food_cost,mite_production_interval,
		improved_mite_interval,ant_hill_connection_range,queen_connection_range,
		road_segments_per_turn,road_food_cost_per_cell,disconnection_limit,
		research_per_building,food_per_food_building,synapse_per_synapse_building,improved_harvest_bonus,
		improved_regrowth_reduction,nursery_development_reduction,caterpillar_nutrient_bonus,caterpillar_requirement_reduction,
		temporary_lifetime_bonus,improved_connection_range_bonus,improved_road_segments_bonus,
		improved_synapse_building_bonus,improved_food_building_bonus,improved_spider_silk_bonus,improved_research_building_bonus,
		starting_nursery_branch,larva_maturation_rounds,larva_success_percent,
		larva_interaction_range,caterpillar_transformation_rounds,vegetation_nutrients,corpse_nutrients])
