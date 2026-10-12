class_name TacticalModelMaterials
extends RefCounted
## Shared presentation overrides for imported biological models; originals and
## textures remain untouched, and squads/previews reuse the same material.
static var _cache: Dictionary[int,BaseMaterial3D]={}

static func apply(root: Node3D) -> void:
	for node: Node in root.find_children("*","MeshInstance3D",true,false):
		var instance:=node as MeshInstance3D
		if instance.mesh==null: continue
		for surface in range(instance.mesh.get_surface_count()):
			var source:=instance.get_active_material(surface) as BaseMaterial3D
			if source==null or source.has_meta("tactical_matte") or "HX_TeamAccent" in source.resource_name: continue
			var key:=source.get_instance_id()
			if not _cache.has(key):
				var material:=source.duplicate(false) as BaseMaterial3D
				material.metallic=0.0; material.metallic_specular=0.22
				material.roughness=maxf(0.85,source.roughness)
				material.normal_scale=minf(0.65,source.normal_scale)
				material.albedo_color=source.albedo_color*Color(0.86,0.88,0.86,1.0)
				material.set_meta("tactical_matte",true)
				_cache[key]=material
			instance.set_surface_override_material(surface,_cache[key])
