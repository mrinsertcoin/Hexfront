class_name ModelPreview
extends SubViewportContainer
## Lightweight isolated model viewport; no world state or world camera is reused.

var viewport_3d: SubViewport
var model_root: Node3D
var visual_map:=VisualMap.new()

func _ready() -> void:
	custom_minimum_size=Vector2(260,150); stretch=true; mouse_filter=Control.MOUSE_FILTER_IGNORE
	viewport_3d=SubViewport.new(); viewport_3d.name="PreviewViewport"; viewport_3d.size=Vector2i(320,180)
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS; viewport_3d.own_world_3d=true; add_child(viewport_3d)
	model_root=Node3D.new(); model_root.name="ModelRoot"; viewport_3d.add_child(model_root)
	var camera:=Camera3D.new(); camera.position=Vector3(0,1.1,3.4); camera.look_at_from_position(camera.position,Vector3(0,0.45,0)); viewport_3d.add_child(camera)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); light.light_energy=1.4; viewport_3d.add_child(light)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("#10191d"); viewport_3d.add_child(environment)
	set_process(true)

func show_model(visual_id: String) -> void:
	for child: Node in model_root.get_children(): child.queue_free()
	var scene:=visual_map.asset_scene(visual_id)
	if scene!=null:
		var instance:=scene.instantiate() as Node3D; model_root.add_child(instance)
		var profile:=visual_map.model_definition(visual_id)
		if profile!=null: instance.scale=profile.model_scale; instance.rotation_degrees=profile.rotation_offset_degrees
	else:
		var fallback:=MeshInstance3D.new(); fallback.mesh=CapsuleMesh.new(); fallback.material_override=StandardMaterial3D.new(); fallback.material_override.albedo_color=Color("#6cae9b"); model_root.add_child(fallback)

func clear_model() -> void:
	for child: Node in model_root.get_children(): child.queue_free()

func _process(delta: float) -> void:
	if model_root!=null: model_root.rotate_y(delta*0.35)
