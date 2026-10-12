class_name AttackOrderOverlay
extends Node3D
## Presentation-only arrows for the local player's queued attack orders.

const HEIGHT_OFFSET:=0.18
const ARROW_COLOR:=Color("#e53935")

var grid: PlanetGrid
var terrain: TerrainSurfaceSampler
var arrow_material: StandardMaterial3D
var arrow_views: Dictionary[int,MeshInstance3D]={}
var _signature: String=""

func configure(topology: PlanetGrid,surface: TerrainSurfaceSampler) -> void:
	grid=topology; terrain=surface
	_signature=""
	arrow_material=StandardMaterial3D.new()
	arrow_material.albedo_color=ARROW_COLOR
	arrow_material.transparency=BaseMaterial3D.TRANSPARENCY_DISABLED
	arrow_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	arrow_material.no_depth_test=false

func sync_orders(state: GameState,controller_id: int) -> void:
	if grid==null or terrain==null: return
	var records: Array[Dictionary]=[]
	var unit_ids: Array[int]=[]
	for value: Variant in state.combat_orders.intents.keys(): unit_ids.append(int(value))
	unit_ids.sort()
	for unit_id: int in unit_ids:
		var intent: CombatIntent=state.combat_orders.intents[unit_id]
		if intent.controller_id!=controller_id or intent.option_id!="attack": continue
		if not state.units.has(unit_id): continue
		var target:=state.combat_target(intent.target_id)
		if target==null: continue
		var source: GameState.Unit=state.units[unit_id]
		records.append({"source_id":unit_id,"target_id":intent.target_id,"source_cell":source.cell_id,"target_cell":target.cell_id})
	var next_signature:=JSON.stringify(records)
	if next_signature==_signature: return
	_signature=next_signature
	for view: MeshInstance3D in arrow_views.values(): view.queue_free()
	arrow_views.clear()
	for record: Dictionary in records:
		var view:=MeshInstance3D.new()
		view.name="AttackOrder_%d_%d" % [record.source_id,record.target_id]
		view.mesh=_arrow_mesh(int(record.source_cell),int(record.target_cell))
		view.material_override=arrow_material
		add_child(view); arrow_views[int(record.source_id)]=view

func _arrow_mesh(source_cell: int,target_cell: int) -> ArrayMesh:
	var source_direction: Vector3=grid.get_cell(source_cell).up
	var target_direction: Vector3=grid.get_cell(target_cell).up
	var start_direction:=source_direction.slerp(target_direction,0.20).normalized()
	var neck_direction:=source_direction.slerp(target_direction,0.67).normalized()
	var head_direction:=source_direction.slerp(target_direction,0.84).normalized()
	var shaft_half_width:=0.045
	var head_half_width:=0.13
	var start_pair:=_edge_pair(start_direction,target_direction,shaft_half_width)
	var neck_pair:=_edge_pair(neck_direction,target_direction,shaft_half_width)
	var head_pair:=_edge_pair(neck_direction,target_direction,head_half_width)
	var start_left: Vector3=start_pair[0]; var start_right: Vector3=start_pair[1]
	var neck_left: Vector3=neck_pair[0]; var neck_right: Vector3=neck_pair[1]
	var head_left: Vector3=head_pair[0]; var head_right: Vector3=head_pair[1]
	var tip:=terrain.sample_position(head_direction,HEIGHT_OFFSET)
	var tool:=SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangle(tool,start_left,start_right,neck_right)
	_triangle(tool,start_left,neck_right,neck_left)
	_triangle(tool,head_left,head_right,tip)
	tool.generate_normals()
	return tool.commit()

func _edge_pair(direction: Vector3,target_direction: Vector3,half_width: float) -> Array[Vector3]:
	var forward:=(target_direction-direction*target_direction.dot(direction)).normalized()
	var side:=direction.cross(forward).normalized()
	var angular_width:=half_width/maxf(0.001,terrain.radius_at(direction))
	return [terrain.sample_position((direction+side*angular_width).normalized(),HEIGHT_OFFSET),
		terrain.sample_position((direction-side*angular_width).normalized(),HEIGHT_OFFSET)]

func _triangle(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
