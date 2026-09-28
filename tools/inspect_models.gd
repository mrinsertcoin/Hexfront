extends SceneTree
## Read both GLB metadata and Godot's imported node hierarchy, without edits.
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_scan("res://assets")
	quit(0 if failures == 0 else 1)

func _scan(directory: String) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".glb"):
			_inspect(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_scan(directory.path_join(child))

func _inspect(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != 0x46546c67 or file.get_32() != 2:
		_fail(path + ": invalid GLB header")
		return
	file.get_32() # Overall byte length.
	var length: int = file.get_32()
	if file.get_32() != 0x4e4f534a:
		_fail(path + ": missing GLB JSON chunk")
		return
	var document: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	if not document is Dictionary:
		_fail(path + ": invalid JSON")
		return
	var stats: Dictionary = {"file": path, "skins": document.get("skins", []).size(), "joints": 0, "weighted_primitives": 0, "glb_clips": [], "godot_skeletons": 0, "godot_bones": 0, "godot_skinned_meshes": 0, "godot_clips": []}
	for skin: Dictionary in document.get("skins", []):
		stats.joints += skin.get("joints", []).size()
	for mesh: Dictionary in document.get("meshes", []):
		for primitive: Dictionary in mesh.get("primitives", []):
			var attributes: Dictionary = primitive.get("attributes", {})
			if attributes.has("JOINTS_0") and attributes.has("WEIGHTS_0"):
				stats.weighted_primitives += 1
	for clip: Dictionary in document.get("animations", []):
		stats.glb_clips.append(clip.get("name", "<unnamed>"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_fail(path + ": cannot load imported scene")
		return
	var instance: Node = scene.instantiate()
	_inspect_node(instance, stats)
	instance.free()
	print(JSON.stringify(stats))

func _inspect_node(node: Node, stats: Dictionary) -> void:
	if node is Skeleton3D:
		stats.godot_skeletons += 1
		stats.godot_bones += (node as Skeleton3D).get_bone_count()
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		stats.godot_skinned_meshes += 1
	if node is AnimationPlayer:
		for clip: StringName in (node as AnimationPlayer).get_animation_list():
			stats.godot_clips.append(String(clip))
	for child: Node in node.get_children():
		_inspect_node(child, stats)

func _fail(message: String) -> void:
	failures += 1
	push_error(message)
