class_name VisualMap
extends Resource

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
	var p: String = ASSET_FILES.get(kind, "")
	if not p.is_empty() and ResourceLoader.exists(p):
		return load(p) as PackedScene
	var fallback_kind: String="hq" if kind in ["Headquarters","prototype_headquarters"] else kind.to_lower()
	var fallback: String = "res://assets/models/hx_%s_v1.tscn" % fallback_kind
	return load(fallback) as PackedScene if ResourceLoader.exists(fallback) else null

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
