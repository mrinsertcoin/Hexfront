class_name DiseaseState
extends RefCounted

var definition_id: String
var remaining_turns: int
var source_controller_id: int
var damage_per_turn: int
var attack_damage_reduction: int

func _init(id: String="",duration: int=0,source: int=0,dot: int=0,reduction: int=0) -> void:
	definition_id=id; remaining_turns=duration; source_controller_id=source
	damage_per_turn=dot; attack_damage_reduction=reduction

func snapshot() -> Dictionary:
	return {"definition_id":definition_id,"remaining_turns":remaining_turns,
		"source_controller_id":source_controller_id,"damage_per_turn":damage_per_turn,
		"attack_damage_reduction":attack_damage_reduction}
