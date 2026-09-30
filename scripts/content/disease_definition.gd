class_name DiseaseDefinition
extends Resource

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var duration_turns: int=1
@export var immunity_turns: int=1
@export var damage_per_turn: int=0
@export var attack_damage_reduction: int=0
@export var unlock_tag: String
@export_file("*.png","*.svg","*.webp") var icon_path: String

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or duration_turns<=0 or immunity_turns<0 \
			or damage_per_turn<0 or attack_damage_reduction<0:
		errors.append("Invalid disease definition: "+id)
	if not unlock_tag.is_empty() and not ContentRegistry.valid_id(unlock_tag):
		errors.append("Invalid disease unlock tag: "+id)
	return errors
