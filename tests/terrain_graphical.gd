extends "res://tests/hotseat.gd"

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/8d_"+label+".png")==OK,"Capture saved")

func legacy_placeholder_arrays() -> Array[Texture2DArray]:
	var ground_images: Array[Image]=[]
	var surface_images: Array[Image]=[]
	for layer in range(5):
		var ground:=Image.create(64,64,false,Image.FORMAT_RGBA8)
		var surface:=Image.create(64,64,false,Image.FORMAT_RGBA8)
		surface.fill(Color(0.5,0.5,0.5,1.0))
		for y in range(64):
			for x in range(64):
				var u:=TAU*x/64.0; var v:=TAU*y/64.0
				var grain:=0.91+0.012*sin(u*7.0+sin(v*3.0)*2.0)+0.01*cos(v*11.0+sin(u*5.0)*2.0)+0.018*sin(u+cos(v*2.0))
				ground.set_pixel(x,y,Color(grain,grain,grain,0.9))
		ground.generate_mipmaps(); surface.generate_mipmaps()
		ground_images.append(ground); surface_images.append(surface)
	var ground_array:=Texture2DArray.new(); ground_array.create_from_images(ground_images)
	var surface_array:=Texture2DArray.new(); surface_array.create_from_images(surface_images)
	return [ground_array,surface_array]

func image_difference(a: Image,b: Image) -> Dictionary:
	var left:=a.get_data(); var right:=b.get_data()
	var changed:=0; var difference:=0.0; var pixels:=mini(a.get_width()*a.get_height(),b.get_width()*b.get_height())
	for offset in range(0,pixels*4,4):
		var delta:=absi(left[offset]-right[offset])+absi(left[offset+1]-right[offset+1])+absi(left[offset+2]-right[offset+2])
		difference+=delta/3.0
		if delta>18: changed+=1
	return {"changed_ratio":float(changed)/pixels,"mean_rgb_byte_difference":difference/pixels}

func verify_material_binding(material: ShaderMaterial) -> void:
	var ground:=material.get_shader_parameter("ground_maps") as Texture2DArray
	var surface:=material.get_shader_parameter("normal_maps") as Texture2DArray
	check(ground!=null and ground.get_layers()==5,"Production shader has five PBR ground layers")
	check(surface!=null and surface.get_layers()==5,"Production shader has five packed PBR surface layers")
	var atlas:=Image.create(ground.get_width()*5,ground.get_height(),false,Image.FORMAT_RGBA8)
	var layer_means: Array[Color]=[]
	for layer in range(5):
		var image:=ground.get_layer_data(layer)
		image.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(layer*image.get_width(),0))
		var sum:=Color(0,0,0,0)
		for y in range(0,image.get_height(),16):
			for x in range(0,image.get_width(),16): sum+=image.get_pixel(x,y)
		layer_means.append(sum/float(ceili(image.get_width()/16.0)*ceili(image.get_height()/16.0)))
	check(atlas.save_png("res://.godot/terrain_material_layers.png")==OK,"Packed PBR layer atlas saved")
	check(layer_means[0].g>layer_means[0].r*1.12,"Grass runtime layer retains green authored albedo")
	check(layer_means[2].r>layer_means[2].b*1.12,"Dry runtime layer retains warm authored sand")
	check(layer_means[1].get_luminance()<layer_means[0].get_luminance(),"Forest runtime layer remains darker than grass")
	print("PBR runtime layer means: ",layer_means)

