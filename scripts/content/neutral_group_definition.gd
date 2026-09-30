class_name NeutralGroupDefinition
extends Resource

@export var id: String
@export var display_name: String
@export var unit_ids: PackedStringArray=[]
@export var composition: Dictionary[String,int]={}
@export_enum("neutral","hostile") var relationship_policy: String="neutral"
@export var spawn_tags: PackedStringArray=[]
@export var biome_affinities: Dictionary[String,float]={}
@export var difficulty: int=0
@export_range(1,12) var awareness_range: int=3
@export_range(0,12) var leash_distance: int=3
@export var site_guardian: bool=false

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if not ContentRegistry.valid_id(id) or display_name.is_empty() or (unit_ids.is_empty() and composition.is_empty()) or difficulty<0 \
			or relationship_policy not in ["neutral","hostile"]:
		errors.append("Invalid neutral-group definition: "+id)
	for weight: float in biome_affinities.values():
		if not is_finite(weight) or weight<0.0: errors.append("Neutral group %s has an invalid biome affinity" % id)
	for count: int in composition.values():
		if count<=0: errors.append("Neutral group %s has invalid composition" % id)
	return errors
