extends SceneTree
## Read-only audit for the production stylized environment kit.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_scan("res://assets/environment/stylized")
	quit()

func _scan(directory: String) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".glb"):
			_inspect(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_scan(directory.path_join(child))

func _inspect(path: String) -> void:
	var packed:=load(path) as PackedScene
	if packed==null:
		push_error("Cannot load "+path)
		return
	var root:=packed.instantiate()
	var meshes: Array[Dictionary]=[]
	_collect(root,meshes)
	print(JSON.stringify({"path":path,"meshes":meshes}))
	root.free()

func _collect(node: Node,meshes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var instance:=node as MeshInstance3D
		var triangles:=0
		for surface in range(instance.mesh.get_surface_count()):
			triangles+=instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
		meshes.append({"name":instance.name,"aabb":str(instance.mesh.get_aabb()),
			"transform":str(instance.transform),"surfaces":instance.mesh.get_surface_count(),
			"triangles":triangles})
	for child: Node in node.get_children(): _collect(child,meshes)
