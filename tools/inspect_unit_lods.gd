extends SceneTree
## Read-only audit of the imported LOD index buffers used by army rendering.
func _initialize() -> void:
	var mapping:=VisualMap.new()
	for id: String in ["worker_ant","fighter_ant","living_spider"]:
		var root:=mapping.asset_scene(id).instantiate()
		for node: Node in root.find_children("*","MeshInstance3D",true,false):
			var mesh: Mesh=(node as MeshInstance3D).mesh
			for index in range(mesh.get_surface_count()):
				var surface:=RenderingServer.mesh_get_surface(mesh.get_rid(),index)
				var stride:=RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
				var lods: Array[Dictionary]=[]
				for lod: Dictionary in surface.get("lods",[]):
					lods.append({"error":lod.edge_length,"triangles":lod.index_data.size()/maxi(1,stride)/3})
				print("UNIT_LODS ",id," source_triangles=",int(surface.get("index_count",surface.vertex_count))/3," lods=",lods)
		root.free()
	quit()
