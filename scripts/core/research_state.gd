class_name ResearchState
extends RefCounted
## Serializable per-player research progress. Definitions remain in the registry.

var completed_ids: PackedStringArray=[]
var current_technology_id: String=""
var accumulated_progress: int=0

func is_completed(id: String) -> bool:
	return id in completed_ids

func is_available(id: String,registry: ContentRegistry,allowed_ids: PackedStringArray) -> bool:
	if is_completed(id) or not registry.technologies.has(id) or id not in allowed_ids:
		return false
	var definition: TechnologyDefinition=registry.technology(id)
	for prerequisite: String in definition.prerequisite_ids:
		if not is_completed(prerequisite): return false
	return true

func available_technologies(registry: ContentRegistry,allowed_ids: PackedStringArray) -> PackedStringArray:
	var result:=PackedStringArray()
	for id: String in registry.technology_order():
		if is_available(id,registry,allowed_ids): result.append(id)
	return result

func reset() -> void:
	completed_ids.clear(); current_technology_id=""; accumulated_progress=0
