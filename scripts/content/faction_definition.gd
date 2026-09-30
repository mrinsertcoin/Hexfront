class_name FactionDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var playable: bool=true
@export var resource_ids: PackedStringArray=[]
@export var unit_roster_ids: PackedStringArray=[]
@export var structure_roster_ids: PackedStringArray=[]
@export var starting_resources: Dictionary[String,int]={}
@export var turn_resource_income: Dictionary[String,int]={}
@export var starting_unit_ids: PackedStringArray=[]
@export var starting_structure_ids: PackedStringArray=[]
@export var technology_ids: PackedStringArray=[]
@export var visual_theme_id: String
@export var music_id: String
@export var gameplay_config: Resource

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty(): errors.append("Invalid faction definition: "+id)
	for amount: int in starting_resources.values():
		if amount<0: errors.append("Faction %s has negative starting resources" % id)
	for amount: int in turn_resource_income.values():
		if amount<0: errors.append("Faction %s has negative turn income" % id)
	if gameplay_config!=null and gameplay_config.has_method("validate"):
		errors.append_array(gameplay_config.validate())
	return errors
