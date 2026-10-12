class_name TerracedTerrain
extends RefCounted
## Public, seed-derived elevation and movement topology. Four terrace levels;
## transitions use one world-space rise/run rather than arbitrary noise slopes.
const CLIFF_PRESETS: PackedStringArray=["None","Rare","Low","Moderate","High","Experimental"]
const CLIFF_RATES: Array[float]=[0.0,0.015,0.04,0.10,0.25,0.65]
const LEVEL_COUNT:=4
const RAMP_ANGLE_DEGREES:=35.0
const REQUESTED_STEP:=0.65
var grid: PlanetGrid
var levels:=PackedInt32Array()
var elevation_step: float=REQUESTED_STEP
var ramp_run: float
var ramp_slope: float=tan(deg_to_rad(RAMP_ANGLE_DEGREES))
var boundaries: Array[Dictionary]=[]
var ramp_segments: Array[Array]=[]
var blocked_edges: Dictionary[Vector2i,bool]={}
var cliff_preset: String="Rare"
var fingerprint: String
var range_frequency: float

static func generate(topology: PlanetGrid,seed_value: int,preset: String="Rare") -> TerracedTerrain:
	var result:=TerracedTerrain.new(); result.grid=topology; result.cliff_preset=preset
	var noise:=FastNoiseLite.new(); noise.seed=PlanetFieldSampler.derive_seed(seed_value,"terraces/ranges")
	# Larger planets get broader, fewer elevation bands rather than spending
	# their extra cells on densely alternating ramp boundaries.
	result.range_frequency=0.65*sqrt(12.0/topology.planet_radius)
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.fractal_type=FastNoiseLite.FRACTAL_NONE; noise.frequency=result.range_frequency
	var ranked: Array[Dictionary]=[]; var shortest:=INF
	for cell: PlanetCell in topology.cells:
		# Low-frequency ridged noise creates connected broad mountain belts.
		var p:=cell.up; var score:=1.0-absf(noise.get_noise_3dv(p))
		ranked.append({"id":cell.id,"score":score}); result.ramp_segments.append([])
		for neighbor: int in cell.neighbor_ids: shortest=minf(shortest,p.distance_to(topology.cells[neighbor].up)*topology.planet_radius)
	result.elevation_step=minf(REQUESTED_STEP,shortest*0.70*result.ramp_slope)
	result.ramp_run=result.elevation_step/result.ramp_slope
	ranked.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.score<b.score or (a.score==b.score and a.id<b.id))
	result.levels.resize(topology.get_cell_count())
	# Broad lowlands and progressively smaller highlands leave room for cities
	# and armies instead of forcing equal-area, densely packed contour bands.
	for index in range(ranked.size()):
		var fraction:=float(index)/ranked.size()
		result.levels[ranked[index].id]=0 if fraction<0.65 else (1 if fraction<0.85 else (2 if fraction<0.97 else 3))
	# Remove multi-level jumps. A transition can never require a steeper ramp.
	var changed:=true
	while changed:
		changed=false
		for cell: PlanetCell in topology.cells:
			for neighbor: int in cell.neighbor_ids:
				if result.levels[cell.id]>result.levels[neighbor]+1:
					result.levels[cell.id]=result.levels[neighbor]+1; changed=true
	# Unusual seeds can erode a very narrow highest ridge while removing jumps.
	# A small Lipschitz peak restores level three without creating steep edges.
	if not result.levels.has(3):
		var peak: int=ranked.back().id
		var around_peak:=topology.breadth_first(peak,3)
		for cell_id: int in around_peak.order: result.levels[cell_id]=maxi(result.levels[cell_id],3-around_peak.costs[cell_id])
	var rate:=CLIFF_RATES[maxi(0,CLIFF_PRESETS.find(preset))]
	for cell: PlanetCell in topology.cells:
		for edge in range(cell.polygon_vertices.size()):
			var low:=topology.neighbor_across_edge(cell.id,edge)
			if low<0 or result.levels[cell.id]!=result.levels[low]+1: continue
			var a:=cell.polygon_vertices[edge].normalized(); var b:=cell.polygon_vertices[(edge+1)%cell.polygon_vertices.size()].normalized()
			var cliff:=float(PlanetFieldSampler.derive_seed(seed_value,"terraces/cliff/%d/%d" % [mini(cell.id,low),maxi(cell.id,low)]))/2147483647.0<rate
			var record:={"high":cell.id,"low":low,"level":result.levels[cell.id],"a":a,"b":b,"cliff":cliff}
			result.boundaries.append(record)
			if cliff:
				result.blocked_edges[Vector2i(cell.id,low)]=true; result.blocked_edges[Vector2i(low,cell.id)]=true
			else:
				for nearby: int in topology.get_cells_within_distance(low,2):
					if result.levels[nearby]==result.levels[low]: result.ramp_segments[nearby].append(record)
	result._open_spanning_connections()
	var rows:=PackedStringArray([str(seed_value),preset,str(result.range_frequency),str(result.elevation_step),str(RAMP_ANGLE_DEGREES),str(result.levels)])
	for edge: Vector2i in result.blocked_edges: rows.append(str(edge))
	result.fingerprint="|".join(rows).sha256_text()
	return result

