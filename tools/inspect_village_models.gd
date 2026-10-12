extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for id: String in ["villager","knight"]:
		var path:="res://assets/neutral/village/%s/source/%s.glb" % [id,id]
		var scene:=load(path).instantiate() as Node3D
		root.add_child(scene)
		var bounds:=AABB(); var found:=false; var triangles:=0; var lod_counts: Array[int]=[]
		for node: Node in scene.find_children("*","MeshInstance3D",true,false):
			var mesh:=node as MeshInstance3D; var box: AABB=mesh.global_transform*mesh.mesh.get_aabb()
			bounds=box if not found else bounds.merge(box); found=true
			for index in range(mesh.mesh.get_surface_count()):
				var surface:=RenderingServer.mesh_get_surface(mesh.mesh.get_rid(),index)
				triangles+=int(surface.index_count)/3
				var stride:=RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
				for lod: Dictionary in surface.get("lods",[]): lod_counts.append(lod.index_data.size()/maxi(1,stride)/3)
		print("VILLAGE_MODEL ",id," bounds=",bounds," triangles=",triangles," lod_triangles=",lod_counts)
		scene.free()
	quit()
