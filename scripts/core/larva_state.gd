class_name LarvaState
extends RefCounted

var id: int
var owner: int
var source_species: String
var cell_id: int
var created_round: int
var maturation_round: int
var successful_outcome: bool
var ready_to_emerge: bool=false

func _init(larva_id: int=0,controller_id: int=0,species: String="",cell: int=-1,created: int=0,matures: int=0,outcome: bool=false) -> void:
	id=larva_id; owner=controller_id; source_species=species; cell_id=cell
	created_round=created; maturation_round=matures; successful_outcome=outcome

func snapshot() -> Dictionary:
	return {"id":id,"owner":owner,"source_species":source_species,"cell_id":cell_id,
		"created_round":created_round,"maturation_round":maturation_round,
		"successful_outcome":successful_outcome,"ready_to_emerge":ready_to_emerge}
