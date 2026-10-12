class_name FogOfWarOverlay
extends Node3D
## One cached displaced spherical mesh; revisions update colors, not topology.

var mesh_instance:=MeshInstance3D.new()
var last_revision: int=-1
var last_team_id: int=-1
var omniscient: bool=false
var _last_omniscient: bool=false
var build_ms: float=0.0
var geometry_build_ms: float=0.0
var _vertices:=PackedVector3Array()
var _normals:=PackedVector3Array()
var _vertex_cells:=PackedInt32Array()
var _cached_grid_fingerprint: String=""
var _cached_surface: TerrainSurfaceSampler

func _init() -> void:
	name="FogOfWarOverlay"; add_child(mesh_instance)
	mesh_instance.name="FogSurface"; mesh_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_BACK
	material.no_depth_test=false
	material.render_priority=20
	mesh_instance.material_override=material

func update_observation(grid: PlanetGrid,surface: TerrainSurfaceSampler,observation: TeamObservation,force: bool=false) -> void:
	var geometry_changed:=_cached_grid_fingerprint!=grid.fingerprint or _cached_surface!=surface
	if geometry_changed: _build_geometry(grid,surface)
	if not force and not geometry_changed and last_revision==observation.revision and last_team_id==observation.team_id and _last_omniscient==omniscient: return
	_last_omniscient=omniscient
	last_revision=observation.revision; last_team_id=observation.team_id
	var started:=Time.get_ticks_usec()
	if omniscient:
		mesh_instance.visible=false; build_ms=(Time.get_ticks_usec()-started)/1000.0; return
	mesh_instance.visible=true
	var colors:=PackedColorArray(); colors.resize(_vertices.size())
	for index in range(_vertices.size()):
		var visibility:=observation.get_visibility(_vertex_cells[index])
		colors[index]=Color(0,0,0,0) if visibility==VisibilityState.CellVisibility.VISIBLE else (
			Color(0.012,0.018,0.024,0.90) if visibility==VisibilityState.CellVisibility.UNEXPLORED else Color(0.09,0.105,0.11,0.58))
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_vertices; arrays[Mesh.ARRAY_NORMAL]=_normals; arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh_instance.mesh=mesh
	build_ms=(Time.get_ticks_usec()-started)/1000.0

func set_omniscient(value: bool,grid: PlanetGrid,surface: TerrainSurfaceSampler,observation: TeamObservation) -> void:
	omniscient=value; update_observation(grid,surface,observation,true)

func _build_geometry(grid: PlanetGrid,surface: TerrainSurfaceSampler) -> void:
	var started:=Time.get_ticks_usec()
	_vertices=PackedVector3Array(); _normals=PackedVector3Array(); _vertex_cells=PackedInt32Array()
	for cell: PlanetCell in grid.cells:
		for index in range(cell.polygon_vertices.size()):
			_cache_triangle(cell.up,cell.polygon_vertices[index].normalized(),cell.polygon_vertices[(index+1)%cell.polygon_vertices.size()].normalized(),cell.id,surface)
	_cached_grid_fingerprint=grid.fingerprint; _cached_surface=surface
	geometry_build_ms=(Time.get_ticks_usec()-started)/1000.0

func _cache_triangle(a: Vector3,b: Vector3,c: Vector3,cell_id: int,surface: TerrainSurfaceSampler) -> void:
	if maxf(a.angle_to(b),maxf(b.angle_to(c),c.angle_to(a)))>0.035:
		var ab:=(a+b).normalized(); var bc:=(b+c).normalized(); var ca:=(c+a).normalized()
		_cache_triangle(a,ab,ca,cell_id,surface); _cache_triangle(ab,b,bc,cell_id,surface)
		_cache_triangle(ca,bc,c,cell_id,surface); _cache_triangle(ab,bc,ca,cell_id,surface)
		return
	for direction: Vector3 in [a,c,b]:
		_vertices.append(surface.sample_cell_position(cell_id,direction,0.085)); _normals.append(direction); _vertex_cells.append(cell_id)
