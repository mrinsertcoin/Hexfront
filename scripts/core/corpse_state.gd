class_name CorpseState
extends RefCounted

var id: int
var source_definition_id: String
var cell_id: int
var food_value: int
var consumed: bool=false

func _init(corpse_id: int=0,definition_id: String="",cell: int=-1,value: int=0) -> void:
	id=corpse_id; source_definition_id=definition_id; cell_id=cell; food_value=value
