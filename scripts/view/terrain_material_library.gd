class_name TerrainMaterialLibrary
extends RefCounted
## Packs the authored 2K library into compact runtime texture arrays. Primary
## layers preserve the five-biome shader contract; secondary sets are composed
## once on the CPU so the fragment shader never loops over all eleven sources.

const IDS: Array[String] = ["Grassland", "Forest", "Dryland", "Rocky", "Wetland"]
static var _warned: bool = false
static var _packed_cache: Dictionary[String, Array] = {}
static var _composite_cache: Dictionary[String, Array] = {}

static func build(config: TerrainRenderConfig) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/terrain/terrain.gdshader")
	var primary_ground: Array[Image] = []
	var primary_surface: Array[Image] = []
	var detail_ground: Array[Image] = []
	var detail_surface: Array[Image] = []
	var tints := PackedColorArray()
	var scales := PackedFloat32Array()
	var detail_scales := PackedFloat32Array()
	var details := PackedFloat32Array()
	var strengths := PackedFloat32Array()
	var missing: Dictionary[String, bool] = {}
	for id: String in IDS:
		var layer := _definition(config, id)
		var primary_sets: Array[TerrainTextureSet] = []
		if layer.primary != null: primary_sets.append(layer.primary)
		var base := _composite(primary_sets, config.texture_resolution, id, layer.roughness_multiplier, missing)
		var secondary_sets := layer.secondary
		var detail := _composite(secondary_sets if not secondary_sets.is_empty() else primary_sets,
			config.texture_resolution, id + " detail", layer.roughness_multiplier, missing)
		primary_ground.append(base[0]); primary_surface.append(base[1])
		detail_ground.append(detail[0]); detail_surface.append(detail[1])
		tints.append(layer.tint)
		scales.append(layer.texture_world_scale)
		detail_scales.append(layer.detail_world_scale)
		details.append(layer.detail_strength if not secondary_sets.is_empty() else 0.0)
		strengths.append(layer.normal_strength)
	if not missing.is_empty() and not _warned:
		print("WARNING: Terrain PBR: %d maps unavailable across [%s]; neutral fallbacks active." % [
			missing.size(), ", ".join(missing.keys())])
		_warned = true
	material.set_shader_parameter("ground_maps", _array(primary_ground))
	material.set_shader_parameter("normal_maps", _array(primary_surface))
	material.set_shader_parameter("detail_maps", _array(detail_ground))
	material.set_shader_parameter("detail_normal_maps", _array(detail_surface))
	material.set_shader_parameter("layer_tints", tints)
	material.set_shader_parameter("layer_scales", scales)
	material.set_shader_parameter("detail_scales", detail_scales)
	material.set_shader_parameter("layer_details", details)
	material.set_shader_parameter("layer_normals", strengths)
	material.set_shader_parameter("use_normal_maps", config.normal_maps_enabled)
	material.set_shader_parameter("rock_strength", config.slope_rock_strength)
	material.set_shader_parameter("wet_strength", config.wetness_strength)
	return material

static func _definition(config: TerrainRenderConfig, id: String) -> BiomeMaterialDefinition:
	for candidate: BiomeMaterialDefinition in config.materials:
		if candidate != null and candidate.biome_id == id:
			return candidate
	var fallback := BiomeMaterialDefinition.new()
	fallback.biome_id = id
	return fallback

static func _composite(sets: Array[TerrainTextureSet], size: int, label: String,
		roughness_multiplier: float, missing: Dictionary[String, bool]) -> Array[Image]:
	if sets.is_empty():
		sets = [TerrainTextureSet.new()]
	var signature := "%d:%.4f" % [size, roughness_multiplier]
	for texture_set: TerrainTextureSet in sets:
		signature += ":%s:%.4f" % [texture_set.material_id, texture_set.blend_weight]
	if _composite_cache.has(signature):
		return _composite_cache[signature]
	var packed: Array[Array] = []
	var total_weight := 0.0
	for texture_set: TerrainTextureSet in sets:
		var weight := maxf(texture_set.blend_weight, 0.0)
		if weight <= 0.0: continue
		packed.append([_pack_set(texture_set, size, label, roughness_multiplier, missing), weight])
		total_weight += weight
	if packed.is_empty():
		packed.append([_pack_set(TerrainTextureSet.new(), size, label, roughness_multiplier, missing), 1.0])
		total_weight = 1.0
	if packed.size() == 1:
		var single: Array[Image] = packed[0][0]
		_composite_cache[signature] = single
		return single
	var byte_count := size * size * 4
	var ground_bytes := PackedByteArray(); ground_bytes.resize(byte_count)
	var surface_bytes := PackedByteArray(); surface_bytes.resize(byte_count)
	var sources: Array[Array] = []
	for source: Array in packed:
		sources.append([(source[0][0] as Image).get_data(),
			(source[0][1] as Image).get_data(), source[1] / total_weight])
	# Byte-array composition avoids millions of get_pixel/set_pixel calls during
	# startup while producing the same deterministic weighted result.
	for offset in range(byte_count):
		var ground_value := 0.0
		var surface_value := 0.0
		for source: Array in sources:
			ground_value += source[0][offset] * source[2]
			surface_value += source[1][offset] * source[2]
		ground_bytes[offset] = clampi(roundi(ground_value), 0, 255)
		surface_bytes[offset] = clampi(roundi(surface_value), 0, 255)
	var ground := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, ground_bytes)
	var surface := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, surface_bytes)
	ground.generate_mipmaps(); surface.generate_mipmaps()
	var result: Array[Image] = [ground, surface]
	_composite_cache[signature] = result
	return result