func _run() -> void:
	await setup(true,4 if "--dense" in OS.get_cmdline_user_args() else 3)
	var production_material: ShaderMaterial=board.terrain_renderer.chunks[0].material_override
	verify_material_binding(production_material)
	for seed_value: int in [48293617,246813579,-42]:
		if board.generated_planet.config.world_seed != seed_value: board.regenerate_world(seed_value)
		board._reset_camera()
		board.feedback_label.text=""
		board.navigation.distance=16; board.navigation.target_distance=16; board._update_camera_transform(0)
		await capture("terrain_%d_overview" % seed_value)
		board.navigation.distance=4; board.navigation.target_distance=4; board._update_camera_transform(0)
		await capture("terrain_%d_close" % seed_value)
		for lake: LakeData in board.generated_planet.hydrology.lakes:
			board.focus_cell(lake.cell_ids[0],true)
			await capture("terrain_%d_lake" % seed_value)
			break
		for pole: float in [-89.9,89.9]:
			_globe_pose(0, pole, 4)
			await capture("terrain_%d_pole_%d" % [seed_value,int(pole)])
	board._reset_camera()
	board.navigation.distance=6; board.navigation.target_distance=6
	board._update_camera_transform(0)
	board.select_at(_screen(board.game_state.units[2].cell_id))
	await capture("terrain_overlays")
	board.clear_selection()
	var frames: Array[float]=[]
	for i in range(180):
		var started: int=Time.get_ticks_usec()
		board.navigation.yaw+=0.5; board._update_camera_transform(0)
		await process_frame
		frames.append((Time.get_ticks_usec()-started)/1000.0)
	frames.sort()
	print("8D renderer profile cells=",board.grid.cells.size()," triangles=",board.terrain_renderer.triangle_count," median_ms=",frames[90]," p95_ms=",frames[171]," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	# Render the same camera with the pre-integration procedural layers. This
	# catches valid-looking screenshots where authored arrays were never bound.
	board.feedback_label.text=""
	production_material=board.terrain_renderer.chunks[0].material_override
	await capture("terrain_material_pbr")
	var pbr_image:=root.get_texture().get_image()
	var original_parameters:={}
	for parameter: String in ["ground_maps","normal_maps","detail_maps","detail_normal_maps","layer_tints","layer_scales"]:
		original_parameters[parameter]=production_material.get_shader_parameter(parameter)
	var legacy:=legacy_placeholder_arrays()
	production_material.set_shader_parameter("ground_maps",legacy[0])
	production_material.set_shader_parameter("detail_maps",legacy[0])
	production_material.set_shader_parameter("normal_maps",legacy[1])
	production_material.set_shader_parameter("detail_normal_maps",legacy[1])
	production_material.set_shader_parameter("layer_tints",PackedColorArray([
		Color("#75834b"),Color("#344c32"),Color("#b39867"),Color("#7b7c77"),Color("#465849")]))
	production_material.set_shader_parameter("layer_scales",PackedFloat32Array([1.25,1.25,1.25,1.25,1.25]))
	await capture("terrain_material_legacy_placeholder")
	var legacy_image:=root.get_texture().get_image()
	var comparison:=image_difference(pbr_image,legacy_image)
	check(comparison.changed_ratio>0.35,"Authored PBR render differs materially from legacy placeholders")
	check(comparison.mean_rgb_byte_difference>5.0,"Authored PBR render has substantial visible color difference")
	print("PBR vs legacy rendered difference: ",comparison)
	for parameter: String in original_parameters:
		production_material.set_shader_parameter(parameter,original_parameters[parameter])
	await process_frame
	# Production materials/geometry are deterministic as well as debug colors.
	board.feedback_label.text=""
	await capture("production_identity_before")
	var before: Image=root.get_texture().get_image()
	board.regenerate_world(board.generated_planet.config.world_seed)
	board.feedback_label.text=""
	await capture("production_identity_after")
	check(before.get_data()==root.get_texture().get_image().get_data(),"Same seed production rendering is pixel-identical")
	var material: ShaderMaterial=board.terrain_renderer.chunks[0].material_override
	material.set_shader_parameter("wet_strength",0.0)
	await capture("wetness_disabled")
	check(before.get_data()!=root.get_texture().get_image().get_data(),"Hydrology wetness changes rendered ground")
	material.set_shader_parameter("wet_strength",board.terrain_config.wetness_strength)
	material.set_shader_parameter("rock_strength",0.0)
	await capture("slope_rock_disabled")
	check(before.get_data()!=root.get_texture().get_image().get_data(),"Slope exposure changes rendered rock contribution")
	material.set_shader_parameter("rock_strength",board.terrain_config.slope_rock_strength)
	await finish("Terrain graphical")
