class_name TerracedTerrainMesh
extends RefCounted
## Cell-aligned terrace/ramp geometry, spatially grouped into 20 draw chunks.
var renderer: PlanetTerrainRenderer
var _walls: Dictionary={}
var _ramps:=PackedByteArray()

func build(target: PlanetTerrainRenderer) -> void:
	renderer=target
	_ramps.resize(renderer.world.grid_reference.get_cell_count())
	for record: Dictionary in renderer.world.terraces.boundaries:
		if record.cliff:
			if not _walls.has(record.high): _walls[record.high]=[]
			_walls[record.high].append(record)
	var groups: Array[Array]=[]; var axes: Array[Vector3]=[]
	var coarse:=PlanetGrid.new(0)
	for face: Vector3i in coarse._faces:
		axes.append((coarse.cells[face.x].up+coarse.cells[face.y].up+coarse.cells[face.z].up).normalized()); groups.append([])
	for cell: PlanetCell in renderer.world.grid_reference.cells:
		_ramps[cell.id]=int(renderer.world.terraces.is_ramp(cell.id))
		var best:=0; var score:=-INF
		for index in range(20):
			var dot:=cell.up.dot(axes[index])
			if dot>score: best=index; score=dot
		groups[best].append(cell.id)
	for group: Array in groups:
		var started:=renderer.faces.size()
		for cell_id: int in group:
			var cell:=renderer.world.grid_reference.cells[cell_id]
			var depth:=int(_ramps[cell_id])
			for edge in range(cell.polygon_vertices.size()):
				var a:=cell.polygon_vertices[edge].normalized(); var b:=cell.polygon_vertices[(edge+1)%cell.polygon_vertices.size()].normalized()
				if depth==0:
					# Match ramp edge tessellation to avoid small cracks between
					# a flat tile's straight chord and a ramp's curved edge.
					var midpoint:=(a+b).normalized()
					_triangle(cell.up,a,midpoint,cell_id,0); _triangle(cell.up,midpoint,b,cell_id,0)
				else: _triangle(cell.up,a,b,cell_id,depth)
			for record: Dictionary in _walls.get(cell_id,[]): _wall(record)
		renderer.chunk_ranges.append(Vector2i(started,renderer.faces.size()-started))

func _triangle(a: Vector3,b: Vector3,c: Vector3,cell_id: int,depth: int) -> void:
	if depth>0:
		var ab:=(a+b).normalized(); var bc:=(b+c).normalized(); var ca:=(c+a).normalized()
		_triangle(a,ab,ca,cell_id,depth-1); _triangle(ab,b,bc,cell_id,depth-1)
		_triangle(ca,bc,c,cell_id,depth-1); _triangle(ab,bc,ca,cell_id,depth-1); return
	var start:=renderer.vertices.size()
	var positions: Array[Vector3]=[]
	for direction: Vector3 in [a,b,c]: positions.append(renderer.surface.sample_cell_position(cell_id,direction))
	var normal:=(positions[1]-positions[0]).cross(positions[2]-positions[0]).normalized()
	if normal.dot(a)<0: normal=-normal
	if _ramps[cell_id]==0: normal=renderer.world.grid_reference.cells[cell_id].up
	for index in range(3): _vertex(positions[index],[a,b,c][index],normal,cell_id,false)
	renderer.faces.append(Vector3i(start,start+1,start+2))

func _vertex(position: Vector3,direction: Vector3,normal: Vector3,cell_id: int,wall: bool) -> void:
	var data:=renderer.world.cell_world_data[cell_id]
	var weights: Array[float]=[0,0,0,0,0]
	if wall: weights[3]=1.0
	else:
		for index in range(renderer.world.config.biomes.size()):
			var slot:=StylizedTerrainMaterial.IDS.find(renderer.world.config.biomes[index].biome_id)
			if slot>=0: weights[slot]+=data.biome_weights[index]
	renderer.vertices.append(position); renderer.directions.append(direction); renderer.normals.append(normal)
	renderer.colors.append(Color(weights[0],weights[1],weights[2],weights[3]))
	renderer.uvs.append(Vector2(data.effective_moisture,data.terrain_roughness))
	renderer.uv2s.append(Vector2(weights[4],data.hydrology.wetland_potential if data.hydrology!=null else 0.0))

func _wall(record: Dictionary) -> void:
	var a: Vector3=record.a; var b: Vector3=record.b
	for index in range(6):
		var p:=a.slerp(b,float(index)/6).normalized(); var q:=a.slerp(b,float(index+1)/6).normalized()
		var high_p:=renderer.surface.sample_cell_position(record.high,p)
		var high_q:=renderer.surface.sample_cell_position(record.high,q)
		var low_p:=renderer.surface.sample_cell_position(record.low,p)
		var low_q:=renderer.surface.sample_cell_position(record.low,q)
		var normal: Vector3=(renderer.world.grid_reference.cells[record.low].up-renderer.world.grid_reference.cells[record.high].up).normalized()
		for triangle: Array in [[high_p,low_p,low_q],[high_p,low_q,high_q]]:
			var start:=renderer.vertices.size()
			for position: Vector3 in triangle: _vertex(position,position.normalized(),normal,record.high,true)
			renderer.faces.append(Vector3i(start,start+1,start+2))
