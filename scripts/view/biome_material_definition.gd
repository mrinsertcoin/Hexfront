class_name BiomeMaterialDefinition
extends Resource
## Visual-only layer. Assign seamless maps in assets/terrain/<biome>/.
@export var biome_id: String = "Grassland"
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
@export var tint: Color = Color.WHITE
@export var texture_world_scale: float = 1.25
@export var normal_strength: float = 0.25
@export var roughness_multiplier: float = 0.9

static func defaults() -> Array[BiomeMaterialDefinition]:
	var result: Array[BiomeMaterialDefinition] = []
	var ids: Array[String] = ["Grassland", "Forest", "Dryland", "Rocky", "Wetland"]
	var colors: Array[Color] = [Color("#75834b"), Color("#344c32"), Color("#b39867"), Color("#7b7c77"), Color("#465849")]
	for i in range(ids.size()):
		var layer := BiomeMaterialDefinition.new()
		layer.biome_id = ids[i]
		layer.tint = colors[i]
		result.append(layer)
	return result
