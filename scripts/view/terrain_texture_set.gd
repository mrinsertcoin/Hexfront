class_name TerrainTextureSet
extends Resource
## One authored PBR texture set. Files are optional and resolved at startup so a
## partially installed library degrades to neutral maps instead of failing.

const ROOT := "res://assets/environment/terrain/materials/"

@export var material_id: String
@export var albedo: Texture2D
@export var normal_gl: Texture2D
@export var roughness: Texture2D
@export var ambient_occlusion: Texture2D
@export var height: Texture2D
@export var blend_weight: float = 1.0

static func from_folder(id: String, weight: float = 1.0) -> TerrainTextureSet:
	var result := TerrainTextureSet.new()
	result.material_id = id
	result.blend_weight = weight
	result.albedo = _load_map(id, "albedo.png")
	result.normal_gl = _load_map(id, "normal_gl.png")
	result.roughness = _load_map(id, "roughness.png")
	result.ambient_occlusion = _load_map(id, "ao.png")
	result.height = _load_map(id, "height.png")
	return result

static func _load_map(id: String, filename: String) -> Texture2D:
	var path := ROOT + id + "/" + filename
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
