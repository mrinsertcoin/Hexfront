class_name DesignationState
extends RefCounted

var source_controller_id: int
var remaining_turns: int
var damage_bonus: int

func _init(source: int=0,duration: int=0,bonus: int=0) -> void:
	source_controller_id=source; remaining_turns=duration; damage_bonus=bonus

func snapshot() -> Dictionary:
	return {"source_controller_id":source_controller_id,"remaining_turns":remaining_turns,"damage_bonus":damage_bonus}
