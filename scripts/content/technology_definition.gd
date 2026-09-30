class_name TechnologyDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var research_cost: int=0
@export var prerequisite_ids: PackedStringArray=[]
@export var unlock_unit_ids: PackedStringArray=[]
@export var unlock_structure_ids: PackedStringArray=[]
@export var unlock_tags: PackedStringArray=[]
@export var modifier_ids: PackedStringArray=[]
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or research_cost<0:
		errors.append("Invalid technology definition: "+id)
	var seen:={}
	for prerequisite: String in prerequisite_ids:
		if prerequisite==id: errors.append("Technology %s depends on itself" % id)
		if seen.has(prerequisite): errors.append("Technology %s repeats prerequisite %s" % [id,prerequisite])
		seen[prerequisite]=true
	return errors
