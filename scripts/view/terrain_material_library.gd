class_name TerrainMaterialLibrary
extends RefCounted
const IDS: Array[String] = ["Grassland", "Forest", "Dryland", "Rocky", "Wetland"]
static var _warned: bool = false

static func build(config: TerrainRenderConfig) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/terrain/terrain.gdshader")
	var ground: Array[Image] = []
	var normals: Array[Image] = []
	var tints := PackedColorArray()
	var scales := PackedFloat32Array()
	var strengths := PackedFloat32Array()
	var missing: int = 0
	for id: String in IDS:
		var layer := BiomeMaterialDefinition.new()
		for candidate: BiomeMaterialDefinition in config.materials:
			if candidate != null and candidate.biome_id == id: layer = candidate
		var albedo: Image = _image(layer.albedo_texture, config.texture_resolution, Color.WHITE)
		var rough: Image = _image(layer.roughness_texture, config.texture_resolution, Color.WHITE)
		var normal: Image = _image(layer.normal_texture, config.texture_resolution, Color(0.5,0.5,1))
		missing += int(layer.albedo_texture == null)
		for y in range(albedo.get_height()):
			for x in range(albedo.get_width()):
				var color: Color = albedo.get_pixel(x,y)
				if layer.albedo_texture == null:
					# Seamless deterministic placeholder grain; not per-cell texture art.
					var u: float = TAU * x / albedo.get_width()
					var v: float = TAU * y / albedo.get_height()
					var grain: float = 0.91 + 0.012*sin(u*7.0+sin(v*3.0)*2.0) + 0.01*cos(v*11.0+sin(u*5.0)*2.0) + 0.018*sin(u+cos(v*2.0))
					color = Color(grain,grain,grain,1)
				color.a = rough.get_pixel(x,y).r * layer.roughness_multiplier
				albedo.set_pixel(x,y,color)
		albedo.generate_mipmaps()
		normal.generate_mipmaps()
		ground.append(albedo)
		normals.append(normal)
		tints.append(layer.tint)
		scales.append(layer.texture_world_scale)
		strengths.append(layer.normal_strength)
	if missing > 0 and not _warned:
		print("WARNING: Terrain: %d biome albedo maps missing; using deterministic placeholder layers. Assign PBR maps in TerrainRenderConfig.materials." % missing)
		_warned = true
	var ground_array := Texture2DArray.new()
	ground_array.create_from_images(ground)
	var normal_array := Texture2DArray.new()
	normal_array.create_from_images(normals)
	material.set_shader_parameter("ground_maps", ground_array)
	material.set_shader_parameter("normal_maps", normal_array)
	material.set_shader_parameter("layer_tints", tints)
	material.set_shader_parameter("layer_scales", scales)
	material.set_shader_parameter("layer_normals", strengths)
	material.set_shader_parameter("use_normal_maps", config.normal_maps_enabled)
	material.set_shader_parameter("rock_strength", config.slope_rock_strength)
	material.set_shader_parameter("wet_strength", config.wetness_strength)
	return material

static func _image(texture: Texture2D, size: int, fallback: Color) -> Image:
	var result: Image = texture.get_image() if texture != null else null
	if result == null or result.is_empty():
		result = Image.create(size,size,false,Image.FORMAT_RGBA8)
		result.fill(fallback)
	else:
		result = result.duplicate()
		if result.is_compressed(): result.decompress()
		result.convert(Image.FORMAT_RGBA8)
		result.resize(size,size,Image.INTERPOLATE_LANCZOS)
	return result
