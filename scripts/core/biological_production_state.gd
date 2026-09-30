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

func _init(recipe: String="",turns: int=0,nutrients: int=0,outcomes: PackedStringArray=[]) -> void:
	recipe_id=recipe; required_turns=turns; required_nutrients=nutrients; outcome_unit_ids=outcomes.duplicate()

func advance() -> void:
	if not held: progress_turns=mini(required_turns,progress_turns+1)
	held=is_complete()

func add_nutrients(amount: int) -> void:
	nutrients_collected=mini(required_nutrients,nutrients_collected+maxi(0,amount))
	held=is_complete()

func is_complete() -> bool:
	return progress_turns>=required_turns and nutrients_collected>=required_nutrients

func snapshot() -> Dictionary:
	return {"recipe_id":recipe_id,"progress_turns":progress_turns,"required_turns":required_turns,
		"nutrients_collected":nutrients_collected,"required_nutrients":required_nutrients,
		"held":held,"outcome_unit_ids":Array(outcome_unit_ids),"deployment_cell_id":deployment_cell_id}
