class_name VisualMap
extends Resource

const ModelVisualDefinitionScript = preload("res://scripts/view/model_visual_definition.gd")

const MODEL_VISUAL_PATHS := [
	"res://assets/factions/swarm/units/admiral/visual.tres",
	"res://assets/factions/swarm/units/caterpillar/visual.tres",
	"res://assets/factions/swarm/units/dragonfly/visual.tres",
	"res://assets/factions/swarm/units/fire_ant/visual.tres",
	"res://assets/factions/swarm/units/fire_ant_flamethrowers/visual.tres",
	"res://assets/factions/swarm/units/firefly/visual.tres",
	"res://assets/factions/swarm/units/mite/visual.tres",
	"res://assets/factions/swarm/units/mosquito/visual.tres",
	"res://assets/factions/swarm/units/queen_ant/visual.tres",
	"res://assets/factions/swarm/units/spider/visual.tres",
	"res://assets/factions/swarm/units/warrior_ant/visual.tres",
	"res://assets/factions/swarm/units/worker_ant/visual.tres",
]

var _model_visuals: Dictionary[String,ModelVisualDefinition] = {}
var _model_visual_errors := PackedStringArray()

func _init() -> void:
	for path: String in MODEL_VISUAL_PATHS:
		if not ResourceLoader.exists(path):
			_model_visual_errors.append("Missing model visual profile: " + path)
			continue
		var profile := load(path) as ModelVisualDefinition
		if profile == null:
			_model_visual_errors.append("Invalid model visual profile: " + path)
		elif _model_visuals.has(profile.id):
			_model_visual_errors.append("Duplicate model visual ID %s in %s" % [profile.id, path])
		else:
			_model_visuals[profile.id] = profile

# Central mapping from unit/structure type to visual scene or GLB path.
# These paths are replaceable by swapping the files at these locations.
const UNIT_SCENES: Dictionary = {
	"Infantry": "res://scenes/visuals/units/infantry_visual.tscn",
	"Scout": "res://scenes/visuals/units/scout_visual.tscn",
	"Gunner": "res://scenes/visuals/units/gunner_visual.tscn",
	"prototype_infantry": "res://scenes/visuals/units/infantry_visual.tscn",
	"prototype_scout": "res://scenes/visuals/units/scout_visual.tscn",
	"prototype_gunner": "res://scenes/visuals/units/gunner_visual.tscn",
}

const STRUCTURE_SCENES: Dictionary = {
	"Headquarters": "res://scenes/visuals/structures/hq_visual.tscn",
	"prototype_headquarters": "res://scenes/visuals/structures/hq_visual.tscn",
}

# Optional direct asset GLB/SCN paths (prefer instantiated wrapper scenes, but fall back to raw assets)
const ASSET_FILES: Dictionary = {
	"Infantry": "res://assets/hx_infantry_v1.glb",
	"Scout": "res://assets/hx_scout_v1.glb",
	"Gunner": "res://assets/hx_gunner_v1.glb",
	"Headquarters": "res://assets/hx_hq_v1.glb",
	"prototype_infantry": "res://assets/hx_infantry_v1.glb",
	"prototype_scout": "res://assets/hx_scout_v1.glb",
	"prototype_gunner": "res://assets/hx_gunner_v1.glb",
	"prototype_headquarters": "res://assets/hx_hq_v1.glb",
}

func asset_scene(kind: String) -> PackedScene:
	var profile := model_definition(kind)
	if profile != null:
		return load(profile.model_path) as PackedScene
	var p: String = ASSET_FILES.get(kind, "")
	if not p.is_empty() and ResourceLoader.exists(p):
		return load(p) as PackedScene
	var fallback_kind: String="hq" if kind in ["Headquarters","prototype_headquarters"] else kind.to_lower()
	var fallback: String = "res://assets/models/hx_%s_v1.tscn" % fallback_kind
	return load(fallback) as PackedScene if ResourceLoader.exists(fallback) else null

func model_definition(kind: String) -> ModelVisualDefinition:
	return _model_visuals.get(kind)

func registered_model_ids() -> PackedStringArray:
	var result := PackedStringArray(_model_visuals.keys())
	result.sort()
	return result

func has_real_model(kind: String) -> bool:
	return _model_visuals.has(kind)

func validation_errors() -> PackedStringArray:
	var result := _model_visual_errors.duplicate()
	for visual_id: String in registered_model_ids():
		result.append_array(_model_visuals[visual_id].validate())
	return result

func has_unit_scene(kind: String) -> bool:
	return ResourceLoader.exists(UNIT_SCENES.get(kind, ""))

func unit_scene(kind: String) -> PackedScene:
	var p: String = UNIT_SCENES.get(kind, "")
	if not p.is_empty() and ResourceLoader.exists(p):
		return load(p) as PackedScene
	return null

func has_structure_scene(kind: String) -> bool:
	return ResourceLoader.exists(STRUCTURE_SCENES.get(kind, ""))

func structure_scene(kind: String) -> PackedScene:
	var p: String = STRUCTURE_SCENES.get(kind, "")
	if not p.is_empty() and ResourceLoader.exists(p):
		return load(p) as PackedScene
	return null
