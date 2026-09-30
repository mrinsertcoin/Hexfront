class_name ModifierDefinition
extends Resource

@export var id: String
@export var stat_id: String
@export var operation: String="add"
@export var value: float=0.0

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or not ContentRegistry.valid_id(stat_id) or operation not in ["add","multiply"]:
		errors.append("Invalid modifier definition: "+id)
	return errors
