class_name CombatIntent
extends RefCounted

var controller_id: int
var unit_id: int
var option_id: String
var target_id: int=-1
var submitted_round: int

func _init(controller: int=0,unit: int=0,option: String="",target: int=-1,round: int=0) -> void:
	controller_id=controller; unit_id=unit; option_id=option; target_id=target; submitted_round=round

func snapshot() -> Dictionary:
	return {"controller_id":controller_id,"unit_id":unit_id,"option_id":option_id,
		"target_id":target_id,"submitted_round":submitted_round}
