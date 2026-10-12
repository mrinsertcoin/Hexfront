class_name EntityView
extends MeshInstance3D
## Accepted cell paths drive displacement; in-place rig animation is independent.
signal movement_finished

var visual: UnitVisual
var moving: bool = false
var destination: Vector3
var _grid: PlanetGrid
var terrain_surface: TerrainSurfaceSampler
var _height: float
var _waypoints: PackedVector3Array = []
var _next_waypoint: int = 0
var _progress: float = 0.0
var _start_basis: Basis
var squad_members: Array[Node3D]=[]
var max_squad_size: int=1
var render_radius: float=3.0
var _render_active: bool=true
var _render_meshes: Array[GeometryInstance3D]=[]
var _render_layers:=PackedInt32Array()
var _animation_nodes: Array[AnimationPlayer]=[]
var grounded: bool=false
var _contact_positions: Array[Vector3]=[]
var _contact_scales: Array[Vector3]=[]

func prepare_ground_contact(wrapper: Node3D,flying: bool=false) -> void:
	grounded=not flying
	if not grounded: return
	if squad_members.is_empty(): squad_members=[wrapper]
	for member: Node3D in squad_members:
		var lowest:=INF
		for node: Node in member.find_children("*","MeshInstance3D",true,false):
			var instance:=node as MeshInstance3D
			if instance.mesh==null: continue
			var box: AABB=(member.global_transform.affine_inverse()*instance.global_transform)*instance.mesh.get_aabb()
			lowest=minf(lowest,box.position.y)
		if is_finite(lowest): member.position.y-=lowest*member.scale.y
		_contact_positions.append(member.position); _contact_scales.append(member.scale)

func _update_ground_pose() -> void:
	if not grounded or terrain_surface==null: return
	var normal:=terrain_surface.ground_normal(position.normalized())
	basis=PlanetCell.tangent_basis(normal,-basis.z)
	var inverse:=global_transform.affine_inverse()
	for index in range(squad_members.size()):
		var member:=squad_members[index]; var base:=_contact_positions[index]
		var footprint:=global_transform*Vector3(base.x,0,base.z)
		var foot:=terrain_surface.ground_position(footprint.normalized())
		member.position=Vector3(base.x,base.y+(inverse*foot).y,base.z)
		var member_normal:=terrain_surface.ground_normal(footprint.normalized())
		member.basis=global_basis.inverse()*PlanetCell.tangent_basis(member_normal,-global_basis.z).scaled(_contact_scales[index])

func prepare_render_culling() -> void:
	_render_meshes.clear(); _render_layers.clear(); _animation_nodes.clear()
	for node: Node in find_children("*","GeometryInstance3D",true,false):
		var geometry:=node as GeometryInstance3D
		# Imported army models contain hundreds of thousands of source triangles.
		# Prefer their generated LODs at tactical screen sizes; previews retain
		# their independent default bias and original source detail.
		if geometry is MeshInstance3D: geometry.lod_bias=0.15
		_render_meshes.append(geometry); _render_layers.append(geometry.layers)
	for node: Node in find_children("*","AnimationPlayer",true,false): _animation_nodes.append(node)
	var bounds:=selectable_bounds()
	render_radius=maxf(1.0,bounds.get_center().length()+bounds.size.length()*0.5)

func set_render_active(active: bool) -> void:
	if active==_render_active: return
	_render_active=active
	for index in range(_render_meshes.size()): _render_meshes[index].layers=_render_layers[index] if active else 0
	for player: AnimationPlayer in _animation_nodes: player.active=active

func selectable_bounds() -> AABB:
	var combined:=AABB()
	var found:=false
	for candidate: Node in find_children("*","MeshInstance3D",true,false):
		var instance:=candidate as MeshInstance3D
		if instance==null or instance.mesh==null or not instance.is_visible_in_tree(): continue
		var relative:=global_transform.affine_inverse()*instance.global_transform
		var bounds: AABB=relative*instance.get_aabb()
		if bounds.size.length_squared()<=0.000001: continue
		combined=bounds if not found else combined.merge(bounds); found=true
	if not found: return AABB(Vector3(-0.45,-0.05,-0.45),Vector3(0.9,1.25,0.9))
	# A modest pointer margin makes thin limbs and spaced squad members forgiving
	# without turning the entire logical hex into an entity hit target.
	return combined.grow(0.12)

func configure(wrapper: Node3D) -> void:
	visual = wrapper as UnitVisual
	if visual != null:
		visual.initialize_animation()
	set_process(false)

