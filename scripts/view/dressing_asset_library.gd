class_name DressingAssetLibrary
extends RefCounted
## Loads an explicit supplied LOD, preserves its topology, and normalizes contact.

static var _cache: Dictionary[String,Dictionary]={}

static func resolve(variant: DressingMeshVariant,lod: int) -> Dictionary:
	var path:=variant.scene_paths[lod]
	var node_name:=variant.mesh_node_names[lod]
	var key:="%s::%s::%s" % [path,node_name,variant.material_tint.to_html()]
	if _cache.has(key): return _cache[key]
	if not ResourceLoader.exists(path):
		push_error("Missing stylized dressing scene: "+path); return {}
	var packed:=load(path) as PackedScene
	if packed==null:
		push_error("Dressing asset is not a scene: "+path); return {}
	var scene:=packed.instantiate()
	var node: Node=scene if scene.name==node_name else scene.find_child(node_name,true,false)
	if not node is MeshInstance3D or (node as MeshInstance3D).mesh==null:
		push_error("Missing dressing mesh node %s in %s" % [node_name,path]); scene.free(); return {}
	var source:=node as MeshInstance3D
	var authored_basis:=source.transform.basis
	var bounds:=source.mesh.get_aabb()
	var minimum:=Vector3(INF,INF,INF)
	var maximum:=Vector3(-INF,-INF,-INF)
	for x in [0.0,1.0]:
		for y in [0.0,1.0]:
			for z in [0.0,1.0]:
				var point:=authored_basis*(bounds.position+Vector3(bounds.size.x*x,bounds.size.y*y,bounds.size.z*z))
				minimum=minimum.min(point); maximum=maximum.max(point)
	var recenter:=Vector3(-(minimum.x+maximum.x)*.5,-minimum.y,-(minimum.z+maximum.z)*.5)
	var normal_basis:=authored_basis.inverse().transposed()
	var mesh:=ArrayMesh.new()
	for surface in range(source.mesh.get_surface_count()):
		var arrays:=source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()): vertices[i]=authored_basis*vertices[i]+recenter
		arrays[Mesh.ARRAY_VERTEX]=vertices
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in range(normals.size()): normals[i]=(normal_basis*normals[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL]=normals
		var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
		for i in range(0,tangents.size(),4):
			var tangent:=(normal_basis*Vector3(tangents[i],tangents[i+1],tangents[i+2])).normalized()
			tangents[i]=tangent.x; tangents[i+1]=tangent.y; tangents[i+2]=tangent.z
		arrays[Mesh.ARRAY_TANGENT]=tangents
		mesh.add_surface_from_arrays(source.mesh.surface_get_primitive_type(surface),arrays)
		var material:=source.mesh.surface_get_material(surface)
		if material is BaseMaterial3D:
			var copy:=material.duplicate() as BaseMaterial3D
			copy.albedo_color*=variant.material_tint
			copy.metallic=0.0; copy.roughness=maxf(copy.roughness,.82); copy.metallic_specular=.25
			copy.normal_scale=minf(copy.normal_scale,.35)
			if copy.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA:
				copy.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				copy.alpha_scissor_threshold=.45
			material=copy
		mesh.surface_set_material(surface,material)
	mesh.set_meta("dressing_source",path)
	mesh.set_meta("dressing_node",node_name)
	mesh.set_meta("stylized_lod",lod)
	var result:={"mesh":mesh,"size":maximum-minimum}
	_cache[key]=result
	scene.free()
	return result

static func clear_cache() -> void:
	_cache.clear()
