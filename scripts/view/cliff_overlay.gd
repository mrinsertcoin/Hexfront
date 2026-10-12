class_name CliffOverlay
extends MeshInstance3D
## One opaque thin rim mesh; unseen edges remain hidden by observation filtering.
var world: GeneratedPlanet
var surface: TerrainSurfaceSampler
var _revision: int=-1
var _team: int=-1
var _omniscient: bool=false

func configure(planet: GeneratedPlanet,sampler: TerrainSurfaceSampler) -> void:
	world=planet; surface=sampler
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("#c95d56"); material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material_override=material; cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_observation(observation: TeamObservation,omniscient: bool=false) -> void:
	if world.terraces==null: return
	if _revision==observation.revision and _team==observation.team_id and _omniscient==omniscient: return
	_revision=observation.revision; _team=observation.team_id; _omniscient=omniscient
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var count:=0
	for record: Dictionary in world.terraces.boundaries:
		if not record.cliff: continue
		if not omniscient and not (observation.is_explored(record.high) or observation.is_explored(record.low)): continue
		var a: Vector3=record.a; var b: Vector3=record.b; var side:=a.cross(b).normalized()
		for index in range(6):
			var p:=a.slerp(b,float(index)/6).normalized(); var q:=a.slerp(b,float(index+1)/6).normalized()
			var radius:=world.grid_reference.planet_radius
			var left_p:=surface.sample_cell_position(record.high,(p*radius+side*0.009).normalized(),0.014)
			var right_p:=surface.sample_cell_position(record.high,(p*radius-side*0.009).normalized(),0.014)
			var left_q:=surface.sample_cell_position(record.high,(q*radius+side*0.009).normalized(),0.014)
			var right_q:=surface.sample_cell_position(record.high,(q*radius-side*0.009).normalized(),0.014)
			for point: Vector3 in [left_p,left_q,right_q,left_p,right_q,right_p]: st.add_vertex(point); count+=1
	mesh=st.commit() if count>0 else null
