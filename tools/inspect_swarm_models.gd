extends SceneTree
## Read-only static-model audit used by Milestone 21A inventory and verification.

const ROOT:="res://assets/factions/swarm/units"
var failures:=0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var paths:=PackedStringArray(); _collect(ROOT,paths); paths.sort()
	for path: String in paths: _inspect(path)
	quit(0 if failures==0 else 1)

func _collect(directory: String,result: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".glb"): result.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory): _collect(directory.path_join(child),result)

func _inspect(path: String) -> void:
	var packed:=load(path) as PackedScene
	if packed==null:
		failures+=1; push_error("Cannot load "+path); return
	var instance:=packed.instantiate() as Node3D
	var stats:={"file":path,"bytes":FileAccess.get_file_as_bytes(path).size(),"mesh_instances":0,"triangles":0,
		"materials":0,"bounds_min":Vector3.ZERO,"bounds_max":Vector3.ZERO,"skins":0,"bones":0,
		"animations":PackedStringArray(),"texture_count":0,"largest_texture":Vector2i.ZERO}
	var points: Array[Vector3]=[]; var materials:={}
	_inspect_node(instance,stats,points,materials,Transform3D.IDENTITY)
	stats.materials=materials.size()
	if not points.is_empty():
		var minimum:=points[0]; var maximum:=points[0]
		for point: Vector3 in points:
			minimum=minimum.min(point); maximum=maximum.max(point)
		stats.bounds_min=minimum; stats.bounds_max=maximum; stats.size=maximum-minimum
	var source_dir:=path.get_base_dir()
	for file: String in DirAccess.get_files_at(source_dir):
		if file.get_extension().to_lower() not in ["png","jpg","jpeg","webp"]: continue
		var texture:=load(source_dir.path_join(file)) as Texture2D
		if texture==null: continue
		stats.texture_count+=1
		if texture.get_width()*texture.get_height()>stats.largest_texture.x*stats.largest_texture.y:
			stats.largest_texture=Vector2i(texture.get_width(),texture.get_height())
	instance.free()
	print(JSON.stringify(stats))

func _inspect_node(node: Node,stats: Dictionary,points: Array[Vector3],materials: Dictionary,parent_transform: Transform3D) -> void:
	var transform:=parent_transform
	if node is Node3D: transform=parent_transform*(node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance:=node as MeshInstance3D; var mesh:=mesh_instance.mesh
		stats.mesh_instances+=1
		if mesh_instance.skin!=null: stats.skins+=1
		if mesh!=null:
			for surface in range(mesh.get_surface_count()):
				var arrays:=mesh.surface_get_arrays(surface); var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				stats.triangles+=indices.size()/3 if not indices.is_empty() else vertices.size()/3
				var material:=mesh_instance.get_surface_override_material(surface)
				if material==null: material=mesh.surface_get_material(surface)
				if material!=null: materials[material.get_instance_id()]=true
			var box:=mesh_instance.get_aabb()
			for x in [box.position.x,box.end.x]:
				for y in [box.position.y,box.end.y]:
					for z in [box.position.z,box.end.z]: points.append(transform*Vector3(x,y,z))
	if node is Skeleton3D: stats.bones+=node.get_bone_count()
	if node is AnimationPlayer:
		for clip: StringName in node.get_animation_list(): stats.animations.append(String(clip))
	for child: Node in node.get_children(): _inspect_node(child,stats,points,materials,transform)
