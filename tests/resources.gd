extends SceneTree
var failures: int = 0
var scenes_checked: int = 0

func _initialize() -> void:
	call_deferred("_run")

func scan(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.ends_with(".tscn") or file.ends_with(".glb"):
			var resource: Resource = load(path.path_join(file))
			if not resource is PackedScene:
				failures += 1
				push_error("Cannot load scene: " + path.path_join(file))
				continue
			var instance: Node = (resource as PackedScene).instantiate()
			if instance == null:
				failures += 1
			else:
				instance.free()
			scenes_checked += 1
	for directory: String in DirAccess.get_directories_at(path):
		scan(path.path_join(directory))

func _run() -> void:
	scan("res://assets")
	scan("res://scenes")
	var mapping := VisualMap.new()
	if mapping.asset_scene("Unknown") != null or mapping.unit_scene("Unknown") != null or mapping.structure_scene("Unknown") != null:
		failures += 1
		push_error("Unknown visual types must return null safely")
	var board := PlanetBoard.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform vec4 team_accent : source_color; void fragment() { ALBEDO = team_accent.rgb; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	var tinted: ShaderMaterial = board._duplicate_and_tint_material(material, Color.RED) as ShaderMaterial
	if tinted.get_shader_parameter("team_accent") != Color.RED or tinted == material:
		failures += 1
		push_error("Shader team tint must use an independent material")
	board.free()
	print("Resource checks complete: ", scenes_checked, " scenes/assets, fallback syntax, shader tint; failures=", failures)
	quit(0 if failures == 0 else 1)

