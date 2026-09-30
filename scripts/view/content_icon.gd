class_name ContentIcon
extends RefCounted
## Optional content icon loader. Missing or invalid art deliberately falls back to text.

static func texture(definition: Resource) -> Texture2D:
	if definition==null: return null
	var path: String=str(definition.get("icon_path"))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

static func apply(button: Button,definition: Resource) -> void:
	var image:=texture(definition)
	if image!=null: button.icon=image
