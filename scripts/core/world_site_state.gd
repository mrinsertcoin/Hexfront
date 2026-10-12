class_name WorldSiteState
extends RefCounted

var id: int
var definition_id: String
var cell_id: int
var controller_id: int
var runtime_state: Dictionary={}
var hp: int=0
var max_hp: int=0
var designation: DesignationState

func _init(site_id: int=0,definition: String="",cell: int=-1,controller: int=0) -> void:
	id=site_id; definition_id=definition; cell_id=cell; controller_id=controller

func snapshot() -> Dictionary:
	return {"id":id,"definition_id":definition_id,"cell_id":cell_id,"controller_id":controller_id,
		"hp":hp,"max_hp":max_hp,"runtime_state":runtime_state.duplicate(true)}
