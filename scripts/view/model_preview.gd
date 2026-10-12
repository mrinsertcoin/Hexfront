class_name ModelPreview
extends SubViewportContainer
## Lightweight isolated model viewport; no world state or world camera is reused.

var viewport_3d: SubViewport
var model_root: Node3D
var camera: Camera3D
var visual_map:=VisualMap.new()
var current_visual_id: String=""
var _load_generation: int=0

func _ready() -> void:
	if custom_minimum_size==Vector2.ZERO: custom_minimum_size=Vector2(128,112)
	stretch=true; mouse_filter=Control.MOUSE_FILTER_STOP
	viewport_3d=SubViewport.new(); viewport_3d.name="PreviewViewport"; viewport_3d.size=Vector2i(320,180)
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_WHEN_PARENT_VISIBLE; viewport_3d.own_world_3d=true; add_child(viewport_3d)
	model_root=Node3D.new(); model_root.name="ModelRoot"; viewport_3d.add_child(model_root)
	camera=Camera3D.new(); camera.fov=32.0; camera.near=0.02; camera.position=Vector3(0,1.1,3.4); camera.look_at_from_position(camera.position,Vector3(0,0.45,0)); viewport_3d.add_child(camera)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); light.light_energy=0.9; viewport_3d.add_child(light)
	var fill:=DirectionalLight3D.new(); fill.rotation_degrees=Vector3(35,145,0); fill.light_energy=0.35; fill.light_color=Color("#bdcbd5"); viewport_3d.add_child(fill)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("#10191d"); viewport_3d.add_child(environment)
	set_process(true)

func show_model(visual_id: String) -> void:
	if visual_id==current_visual_id and model_root.get_child_count()>0: return
	current_visual_id=visual_id; _load_generation+=1
	for child: Node in model_root.get_children(): child.queue_free()
	var scene:=visual_map.asset_scene(visual_id)
	if scene!=null:
		var instance:=scene.instantiate() as Node3D; model_root.add_child(instance)
		var profile:=visual_map.model_definition(visual_id)
		if profile!=null:
			TacticalModelMaterials.apply(instance)
			instance.scale=profile.model_scale*profile.preview_scale
			instance.rotation_degrees=profile.rotation_offset_degrees+profile.preview_rotation_offset
			instance.position.y=profile.preview_vertical_offset
	else:
		var fallback:=MeshInstance3D.new(); fallback.mesh=CapsuleMesh.new(); fallback.material_override=StandardMaterial3D.new(); fallback.material_override.albedo_color=Color("#6cae9b"); model_root.add_child(fallback)
	_frame_model.call_deferred(_load_generation,visual_id)

func clear_model() -> void:
	current_visual_id=""; _load_generation+=1
	for child: Node in model_root.get_children(): child.queue_free()

func _process(delta: float) -> void:
	if model_root!=null and is_visible_in_tree() and not current_visual_id.is_empty(): model_root.rotate_y(delta*0.35)

func _frame_model(generation: int,visual_id: String) -> void:
	if generation!=_load_generation or model_root==null: return
	var bounds:=_visual_bounds()
	var center:=bounds.get_center(); var radius:=maxf(0.25,bounds.size.length()*0.5)
	var profile:=visual_map.model_definition(visual_id)
	var distance:=profile.preview_camera_distance if profile!=null and profile.preview_camera_distance>0.0 else radius/tan(deg_to_rad(camera.fov*0.5))*1.22
	distance=maxf(0.8,distance); camera.far=maxf(20.0,distance+radius*4.0)
	var target:=center+Vector3.UP*radius*0.05
	camera.look_at_from_position(target+Vector3(0.0,radius*0.12,distance),target,Vector3.UP)

func _visual_bounds() -> AABB:
	var found:=false; var minimum:=Vector3.ZERO; var maximum:=Vector3.ZERO
	for node: Node in model_root.find_children("*","MeshInstance3D",true,false):
		var mesh_node:=node as MeshInstance3D
		if mesh_node.mesh==null: continue
		var box:=mesh_node.mesh.get_aabb(); var relative:=model_root.global_transform.affine_inverse()*mesh_node.global_transform
		for x: int in [0,1]:
			for y: int in [0,1]:
				for z: int in [0,1]:
					var point:=relative*(box.position+Vector3(box.size.x*x,box.size.y*y,box.size.z*z))
					if not found: minimum=point; maximum=point; found=true
					else: minimum=minimum.min(point); maximum=maximum.max(point)
	return AABB(minimum,maximum-minimum) if found else AABB(Vector3(-0.5,0.0,-0.5),Vector3.ONE)
