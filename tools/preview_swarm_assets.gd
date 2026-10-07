extends SceneTree
## Graphical source-asset contact sheet. It does not change imports or gameplay.

const MODELS: Array[Dictionary]=[
	{"label":"Admiral","path":"res://assets/factions/swarm/units/admiral/source/admiral.glb"},
	{"label":"Caterpillar","path":"res://assets/factions/swarm/units/caterpillar/source/caterpillar.glb"},
	{"label":"Dragonfly","path":"res://assets/factions/swarm/units/dragonfly/source/dragonfly.glb.glb"},
	{"label":"Fire Ant","path":"res://assets/factions/swarm/units/fire_ant/source/fire_ant.glb"},
	{"label":"Fire Ant + weapons","path":"res://assets/factions/swarm/units/fire_ant_flamethrowers/source/fire_ant_flamethrowers.glb"},
	{"label":"Firefly","path":"res://assets/factions/swarm/units/firefly/source/firefly.glb"},
	{"label":"Mite","path":"res://assets/factions/swarm/units/mite/source/mite.glb"},
	{"label":"Mosquito","path":"res://assets/factions/swarm/units/mosquito/source/mosquito.glb"},
	{"label":"Queen Ant","path":"res://assets/factions/swarm/units/queen_ant/source/queen_ant.glb"},
	{"label":"Spider","path":"res://assets/factions/swarm/units/spider/source/spider.glb"},
	{"label":"Warrior Ant","path":"res://assets/factions/swarm/units/warrior_ant/source/warrior_ant.glb"},
	{"label":"Worker Ant","path":"res://assets/factions/swarm/units/worker_ant/source/worker_ant.glb"},
]

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Run preview_swarm_assets.gd with a graphical display."); quit(1); return
	get_root().size=Vector2i(1600,900)
	var world:=Node3D.new(); get_root().add_child(world)
	var environment:=WorldEnvironment.new(); var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("#172027")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("#d8e3e8"); settings.ambient_light_energy=0.65
	environment.environment=settings; world.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-48,-25,0); light.light_energy=1.8; light.shadow_enabled=true; world.add_child(light)
	var ground:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(14,10); ground.mesh=plane
	var ground_material:=StandardMaterial3D.new(); ground_material.albedo_color=Color("#48565b"); ground.material_override=ground_material; world.add_child(ground)
	for index in range(MODELS.size()):
		var entry:=MODELS[index]; var packed:=load(entry.path) as PackedScene; var model:=packed.instantiate() as Node3D
		var bounds:=_bounds(model); var size: Vector3=bounds.size; var factor:=1.25/maxf(size.x,maxf(size.y,size.z))
		model.scale=Vector3.ONE*factor
		model.position=Vector3((index%4-1.5)*3.2,-bounds.position.y*factor,(index/4-1.0)*3.0)
		world.add_child(model)
		var label:=Label3D.new(); label.text=entry.label; label.font_size=38; label.pixel_size=0.007; label.outline_size=8
		label.position=model.position+Vector3(0,1.55,0); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; world.add_child(label)
	var camera:=Camera3D.new(); camera.position=Vector3(0,8.5,11.5); camera.look_at_from_position(camera.position,Vector3(0,0.35,0)); camera.fov=48; world.add_child(camera)
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var error:=get_root().get_texture().get_image().save_png("res://.godot/swarm_asset_inventory.png")
	print("Swarm asset preview: ",error," -> .godot/swarm_asset_inventory.png")
	quit(0 if error==OK else 1)

func _bounds(root: Node3D) -> AABB:
	var points: Array[Vector3]=[]; _collect_points(root,Transform3D.IDENTITY,points)
	if points.is_empty(): return AABB(Vector3(-0.5,0,-0.5),Vector3.ONE)
	var minimum:=points[0]; var maximum:=points[0]
	for point: Vector3 in points: minimum=minimum.min(point); maximum=maximum.max(point)
	return AABB(minimum,maximum-minimum)

func _collect_points(node: Node,parent_transform: Transform3D,points: Array[Vector3]) -> void:
	var transform:=parent_transform
	if node is Node3D: transform=parent_transform*(node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
		var box:=(node as MeshInstance3D).get_aabb()
		for x in [box.position.x,box.end.x]:
			for y in [box.position.y,box.end.y]:
				for z in [box.position.z,box.end.z]: points.append(transform*Vector3(x,y,z))
	for child: Node in node.get_children(): _collect_points(child,transform,points)
