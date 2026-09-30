class_name UnitDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export_range(1,10000) var max_hp: int=1
@export_range(0,100) var movement: int=0
@export_range(0,100) var attack_range: int=0
@export_range(0,10000) var attack_damage: int=0
@export var costs: Dictionary[String,int]={}
@export var upkeep: Dictionary[String,int]={}
@export var turn_production: Dictionary[String,int]={}
@export var corpse_food_value: int=0
@export var temporary_lifetime_turns: int=0
@export var deployed_attack_range: int=0
@export var deployed_attack_damage: int=0
@export_range(0,20) var vision_range: int=2
@export_range(0,20) var detection_range: int=0
@export var concealed: bool=false
@export var tags: PackedStringArray=[]
@export var visual_id: String
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id): errors.append("Invalid unit ID: "+id)
	if display_name.is_empty() or max_hp<=0 or movement<0 or attack_range<0 or attack_damage<0:
		errors.append("Invalid unit definition: "+id)
	for resource_id: String in costs:
		if costs[resource_id]<0: errors.append("Unit %s has a negative cost" % id)
	for amount: int in upkeep.values():
		if amount<0: errors.append("Unit %s has negative upkeep" % id)
	for amount: int in turn_production.values():
		if amount<0: errors.append("Unit %s has negative production" % id)
	if corpse_food_value<0 or temporary_lifetime_turns<0 or deployed_attack_range<0 or deployed_attack_damage<0 or vision_range<0 or detection_range<0:
		errors.append("Unit %s has invalid lifecycle/deployment values" % id)
	return errors
