class_name AntRoadOverlay
extends Node3D
## Narrow terrain-following paths. Connections never paint the full hex border.

const DIRT_TEXTURE_PATH:="res://assets/factions/swarm/structs/ant road/source/ant_road.png.png"
const BORDER_TEXTURE_PATH:="res://assets/factions/swarm/structs/ant road/source/ant_road_border.png.png"
const HEIGHT_OFFSET:=0.010
const PATH_WIDTH:=0.16
const SAMPLE_SPACING:=0.12

var grid: PlanetGrid
var terrain: TerrainSurfaceSampler
var world_seed: int=0
var visible_roads: Dictionary[int,int]={}
var cell_views: Dictionary[int,Node3D]={}
var dirt_material: StandardMaterial3D
var border_material: StandardMaterial3D
var last_refreshed_cells: Array[int]=[]

func configure(topology: PlanetGrid,surface: TerrainSurfaceSampler,seed_value: int) -> void:
	grid=topology; terrain=surface; world_seed=seed_value
	dirt_material=StandardMaterial3D.new()
	dirt_material.albedo_texture=load(DIRT_TEXTURE_PATH)
	dirt_material.albedo_color=Color(0.66,0.61,0.46,0.66)
	border_material=StandardMaterial3D.new()
	border_material.albedo_color=Color(0.22,0.20,0.14,0.28)
	for material: StandardMaterial3D in [dirt_material,border_material]:
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.roughness=1.0
	border_material.render_priority=1; dirt_material.render_priority=2

func sync_roads(next_roads: Dictionary[int,int]) -> void:
	if grid==null or terrain==null: return
	var dirty: Dictionary[int,bool]={}
	for cell_id: int in visible_roads:
		if not next_roads.has(cell_id) or next_roads[cell_id]!=visible_roads[cell_id]: dirty[cell_id]=true
	for cell_id: int in next_roads:
		if not visible_roads.has(cell_id) or next_roads[cell_id]!=visible_roads[cell_id]: dirty[cell_id]=true
	for value: Variant in dirty.keys():
		for neighbor: int in grid.get_neighbors(int(value)):
			if visible_roads.has(neighbor) or next_roads.has(neighbor): dirty[neighbor]=true
	visible_roads=next_roads.duplicate(); last_refreshed_cells.clear()
	var ids: Array[int]=[]; ids.assign(dirty.keys()); ids.sort()
	for cell_id: int in ids:
		if cell_views.has(cell_id): cell_views[cell_id].queue_free(); cell_views.erase(cell_id)
		if visible_roads.has(cell_id): cell_views[cell_id]=_build_cell(cell_id)
		last_refreshed_cells.append(cell_id)

func connection_record(cell_id: int) -> Dictionary:
	var connected: Array[int]=[]; var exposed: Array[int]=[]
	if grid==null or not grid.contains(cell_id): return {"connected_neighbors":connected,"exposed_edges":exposed}
	var owner: int=int(visible_roads.get(cell_id,-1)); var cell:=grid.get_cell(cell_id)
	for edge in range(cell.polygon_vertices.size()):
		var neighbor:=grid.neighbor_across_edge(cell_id,edge)
		if neighbor>=0 and int(visible_roads.get(neighbor,-2))==owner: connected.append(neighbor)
		else: exposed.append(edge)
	return {"connected_neighbors":connected,"exposed_edges":exposed}

func edge_geometry_record(cell_id: int,edge: int) -> Dictionary:
	if grid==null or not grid.contains(cell_id): return {}
	var cell:=grid.get_cell(cell_id)
	if edge<0 or edge>=cell.polygon_vertices.size(): return {}
	var a:=cell.polygon_vertices[edge].normalized(); var b:=cell.polygon_vertices[(edge+1)%cell.polygon_vertices.size()].normalized()
	return {"a":a,"b":b,"midpoint":a.slerp(b,0.5).normalized(),
		"inner_a":a.slerp(cell.up,0.15).normalized(),"inner_b":b.slerp(cell.up,0.15).normalized()}

