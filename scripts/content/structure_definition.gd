class_name StructureDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export_range(1,10000) var max_hp: int=1
@export var tags: PackedStringArray=[]
@export var costs: Dictionary[String,int]={}
@export var upkeep: Dictionary[String,int]={}
@export var turn_production: Dictionary[String,int]={}
@export var can_recruit: bool=false
@export_range(0,20) var vision_range: int=3
@export_range(0,20) var detection_range: int=1
@export var visual_id: String
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or max_hp<=0:
		errors.append("Invalid structure definition: "+id)
	for resource_id: String in costs:
		if costs[resource_id]<0: errors.append("Structure %s has a negative cost" % id)
	for amount: int in upkeep.values():
		if amount<0: errors.append("Structure %s has negative upkeep" % id)
	for amount: int in turn_production.values():
		if amount<0: errors.append("Structure %s has negative production" % id)
	return errors
