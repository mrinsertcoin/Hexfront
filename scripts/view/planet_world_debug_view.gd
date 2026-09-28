class_name PlanetWorldDebugView
extends MeshInstance3D
## Temporary vertex colors only. Consumes GeneratedPlanet; owns no noise or world rules.
enum Mode { NORMAL, HEIGHT, TEMPERATURE, BASE_MOISTURE, EFFECTIVE_MOISTURE, FERTILITY, TERRAIN_ROUGHNESS,
	DOMINANT_BIOME, BIOME_BLEND, REGIONS, FLOW_DIRECTION, FLOW_ACCUMULATION, DRAINAGE_BASINS,
	LAKES, RIVERS, HYDROLOGY_MOISTURE, WETLAND_POTENTIAL }
const MODE_NAMES: PackedStringArray = ["Normal", "Height", "Temperature", "Base Moisture", "Effective Moisture",
	"Fertility", "Terrain Roughness", "Dominant Biome", "Biome Blend", "Regions", "Flow Direction",
	"Flow Accumulation", "Drainage Basins", "Lakes", "Rivers", "Hydrology Moisture", "Wetland Potential"]
const BIOME_COLORS: Dictionary = {"Grassland": Color("#a7bf53"), "Forest": Color("#236747"),
	"Dryland": Color("#d6a268"), "Rocky": Color("#878ca1"), "Wetland": Color("#4eb6ac")}
const REGION_PALETTE: Array[Color] = [Color("#e87c63"), Color("#5b94e5"), Color("#e3c849"),
	Color("#835ac6"), Color("#53c7a6"), Color("#de78b6"), Color("#a1c65d"), Color("#87d5e4")]
var world: GeneratedPlanet
var terrain_surface: TerrainSurfaceSampler
var mode: int = Mode.NORMAL
var build_ms: float = 0.0
var _meshes: Dictionary[int, ArrayMesh] = {}
var _continuous_arrays: Array = []
var _samples: Array[PlanetWorldCellData] = []
var _region_colors: Array[Color] = []

func _init() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

func set_world(generated: GeneratedPlanet) -> void:
	world = generated
	_meshes.clear()
	_continuous_arrays.clear()
	_samples.clear()
	_color_regions()
	set_mode(mode)

func set_mode(value: int) -> void:
	mode = clampi(value, Mode.NORMAL, Mode.WETLAND_POTENTIAL)
	visible = mode != Mode.NORMAL
	if not visible or world == null:
		return
	var started: int = Time.get_ticks_usec()
	if not _meshes.has(mode):
		if mode == Mode.FLOW_DIRECTION or mode == Mode.RIVERS:
			_meshes[mode] = _line_mesh(mode == Mode.RIVERS)
		elif mode in [Mode.HEIGHT, Mode.TEMPERATURE, Mode.FERTILITY, Mode.TERRAIN_ROUGHNESS, Mode.BIOME_BLEND]:
			_meshes[mode] = _continuous_mesh()
		else:
			_meshes[mode] = _cell_mesh()
	mesh = _meshes[mode]
	build_ms = (Time.get_ticks_usec() - started) / 1000.0