func _build_cell(cell_id: int) -> Node3D:
	var root:=Node3D.new(); root.name="AntRoad_%d" % cell_id; add_child(root)
	var record:=connection_record(cell_id)
	for layer in [0,1]:
		var mesh:=MeshInstance3D.new(); mesh.name="Dirt" if layer==0 else "ExposedBorders"
		mesh.mesh=_path_mesh(cell_id,record.connected_neighbors,PATH_WIDTH if layer==0 else PATH_WIDTH*1.45,HEIGHT_OFFSET if layer==0 else HEIGHT_OFFSET*0.6)
		mesh.material_override=dirt_material if layer==0 else border_material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(mesh)
	return root

func _path_mesh(cell_id: int,connections: Array,width: float,offset: float) -> ArrayMesh:
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell:=grid.get_cell(cell_id); var center:=cell.up
	# A small junction dot keeps isolated cells visible without a tile-sized patch.
	var frame:=PlanetCell.tangent_basis(center)
	for segment in range(8):
		var angle:=TAU*segment/8.0; var next:=TAU*(segment+1)/8.0
		var a:=(center*grid.planet_radius+(frame.x*cos(angle)+frame.z*sin(angle))*width*0.55).normalized()
		var b:=(center*grid.planet_radius+(frame.x*cos(next)+frame.z*sin(next))*width*0.55).normalized()
		_vertex(st,center,Vector2(0.5,0.5),offset); _vertex(st,b,Vector2(0.5+cos(next)*0.5,0.5+sin(next)*0.5),offset); _vertex(st,a,Vector2(0.5+cos(angle)*0.5,0.5+sin(angle)*0.5),offset)
	for neighbor_id: int in connections:
		var edge:=_edge_for_neighbor(cell_id,neighbor_id)
		if edge>=0: _ribbon(st,center,edge_geometry_record(cell_id,edge).midpoint,width,offset)
	return st.commit()

func _ribbon(st: SurfaceTool,start: Vector3,end: Vector3,width: float,offset: float) -> void:
	var length:=start.angle_to(end)*grid.planet_radius
	var steps:=maxi(1,ceili(length/SAMPLE_SPACING))
	var side:=start.cross(end).normalized()
	for index in range(steps):
		var a:=start.slerp(end,float(index)/steps).normalized()
		var b:=start.slerp(end,float(index+1)/steps).normalized()
		var left_a:=(a*grid.planet_radius+side*width*0.5).normalized()
		var right_a:=(a*grid.planet_radius-side*width*0.5).normalized()
		var left_b:=(b*grid.planet_radius+side*width*0.5).normalized()
		var right_b:=(b*grid.planet_radius-side*width*0.5).normalized()
		var v0:=length*float(index)/steps; var v1:=length*float(index+1)/steps
		for pair: Array in [[left_a,Vector2(0,v0)],[left_b,Vector2(0,v1)],[right_b,Vector2(1,v1)],[left_a,Vector2(0,v0)],[right_b,Vector2(1,v1)],[right_a,Vector2(1,v0)]]:
			_vertex(st,pair[0],pair[1],offset)

func _vertex(st: SurfaceTool,direction: Vector3,uv: Vector2,offset: float) -> void:
	var position:=terrain.sample_position(direction,offset)
	if terrain.picking_mesh!=null:
		var outer:=grid.planet_radius+maxf(terrain.config.mapped_height(0.0),terrain.config.mapped_height(1.0))+2.0
		var hit: Dictionary=terrain.picking_mesh.intersect_ray(direction*outer,-direction)
		if not hit.is_empty(): position=hit.position+direction*offset
	st.set_normal(direction); st.set_uv(uv); st.add_vertex(position)

func _edge_for_neighbor(cell_id: int,neighbor_id: int) -> int:
	var cell:=grid.get_cell(cell_id)
	for edge in range(cell.polygon_vertices.size()):
		if grid.neighbor_across_edge(cell_id,edge)==neighbor_id: return edge
	return -1
