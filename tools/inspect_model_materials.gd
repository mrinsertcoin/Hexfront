extends SceneTree
## Read-only import audit: identify unlit, emissive and reflective materials.
func _initialize() -> void:
	var mapping:=VisualMap.new()
	for id: String in ["living_spider","worker_ant","fighter_ant","dragonfly","mite","admiral"]:
		var scene:=mapping.asset_scene(id).instantiate()
		for node: Node in scene.find_children("*","MeshInstance3D",true,false):
			var instance:=node as MeshInstance3D
			for index in range(instance.mesh.get_surface_count()):
				var material:=instance.get_active_material(index) as BaseMaterial3D
				if material!=null: print("MATERIAL ",id," shading=",material.shading_mode," albedo=",material.albedo_color," metallic=",material.metallic," roughness=",material.roughness," specular=",material.metallic_specular," emission=",material.emission_enabled," emission_energy=",material.emission_energy_multiplier," normal_scale=",material.normal_scale)
		scene.free()
	quit()
