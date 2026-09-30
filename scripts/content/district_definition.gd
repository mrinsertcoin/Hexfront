class_name DistrictDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var costs: Dictionary[String,int]={}
@export var upkeep: Dictionary[String,int]={}
@export var turn_production: Dictionary[String,int]={}
@export var construction_turns: int=1
@export var required_unlock_tag: String
@export var tags: PackedStringArray=[]
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or construction_turns<=0:
		errors.append("Invalid district definition: "+id)
	for values: Dictionary in [costs,upkeep,turn_production]:
		for amount: int in values.values():
			if amount<0: errors.append("District %s has a negative resource value" % id)
	if not required_unlock_tag.is_empty() and not ContentRegistry.valid_id(required_unlock_tag):
		errors.append("District %s has invalid unlock tag" % id)
	return errors
