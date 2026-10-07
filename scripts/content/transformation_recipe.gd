class_name TransformationRecipe
extends Resource
## Authoritative caterpillar outcome threshold and restriction metadata.

@export var id: String
@export var required_food: int=0
@export var required_matter: int=0
@export var priority: int=0
@export var result_unit_id: String
@export var research_requirement: String
@export var hero_limit: int=0

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or result_unit_id.is_empty() or required_food<0 or required_matter<0 or hero_limit<0:
		errors.append("Invalid transformation recipe: "+id)
	return errors
