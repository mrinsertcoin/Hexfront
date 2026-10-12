class_name ModelVisualDefinition
extends Resource
## Presentation-only mapping from a stable visual ID to an authored model.

@export var id: String
@export_file("*.glb", "*.gltf", "*.tscn") var model_path: String
@export var model_scale: Vector3 = Vector3.ONE
@export var rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var height_offset: float = 0.0
@export_range(0.05, 10.0, 0.01) var preview_scale: float = 1.0
@export_range(0.0, 100.0, 0.05) var preview_camera_distance: float = 0.0
@export var preview_rotation_offset: Vector3 = Vector3.ZERO
@export var preview_vertical_offset: float = 0.0
@export_range(0.1, 2.0, 0.01) var squad_member_scale: float = 1.0
@export_range(0.5, 2.5, 0.01) var squad_spacing: float = 1.0
@export_enum("default", "cross_five") var squad_formation: String = "default"
@export_multiline var notes: String

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ContentRegistry.valid_id(id):
		errors.append("Invalid model visual ID: " + id)
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		errors.append("Model visual %s has a missing model: %s" % [id, model_path])
	else:
		var model := load(model_path)
		if not model is PackedScene:
			errors.append("Model visual %s is not a PackedScene: %s" % [id, model_path])
	if model_scale.x <= 0.0 or model_scale.y <= 0.0 or model_scale.z <= 0.0:
		errors.append("Model visual %s has a non-positive scale" % id)
	if squad_member_scale<=0.0 or squad_spacing<=0.0 or preview_scale<=0.0 or preview_camera_distance<0.0:
		errors.append("Model visual %s has invalid squad presentation values" % id)
	return errors