func configure_squad(wrapper: Node3D,size: int,member_scale: float=1.0,spacing: float=1.0,formation: String="default") -> void:
	max_squad_size=maxi(1,size); squad_members=[wrapper]
	for index in range(1,max_squad_size):
		var member:=wrapper.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
		member.name="SquadMember_%d" % (index+1); add_child(member); squad_members.append(member)
	for index in range(squad_members.size()):
		squad_members[index].scale*=member_scale
		squad_members[index].position=_formation_offset(index,max_squad_size,formation)*spacing

func sync_squad_health(current_hp: int,max_hp: int) -> void:
	var visible_count:=visible_member_count(max_squad_size,current_hp,max_hp)
	for index in range(squad_members.size()): squad_members[index].visible=index<visible_count

static func visible_member_count(size: int,current_hp: int,max_hp: int) -> int:
	if size<=0 or current_hp<=0 or max_hp<=0: return 0
	return clampi(int(ceil(float(size)*float(current_hp)/float(max_hp))),1,size)

static func _formation_offset(index: int,size: int,formation: String="default") -> Vector3:
	if size<=1: return Vector3.ZERO
	if size==7:
		if index==0: return Vector3.ZERO
		var angle:=TAU*float(index-1)/6.0
		return Vector3(cos(angle)*0.38,0.0,sin(angle)*0.38)
	if formation=="cross_five" and size==5:
		const CROSS: Array[Vector2]=[Vector2(0,-0.34),Vector2(-0.34,0),Vector2.ZERO,Vector2(0.34,0),Vector2(0,0.34)]
		var cross_point:=CROSS[index]
		return Vector3(cross_point.x,0.0,cross_point.y)
	const OFFSETS: Array[Vector2]=[Vector2(-0.24,-0.16),Vector2(0.24,-0.16),Vector2.ZERO,Vector2(-0.18,0.22),Vector2(0.18,0.22)]
	var p:=OFFSETS[index%OFFSETS.size()]
	return Vector3(p.x,0.0,p.y)

func sync_position(logical_position: Vector3) -> void:
	if moving and destination.is_equal_approx(logical_position):
		return
	cancel_movement()
	position = logical_position
	destination = logical_position
	basis = PlanetCell.tangent_basis(position.normalized(), -basis.z)
	_update_ground_pose()

func play_path(path: Array[int], grid: PlanetGrid, height: float) -> void:
	cancel_movement()
	if path.size() < 2:
		return
	_grid = grid
	_height = height
	for id: int in path:
		# Use the same normalized direction as stationary placement so starting a
		# path cannot shift the model by a float-rounding step in height sampling.
		_waypoints.append(grid.get_cell(id).up)
	position = _surface_position(_waypoints[0], height)
	basis = PlanetCell.tangent_basis(_waypoints[0], -basis.z)
	_update_ground_pose()
	destination = _surface_position(_waypoints[-1], height)
	_next_waypoint = 1
	_progress = 0.0
	_start_basis = basis
	moving = true
	if visual != null:
		visual.set_moving(true)
	set_process(true)

func _process(delta: float) -> void:
	advance_movement(delta)

func advance_movement(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0) * (maxf(0.1, visual.move_speed) if visual != null else 4.0)
	while moving and remaining > 0.0:
		var source: Vector3 = _waypoints[_next_waypoint - 1]
		var target: Vector3 = _waypoints[_next_waypoint]
		var length: float = source.angle_to(target) * (_grid.planet_radius + _height)
		var consumed: float = minf(remaining, length * (1.0 - _progress))
		_progress = minf(1.0, _progress + consumed / length)
		remaining -= consumed
		var radial: Vector3 = source.slerp(target, _progress).normalized()
		position = _surface_position(radial, _height)
		# Parallel transport the old heading and smoothly turn into this leg.
		var transport := Quaternion(source, radial)
		var old_forward: Vector3 = transport * -_start_basis.z
		var travel: Vector3 = source.cross(target).normalized().cross(radial)
		var turn: float = old_forward.signed_angle_to(travel, radial)
		var heading: Vector3 = old_forward.rotated(radial, turn * smoothstep(0.0, 0.4, _progress))
		basis = PlanetCell.tangent_basis(radial, heading)
		_update_ground_pose()
		if _progress < 1.0:
			return
		_next_waypoint += 1
		_progress = 0.0
		_start_basis = basis
		if _next_waypoint == _waypoints.size():
			cancel_movement()
			movement_finished.emit()

func cancel_movement() -> void:
	moving = false
	_waypoints.clear()
	set_process(false)
	if visual != null:
		visual.set_moving(false)

func _surface_position(direction: Vector3, offset: float) -> Vector3:
	if grounded and terrain_surface!=null: return terrain_surface.ground_position(direction,offset)
	return terrain_surface.sample_position(direction, offset) if terrain_surface != null else _grid.sample_position(direction, offset)
