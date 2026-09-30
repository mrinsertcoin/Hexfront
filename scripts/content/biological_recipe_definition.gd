class_name BiologicalRecipeDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export_enum("ant_hill","marsh","caterpillar_foliage") var branch_id: String="ant_hill"
@export var costs: Dictionary[String,int]={}
@export var development_turns: int=1
@export var nutrient_requirement: int=0
@export var outcome_unit_ids: PackedStringArray=[]
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or development_turns<0 or nutrient_requirement<0:
		errors.append("Invalid biological recipe: "+id)
	if branch_id not in ["ant_hill","marsh","caterpillar_foliage"] or outcome_unit_ids.is_empty():
		errors.append("Biological recipe %s has invalid branch/outcomes" % id)
	for amount: int in costs.values():
		if amount<0: errors.append("Biological recipe %s has a negative cost" % id)
	return errors