func height_at(direction: Vector3,cell_id: int=-1) -> float:
	var p:=direction.normalized()
	if cell_id<0: cell_id=grid.find_cell(p)
	if cell_id<0: return 0.0
	var height:=levels[cell_id]*elevation_step
	for record: Dictionary in ramp_segments[cell_id]:
		var a: Vector3=record.a; var b: Vector3=record.b; var line:=b-a
		var t:=clampf((p-a).dot(line)/maxf(0.000001,line.length_squared()),0.0,1.0)
		var nearest:=a.lerp(b,t).normalized()
		var distance:=p.distance_to(nearest)*grid.planet_radius
		if distance<ramp_run: height=maxf(height,record.level*elevation_step-distance*ramp_slope)
	return height

func _open_spanning_connections() -> void:
	# Label open components once, then join them through the minimum number of
	# cliff removals. This stays linear even at Experimental density.
	var components:=PackedInt32Array(); components.resize(grid.cells.size()); components.fill(-1)
	var roots: Array[int]=[]
	for start in range(grid.cells.size()):
		if components[start]>=0: continue
		var component:=roots.size(); roots.append(component)
		var queue: Array[int]=[start]; components[start]=component; var cursor:=0
		while cursor<queue.size():
			var current:=queue[cursor]; cursor+=1
			for neighbor: int in grid.get_neighbors(current):
				if components[neighbor]>=0 or blocked_edges.has(Vector2i(current,neighbor)): continue
				components[neighbor]=component; queue.append(neighbor)
	for record: Dictionary in boundaries:
		if not record.cliff: continue
		var high_root:=components[record.high]; var low_root:=components[record.low]
		while roots[high_root]!=high_root: high_root=roots[high_root]
		while roots[low_root]!=low_root: low_root=roots[low_root]
		if high_root==low_root: continue
		roots[maxi(high_root,low_root)]=mini(high_root,low_root)
		blocked_edges.erase(Vector2i(record.high,record.low)); blocked_edges.erase(Vector2i(record.low,record.high)); record.cliff=false
		for nearby: int in grid.get_cells_within_distance(record.low,2):
			if levels[nearby]==levels[record.low]: ramp_segments[nearby].append(record)

func is_ramp(cell_id: int) -> bool:
	if ramp_segments[cell_id].is_empty(): return false
	var base:=levels[cell_id]*elevation_step
	var cell:=grid.cells[cell_id]
	if height_at(cell.up,cell_id)>base+0.0001: return true
	for index in range(cell.polygon_vertices.size()):
		var corner:=cell.polygon_vertices[index]
		if height_at(corner.normalized(),cell_id)>base+0.0001: return true
		var midpoint: Vector3=(corner+cell.polygon_vertices[(index+1)%cell.polygon_vertices.size()]).normalized()
		if height_at(midpoint,cell_id)>base+0.0001: return true
	return false

func can_cross(from_cell: int,to_cell: int,flying: bool=false) -> bool:
	return flying or not blocked_edges.has(Vector2i(from_cell,to_cell))
