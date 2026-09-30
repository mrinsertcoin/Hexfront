class_name PlanetTerrainRenderer
extends Node3D
## Static 20-face chunks share a welded vertex/normal source; gameplay cells are
## never terrain patches. Godot can frustum-cull the independent face instances.
var world: GeneratedPlanet
var config: TerrainRenderConfig
var surface: TerrainSurfaceSampler
var directions: PackedVector3Array = []
var vertices: PackedVector3Array = []
var normals: PackedVector3Array = []
var faces: Array[Vector3i] = []
var colors: PackedColorArray = []
var uvs: PackedVector2Array = []
var uv2s: PackedVector2Array = []
var chunks: Array[MeshInstance3D] = []
var water: PlanetWaterRenderer
var dressing: WorldDressing
var build_ms: float = 0.0
var triangle_count: int = 0

func rebuild(planet: GeneratedPlanet, settings: TerrainRenderConfig,
		exclusions: Array[Vector3] = []) -> void:
	assert(settings.validate().is_empty(), "Invalid terrain render settings")
	var start: int = Time.get_ticks_usec()
	for child: Node in get_children(): child.free()
	chunks.clear()
	vertices.clear(); normals.clear(); colors.clear(); uvs.clear(); uv2s.clear()
	world = planet
	config = settings.duplicate(true)
	surface = TerrainSurfaceSampler.new(world, config)
	var base := PlanetGrid.new(0)
	directions = base._vertices.duplicate()
	faces = base._faces.duplicate()
	# Each subdivision preserves contiguous original-face groups.
	for level in range(config.terrain_subdivision_level):
		var cache: Dictionary = {}
		var next: Array[Vector3i] = []
		for f: Vector3i in faces:
			var ab: int = _midpoint(f.x,f.y,cache)
			var bc: int = _midpoint(f.y,f.z,cache)
			var ca: int = _midpoint(f.z,f.x,cache)
			next.append_array([Vector3i(f.x,ab,ca), Vector3i(ab,f.y,bc), Vector3i(ca,bc,f.z), Vector3i(ab,bc,ca)])
		faces = next
	for direction: Vector3 in directions:
		vertices.append(surface.sample_position(direction))
		normals.append(Vector3.ZERO)
		var data: PlanetWorldCellData = world.sample_fields(direction)
		var weights: Array[float] = [0,0,0,0,0]
		for i in range(world.config.biomes.size()):
			var slot: int = StylizedTerrainMaterial.IDS.find(world.config.biomes[i].biome_id)
			if slot >= 0: weights[slot] += data.biome_weights[i]
		colors.append(Color(weights[0],weights[1],weights[2],weights[3]))
		uvs.append(Vector2(data.effective_moisture,data.terrain_roughness))
		uv2s.append(Vector2(weights[4],data.hydrology.wetland_potential if data.hydrology != null else 0.0))
	# Area-weighted smooth normals from actual displaced geometry, shared at seams.
	for f: Vector3i in faces:
		var normal: Vector3 = (vertices[f.y]-vertices[f.x]).cross(vertices[f.z]-vertices[f.x])
		for id: int in [f.x,f.y,f.z]: normals[id] += normal
	for i in range(normals.size()): normals[i] = normals[i].normalized()
	var picking_faces := PackedVector3Array()
	for f: Vector3i in faces:
		picking_faces.append_array(PackedVector3Array([vertices[f.x],vertices[f.z],vertices[f.y]]))
	surface.picking_mesh = TriangleMesh.new()
	surface.picking_mesh.create_from_faces(picking_faces)
	var material: ShaderMaterial = StylizedTerrainMaterial.build(config)
	var per_chunk: int = faces.size() / 20
	for chunk in range(20):
		var instance := MeshInstance3D.new()
		instance.name = "TerrainFace_%02d" % chunk
		instance.mesh = _chunk_mesh(chunk * per_chunk, per_chunk)
		instance.material_override = material
		add_child(instance)
		chunks.append(instance)
	water = PlanetWaterRenderer.new()
	add_child(water)
	water.rebuild(world,surface)
	dressing = WorldDressing.new()
	dressing.name = "WorldDressing"
	dressing.exclusion_directions = exclusions.duplicate()
	add_child(dressing)
	dressing.rebuild(world,surface,config.dressing)
	triangle_count = faces.size()
	build_ms = (Time.get_ticks_usec()-start)/1000.0
	print("Terrain render: cells=%d visual_level=%d triangles=%d chunks=20 build_ms=%.1f" % [world.grid_reference.cells.size(),config.terrain_subdivision_level,triangle_count,build_ms])

func _midpoint(a: int, b: int, cache: Dictionary) -> int:
	var key := Vector2i(mini(a,b),maxi(a,b))
	if not cache.has(key):
		cache[key] = directions.size()
		directions.append((directions[a]+directions[b]).normalized())
	return cache[key]

func _chunk_mesh(start: int, count: int) -> ArrayMesh:
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	var points := PackedVector3Array(); var ns := PackedVector3Array(); var cs := PackedColorArray()
	var us := PackedVector2Array(); var vs := PackedVector2Array(); var indices := PackedInt32Array()
	var mapping: Dictionary = {}
	for i in range(start,start+count):
		var f: Vector3i = faces[i]
		for id: int in [f.x,f.z,f.y]: # Clockwise Godot front face.
			if not mapping.has(id):
				mapping[id] = points.size()
				points.append(vertices[id]); ns.append(normals[id]); cs.append(colors[id]); us.append(uvs[id]); vs.append(uv2s[id])
			indices.append(mapping[id])
	arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_NORMAL]=ns; arrays[Mesh.ARRAY_COLOR]=cs
	arrays[Mesh.ARRAY_TEX_UV]=us; arrays[Mesh.ARRAY_TEX_UV2]=vs; arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
