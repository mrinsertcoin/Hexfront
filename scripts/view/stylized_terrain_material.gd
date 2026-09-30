class_name StylizedTerrainMaterial
extends RefCounted
## Lightweight palette material for the five existing continuous biome fields.

const IDS: Array[String]=["Grassland","Forest","Dryland","Rocky","Wetland"]
const PALETTE: Array[Color]=[
	Color("#71875a"), Color("#3f6048"), Color("#a27c4f"),
	Color("#6d706c"), Color("#405d56"),
]

static func build(config: TerrainRenderConfig) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://assets/terrain/terrain.gdshader")
	material.set_shader_parameter("biome_colors",config.biome_colors)
	material.set_shader_parameter("macro_scale",config.macro_scale)
	material.set_shader_parameter("macro_strength",config.macro_strength)
	material.set_shader_parameter("rock_strength",config.slope_rock_strength)
	material.set_shader_parameter("wet_strength",config.wetness_strength)
	material.set_meta("terrain_pipeline","stylized_palette_v1")
	return material
