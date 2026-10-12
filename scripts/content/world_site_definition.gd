class_name WorldSiteDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var tags: PackedStringArray=[]
@export var blocks_movement: bool=false
@export var selectable: bool=true
@export var interactable: bool=false
@export_enum("landmark","trade","resource","ruin","village") var category: String="landmark"
@export_enum("none","trade","gather","explore") var interaction_type: String="none"
@export var trade_recipe_ids: PackedStringArray=[]
@export var reward_resources: Dictionary[String,int]={}
@export_range(0,100) var research_progress_reward: int=0
@export_range(0,100) var initial_charges: int=0
@export_range(0,100) var regeneration_turns: int=0
@export var remove_when_exhausted: bool=false
@export var guardian_group_id: String
@export_range(0,10000) var max_hp: int=0
@export var neutral_allegiance_id: String=""
@export var loot_resources: Dictionary[String,int]={}
@export_range(0,100) var loot_research_progress: int=0
@export_range(0.01,10.0) var visual_scale: float=1.0
@export_range(0.0,1.0) var placement_weight: float=1.0
@export var visual_id: String
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or category not in ["landmark","trade","resource","ruin","village"] or interaction_type not in ["none","trade","gather","explore"]:
		errors.append("Invalid world-site definition: "+id)
	if interactable and interaction_type=="none": errors.append("Interactable site %s has no interaction type" % id)
	if interaction_type=="trade" and trade_recipe_ids.is_empty(): errors.append("Trade site %s has no recipes" % id)
	if interaction_type=="gather" and (initial_charges<=0 or reward_resources.is_empty()): errors.append("Resource site %s has no charges/reward" % id)
	for amount: int in reward_resources.values():
		if amount<0: errors.append("Site %s has a negative reward" % id)
	for amount: int in loot_resources.values():
		if amount<0: errors.append("Site %s has negative loot" % id)
	if category=="village" and (max_hp<=0 or neutral_allegiance_id.is_empty() or guardian_group_id.is_empty()):
		errors.append("Village %s requires durability, allegiance, and guardians" % id)
	return errors
