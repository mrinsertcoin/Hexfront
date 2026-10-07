class_name BiologicalProductionState
extends RefCounted

var recipe_id: String
var progress_turns: int=0
var required_turns: int=0
var nutrients_collected: int=0
var required_nutrients: int=0
var held: bool=false
var outcome_unit_ids: PackedStringArray=[]
var deployment_cell_id: int=-1
var stored_food: int=0
var stored_matter: int=0
var has_consumed: bool=false
var transformation_started_round: int=-1
var transformation_round: int=-1

func _init(recipe: String="",turns: int=0,nutrients: int=0,outcomes: PackedStringArray=[]) -> void:
	recipe_id=recipe; required_turns=turns; required_nutrients=nutrients; outcome_unit_ids=outcomes.duplicate()

func advance() -> void:
	if not held: progress_turns=mini(required_turns,progress_turns+1)
	held=is_complete()

func add_nutrients(amount: int) -> void:
	nutrients_collected=mini(required_nutrients,nutrients_collected+maxi(0,amount))
	held=is_complete()

func is_complete() -> bool:
	if transformation_round>=0: return has_consumed and progress_turns>=required_turns
	return progress_turns>=required_turns and nutrients_collected>=required_nutrients

func consume(food: int,matter: int,current_round: int,transformation_turns: int) -> void:
	stored_food+=maxi(0,food); stored_matter+=maxi(0,matter); has_consumed=true
	nutrients_collected=stored_food+stored_matter
	transformation_started_round=current_round; transformation_round=current_round+transformation_turns
	progress_turns=0; required_turns=transformation_turns; held=false

func snapshot() -> Dictionary:
	return {"recipe_id":recipe_id,"progress_turns":progress_turns,"required_turns":required_turns,
		"nutrients_collected":nutrients_collected,"required_nutrients":required_nutrients,
		"held":held,"outcome_unit_ids":Array(outcome_unit_ids),"deployment_cell_id":deployment_cell_id,
		"stored_food":stored_food,"stored_matter":stored_matter,"has_consumed":has_consumed,
		"transformation_started_round":transformation_started_round,"transformation_round":transformation_round}
