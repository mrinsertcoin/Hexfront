class_name CombatOptionDefinition
extends Resource
## Data-only combat stance. Resolver behavior keys off capabilities, not UI labels.

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var requires_target: bool=false
@export_range(0,10000) var damage_reduction: int=0
@export_range(0,10000) var retaliation_damage: int=0
@export_range(0,100) var cooldown_rounds: int=0
@export_range(0,100) var trigger_limit: int=0

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty(): errors.append("Invalid combat option: "+id)
	if damage_reduction<0 or retaliation_damage<0 or cooldown_rounds<0 or trigger_limit<0:
		errors.append("Combat option %s contains a negative value" % id)
	return errors
