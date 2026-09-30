class_name ResourceDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var sort_order: int=0
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id): errors.append("Invalid resource ID: "+id)
	if display_name.is_empty(): errors.append("Resource %s has no display name" % id)
	return errors
