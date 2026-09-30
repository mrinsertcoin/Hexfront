class_name TradeRecipeDefinition
extends Resource
## Fixed, deterministic exchange authored independently of site/UI code.

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var input_costs: Dictionary[String,int]={}
@export var output_rewards: Dictionary[String,int]={}
@export var allowed_faction_ids: PackedStringArray=[]
@export_range(1,16) var usage_limit_per_turn: int=1
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or input_costs.is_empty() or output_rewards.is_empty():
		errors.append("Invalid trade recipe: "+id)
	for values: Dictionary in [input_costs,output_rewards]:
		for amount: int in values.values():
			if amount<=0: errors.append("Trade recipe %s has a non-positive resource amount" % id)
	for resource_id: String in input_costs:
		if output_rewards.has(resource_id): errors.append("Trade recipe %s both consumes and produces %s" % [id,resource_id])
	return errors
