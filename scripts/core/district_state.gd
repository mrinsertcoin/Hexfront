class_name DistrictState
extends RefCounted

var id: int
var controller_id: int
var pillar_id: int
var cell_id: int
var definition_id: String
var construction_progress: int=0
var required_turns: int=1
var last_action_serial: int=-1

var completed: bool:
	get: return construction_progress>=required_turns

func _init(district_id: int=0,controller: int=0,pillar: int=0,cell: int=0,definition: String="",turns: int=1) -> void:
	id=district_id; controller_id=controller; pillar_id=pillar; cell_id=cell; definition_id=definition; required_turns=turns

func snapshot() -> Dictionary:
	return {"id":id,"controller_id":controller_id,"pillar_id":pillar_id,"cell_id":cell_id,
		"definition_id":definition_id,"construction_progress":construction_progress,"required_turns":required_turns,
		"last_action_serial":last_action_serial}