static func _pack_set(texture_set: TerrainTextureSet, size: int, label: String,
		roughness_multiplier: float, missing: Dictionary[String, bool]) -> Array[Image]:
	var cache_key := "%s:%d:%.4f" % [texture_set.material_id, size, roughness_multiplier]
	if not texture_set.material_id.is_empty() and _packed_cache.has(cache_key):
		return _packed_cache[cache_key]
	var albedo := _image(texture_set.albedo, size, Color.WHITE, true)
	var normal := _image(texture_set.normal_gl, size, Color(0.5, 0.5, 1.0), false)
	var roughness := _image(texture_set.roughness, size, Color.WHITE, false)
	var ao := _image(texture_set.ambient_occlusion, size, Color.WHITE, false)
	var height := _image(texture_set.height, size, Color(0.5, 0.5, 0.5), false)
	var maps := {
		"albedo": texture_set.albedo, "normal": texture_set.normal_gl,
		"roughness": texture_set.roughness, "ao": texture_set.ambient_occlusion,
		"height": texture_set.height,
	}
	for map_name: String in maps:
		if maps[map_name] == null:
			missing["%s/%s" % [texture_set.material_id if not texture_set.material_id.is_empty() else label, map_name]] = true
	var albedo_bytes := albedo.get_data()
	var normal_bytes := normal.get_data()
	var roughness_bytes := roughness.get_data()
	var ao_bytes := ao.get_data()
	var height_bytes := height.get_data()
	var byte_count := size * size * 4
	var ground_bytes := PackedByteArray(); ground_bytes.resize(byte_count)
	var surface_bytes := PackedByteArray(); surface_bytes.resize(byte_count)
	for offset in range(0, byte_count, 4):
		ground_bytes[offset] = albedo_bytes[offset]
		ground_bytes[offset + 1] = albedo_bytes[offset + 1]
		ground_bytes[offset + 2] = albedo_bytes[offset + 2]
		ground_bytes[offset + 3] = clampi(roundi(roughness_bytes[offset] * roughness_multiplier), 0, 255)
		# RG keeps the OpenGL tangent normal. Height and AO occupy otherwise
		# unused channels and never affect authoritative geometry.
		surface_bytes[offset] = normal_bytes[offset]
		surface_bytes[offset + 1] = normal_bytes[offset + 1]
		surface_bytes[offset + 2] = height_bytes[offset]
		surface_bytes[offset + 3] = ao_bytes[offset]
	var ground := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, ground_bytes)
	var surface := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, surface_bytes)
	ground.generate_mipmaps(); surface.generate_mipmaps()
	var result: Array[Image] = [ground, surface]
	if not texture_set.material_id.is_empty(): _packed_cache[cache_key] = result
	return result

static func _image(texture: Texture2D, size: int, fallback: Color, color_map: bool) -> Image:
	var result: Image = texture.get_image() if texture != null else null
	if result == null or result.is_empty():
		result = Image.create(size, size, false, Image.FORMAT_RGBA8)
		result.fill(fallback)
	else:
		result = result.duplicate()
		if result.is_compressed(): result.decompress()
		result.convert(Image.FORMAT_RGBA8)
		result.resize(size, size, Image.INTERPOLATE_LANCZOS if color_map else Image.INTERPOLATE_BILINEAR)
	return result

static func _array(images: Array[Image]) -> Texture2DArray:
	var result := Texture2DArray.new()
	result.create_from_images(images)
	return result