func _continuous_mesh() -> ArrayMesh:
	if _continuous_arrays.is_empty():
		var sphere := SphereMesh.new()
		sphere.radius = world.grid_reference.planet_radius + 0.012
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 128
		sphere.rings = 64
		_continuous_arrays = sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = _continuous_arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			_samples.append(world.sample_fields(vertex))
		if terrain_surface != null:
			for i in range(vertices.size()): vertices[i] = terrain_surface.sample_position(vertices[i],0.06)
			_continuous_arrays[Mesh.ARRAY_VERTEX] = vertices
	var arrays: Array = _continuous_arrays.duplicate()
	var colors := PackedColorArray()
	for sample: PlanetWorldCellData in _samples:
		colors.append(sample_color(sample))
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func _cell_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for cell: PlanetCell in world.grid_reference.cells:
		var polygon: ArrayMesh = PlanetSurface.polygon_mesh(cell, world.grid_reference.planet_radius + 0.06, terrain_surface)
		var arrays: Array = polygon.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices.append_array(points)
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		var color: Color = sample_color(world.get_cell(cell.id))
		for point in range(points.size()):
			colors.append(color)
	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = vertices
	merged[Mesh.ARRAY_NORMAL] = normals
	merged[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	return result

func sample_color(data: PlanetWorldCellData) -> Color:
	match mode:
		Mode.HEIGHT:
			return Color("#253151").lerp(Color("#b0b58a"), data.height * 2.0) if data.height < 0.5 else Color("#b0b58a").lerp(Color("#fff3db"), (data.height - 0.5) * 2.0)
		Mode.TEMPERATURE:
			return Color("#387ec6").lerp(Color("#e65335"), data.temperature)
		Mode.BASE_MOISTURE:
			return Color("#c99755").lerp(Color("#247ba2"), data.base_moisture)
		Mode.EFFECTIVE_MOISTURE:
			return Color("#c99755").lerp(Color("#247ba2"), data.effective_moisture)
		Mode.FERTILITY:
			return Color("#664638").lerp(Color("#89df55"), data.fertility)
		Mode.TERRAIN_ROUGHNESS:
			return Color("#292c3f").lerp(Color("#e4b7e6"), data.terrain_roughness)
		Mode.DOMINANT_BIOME:
			return _biome_color(data.dominant_biome)
		Mode.BIOME_BLEND:
			var color := Color(0, 0, 0, 1)
			for i in range(data.biome_weights.size()):
				var biome: Color = _biome_color(world.config.biomes[i].biome_id)
				color.r += biome.r * data.biome_weights[i]
				color.g += biome.g * data.biome_weights[i]
				color.b += biome.b * data.biome_weights[i]
			return color
		Mode.REGIONS:
			return _region_colors[data.region_id]
		Mode.FLOW_ACCUMULATION:
			return Color("#171c31").lerp(Color("#55d9ff"), pow(data.hydrology.normalized_accumulation, 0.25))
		Mode.DRAINAGE_BASINS:
			return Color.from_hsv(float(PlanetFieldSampler.derive_seed(0, "basin/%d" % data.hydrology.basin_id) % 1000) / 1000.0, 0.65, 0.85)
		Mode.LAKES:
			if data.hydrology.surface_water_type == HydrologyCellData.SurfaceWater.LAKE:
				return Color("#43a9e6") if not world.hydrology.lakes[data.hydrology.lake_id].terminal else Color("#675bd6")
			if data.hydrology.surface_water_type == HydrologyCellData.SurfaceWater.OCEAN: return Color("#174b86")
			return Color("#4d5145")
		Mode.HYDROLOGY_MOISTURE:
			return Color("#3c302c").lerp(Color("#42e0ce"), data.hydrology.hydrology_moisture_bonus / maxf(0.001, world.config.hydrology.lake_moisture_strength))
		Mode.WETLAND_POTENTIAL:
			return Color("#40382d").lerp(Color("#55d58f"), data.hydrology.wetland_potential)
	return Color.WHITE

func _line_mesh(rivers_only: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var radius: float = world.grid_reference.planet_radius + 0.045
	for from_id in range(world.cell_world_data.size()):
		var hydro: HydrologyCellData = world.get_cell(from_id).hydrology
		if hydro.downstream_cell_id < 0 or (rivers_only and hydro.river_class == HydrologyCellData.RiverClass.NONE): continue
		var a: Vector3 = world.grid_reference.get_cell(from_id).center_direction
		var b: Vector3 = world.grid_reference.get_cell(hydro.downstream_cell_id).center_direction
		var color: Color = Color("#4fc8ff").lerp(Color.WHITE, hydro.river_width_factor * 0.55) if rivers_only else Color.from_hsv(float(hydro.basin_id % 12) / 12.0, 0.7, 1.0)
		for step in range(5):
			var p0: Vector3 = a.slerp(b, float(step) / 5.0).normalized() * radius
			var p1: Vector3 = a.slerp(b, float(step + 1) / 5.0).normalized() * radius
			if terrain_surface != null:
				p0 = terrain_surface.sample_position(p0,0.06)
				p1 = terrain_surface.sample_position(p1,0.06)
			vertices.append_array(PackedVector3Array([p0, p1]))
			colors.append_array(PackedColorArray([color, color]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return result

func _biome_color(id: String) -> Color:
	if BIOME_COLORS.has(id):
		return BIOME_COLORS[id]
	return Color.from_hsv(float(PlanetFieldSampler.derive_seed(0, "debug-color/" + id) % 1000) / 1000.0, 0.45, 0.85)

func _color_regions() -> void:
	_region_colors.clear()
	var palette_ids: Array[int] = []
	for region: PlanetRegionData in world.regions:
		var used: Dictionary = {}
		for id: int in region.cell_ids:
			for neighbor: int in world.grid_reference.get_neighbors(id):
				var other: int = world.get_cell(neighbor).region_id
				if other < region.id:
					used[palette_ids[other]] = true
		var chosen: int = 0
		for i in range(REGION_PALETTE.size()):
			if not used.has(i):
				chosen = i
				break
		palette_ids.append(chosen)
		_region_colors.append(REGION_PALETTE[chosen])
