class_name PlanetWaterRenderer
extends Node3D
## Water consumes authoritative segment/lake IDs. No drainage generation here.
var river_mesh: MeshInstance3D
var lake_meshes: Array[MeshInstance3D] = []
var segment_ranges: Dictionary = {}
var surface: TerrainSurfaceSampler
var world: GeneratedPlanet

func rebuild(planet: GeneratedPlanet, sampler: TerrainSurfaceSampler) -> void:
	world = planet; surface = sampler
	if world.hydrology == null: return
	_build_rivers()
	for lake: LakeData in world.hydrology.lakes: _build_lake(lake)
	if world.config.hydrology.enable_oceans:
		var ocean := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = world.grid_reference.planet_radius + surface.mapped_world_height(world.config.hydrology.sea_level)
		sphere.height = sphere.radius*2; sphere.radial_segments=128; sphere.rings=64
		ocean.mesh=sphere; ocean.material_override=_material(true); add_child(ocean)

func width_for(segment: RiverSegment) -> float:
	return lerpf(surface.config.river_min_width,surface.config.river_max_width,segment.width_factor)

func _material(lake: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/terrain/water.gdshader")
	material.set_shader_parameter("calmness", 0.9 if lake else 0.45)
	return material

func _water_point(direction: Vector3, from: int, to: int, t: float) -> Vector3:
	var radius: float = surface.radius_at(direction)
	# Blend banks into each authoritative lake radius; avoid a ribbon end gap.
	for pair: Vector2 in [Vector2(from,1.0-smoothstep(0.0,0.35,t)),Vector2(to,smoothstep(0.65,1.0,t))]:
		var lake_id: int = world.hydrology.cells[int(pair.x)].lake_id
		if lake_id >= 0:
			var level: float = world.grid_reference.planet_radius + surface.mapped_world_height(world.hydrology.lakes[lake_id].surface_height)
			radius = lerpf(radius,maxf(radius,level),pair.y)
	return direction.normalized()*(radius+surface.config.water_offset)

func _build_rivers() -> void:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array()
	var incoming: Dictionary = {}
	for segment: RiverSegment in world.hydrology.river_segments:
		if not incoming.has(segment.to_cell_id) or segment.accumulation > incoming[segment.to_cell_id].accumulation:
			incoming[segment.to_cell_id] = segment
	for segment: RiverSegment in world.hydrology.river_segments:
		var from: int = segment.from_cell_id; var to: int = segment.to_cell_id
		var first: Vector3 = world.grid_reference.cells[from].up
		var last: Vector3 = world.grid_reference.cells[to].up
		var chord: float = first.distance_to(last)
		var before: Vector3 = world.grid_reference.cells[incoming[from].from_cell_id].up if incoming.has(from) else (2.0*first-last).normalized()
		var after_id: int = world.hydrology.cells[to].downstream_cell_id
		var after: Vector3 = world.grid_reference.cells[after_id].up if after_id >= 0 else (2.0*last-first).normalized()
		var ta: Vector3 = (last-before).normalized()*chord
		var tb: Vector3 = (after-first).normalized()*chord
		var steps: int = maxi(8,ceili(chord*world.grid_reference.planet_radius/surface.config.river_sample_spacing))
		var width: float = width_for(segment)
		var start: int = vertices.size()
		var lefts: PackedVector3Array=[]; var rights: PackedVector3Array=[]
		for i in range(steps+1):
			var t: float = float(i)/steps
			var t2: float=t*t; var t3: float=t2*t
			var p: Vector3 = ((2*t3-3*t2+1)*first + (t3-2*t2+t)*ta + (-2*t3+3*t2)*last + (t3-t2)*tb).normalized()
			# Constrain smoothing close to the original great-circle route.
			p = first.slerp(last,t).slerp(p,0.5).normalized()
			var tangent: Vector3 = ((6*t2-6*t)*first+(3*t2-4*t+1)*ta+(-6*t2+6*t)*last+(3*t2-2*t)*tb).normalized()
			var side: Vector3 = tangent.cross(p).normalized()*width*0.5/world.grid_reference.planet_radius
			lefts.append(_water_point((p-side).normalized(),from,to,t))
			rights.append(_water_point((p+side).normalized(),from,to,t))
		for i in range(steps):
			for item: Vector2i in [Vector2i(i,0),Vector2i(i+1,0),Vector2i(i,1),Vector2i(i,1),Vector2i(i+1,0),Vector2i(i+1,1)]:
				var point: Vector3 = lefts[item.x] if item.y==0 else rights[item.x]
				vertices.append(point); normals.append(point.normalized()); uv.append(Vector2(item.y,float(item.x)/steps))
		segment_ranges[from]=Vector2i(start,vertices.size()-start)
		# Small shared-center patches close confluences without complex fluid joins.
		var center: Vector3 = _water_point(last,from,to,1.0)
		var basis: Basis = PlanetCell.tangent_basis(last)
		for wedge in range(10):
			var a: float=TAU*wedge/10.0; var b: float=TAU*(wedge+1)/10.0
			for point: Vector3 in [center,center+(basis.x*cos(a)+basis.z*sin(a))*width*0.55,center+(basis.x*cos(b)+basis.z*sin(b))*width*0.55]:
				vertices.append(point); normals.append(last); uv.append(Vector2(0.5,0.5))
	if vertices.is_empty(): return
	river_mesh=MeshInstance3D.new(); river_mesh.name="RiverRibbons"
	river_mesh.mesh=_mesh(vertices,normals,uv); river_mesh.material_override=_material()
	add_child(river_mesh)

func _build_lake(lake: LakeData) -> void:
	# Weld cell corners before smoothing only the exterior boundary. Shared internal
	# edges use identical vertices; one merged water surface per authoritative lake.
	var points: Array[Vector3] = []
	var mapping: Dictionary = {}; var edges: Dictionary = {}; var polygons: Array[Array] = []
	for id: int in lake.cell_ids:
		var polygon: Array[int] = []
		for vertex: Vector3 in world.grid_reference.cells[id].polygon_vertices:
			var direction: Vector3=vertex.normalized()
			var key := Vector3i((direction*1000000.0).round())
			if not mapping.has(key): mapping[key]=points.size(); points.append(direction)
			polygon.append(mapping[key])
		polygons.append(polygon)
		for i in range(polygon.size()):
			var a: int=polygon[i]; var b: int=polygon[(i+1)%polygon.size()]
			var edge := Vector2i(mini(a,b),maxi(a,b))
			edges[edge]=int(edges.get(edge,0))+1
	var boundary: Dictionary = {}
	for edge: Vector2i in edges:
		if edges[edge]!=1: continue
		for id: int in [edge.x,edge.y]:
			if not boundary.has(id): boundary[id]=[]
		boundary[edge.x].append(edge.y); boundary[edge.y].append(edge.x)
	for iteration in range(2):
		var updated: Array[Vector3]=points.duplicate()
		for id: int in boundary:
			var average: Vector3=Vector3.ZERO
			for neighbor: int in boundary[id]: average+=points[neighbor]
			updated[id]=points[id].lerp(average.normalized(),0.25).normalized()
		points=updated
	var contour: Array[Vector3] = []
	var first: int = int(boundary.keys()[0])
	var previous: int = -1
	var cursor: int = first
	while contour.is_empty() or cursor != first:
		contour.append(points[cursor])
		var next: int = boundary[cursor][0]
		if next == previous and boundary[cursor].size() > 1: next = boundary[cursor][1]
		previous = cursor
		cursor = next
		if contour.size() > boundary.size(): break
	# Corner-cutting rounds only the external shore inside a fraction of a cell.
	for iteration in range(2):
		var smooth: Array[Vector3] = []
		for i in range(contour.size()):
			var a: Vector3 = contour[i]; var b: Vector3 = contour[(i+1)%contour.size()]
			smooth.append(a.lerp(b,0.25).normalized()); smooth.append(a.lerp(b,0.75).normalized())
		contour = smooth
	var center: Vector3 = lake.center_direction
	var frame: Basis = PlanetCell.tangent_basis(center)
	var planar := PackedVector2Array()
	for p: Vector3 in contour: planar.append(Vector2(p.dot(frame.x),p.dot(frame.z)))
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(planar)
	var radius: float=world.grid_reference.planet_radius+surface.mapped_world_height(lake.surface_height)+surface.config.water_offset
	var tool:=SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,triangles.size(),3):
		var a: Vector3 = contour[triangles[i]]
		var b: Vector3 = contour[triangles[i+1]]
		var c: Vector3 = contour[triangles[i+2]]
		if (b-a).cross(c-a).dot(a)<0:
			var swap: Vector3=b; b=c; c=swap
		_lake_triangle(tool,a,b,c,radius)
	var instance:=MeshInstance3D.new(); instance.name="Lake_%d" % lake.id
	instance.mesh=tool.commit(); instance.material_override=_material(true)
	add_child(instance); lake_meshes.append(instance)
	# Narrow damp shore lip; it shares the smoothed contour with the water and
	# fades into the hydrology-darkened ground. No gameplay terrain modification.
	var bank:=SurfaceTool.new(); bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(contour.size()):
		var a: Vector3=contour[i]; var b: Vector3=contour[(i+1)%contour.size()]
		if surface.radius_at(a)>radius-0.01 or surface.radius_at(b)>radius-0.01: continue
		var oa: Vector3=(a+(a-center)*0.025).normalized()
		var ob: Vector3=(b+(b-center)*0.025).normalized()
		var pa: Vector3=a*radius; var pb: Vector3=b*radius
		var qa: Vector3=oa*maxf(radius-0.012,surface.radius_at(oa)+0.018)
		var qb: Vector3=ob*maxf(radius-0.012,surface.radius_at(ob)+0.018)
		for p: Vector3 in [pa,pb,qa,pb,qb,qa]: bank.set_normal(p.normalized()); bank.add_vertex(p)
	var bank_mesh:=MeshInstance3D.new(); bank_mesh.mesh=bank.commit()
	var bank_material:=StandardMaterial3D.new(); bank_material.albedo_color=Color("#5b6552")
	bank_material.roughness=0.85; bank_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	bank_mesh.material_override=bank_material; add_child(bank_mesh)

func _lake_triangle(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,radius: float) -> void:
	if maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a)))*radius>0.25:
		var ab: Vector3=(a+b).normalized(); var bc: Vector3=(b+c).normalized(); var ca: Vector3=(c+a).normalized()
		_lake_triangle(tool,a,ab,ca,radius); _lake_triangle(tool,ab,b,bc,radius)
		_lake_triangle(tool,ca,bc,c,radius); _lake_triangle(tool,ab,bc,ca,radius)
		return
	for point: Vector3 in [a,c,b]: tool.set_normal(point); tool.set_uv(Vector2(0.5,0.5)); tool.add_vertex(point*radius)

func _mesh(vertices: PackedVector3Array,normals: PackedVector3Array,uv: PackedVector2Array) -> ArrayMesh:
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv
	var result:=ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
