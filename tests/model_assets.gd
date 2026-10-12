extends SceneTree

const EXPECTED_MAPPINGS := {
	"living_spider": "res://assets/factions/swarm/units/spider/source/spider.glb",
	"mite": "res://assets/factions/swarm/units/mite/source/mite.glb",
	"worker_ant": "res://assets/factions/swarm/units/worker_ant/source/worker_ant.glb",
	"fighter_ant": "res://assets/factions/swarm/units/warrior_ant/source/warrior_ant.glb",
	"fire_ant": "res://assets/factions/swarm/units/fire_ant_flamethrowers/source/fire_ant_flamethrowers.glb",
	"ant_queen": "res://assets/factions/swarm/units/queen_ant/source/queen_ant.glb",
	"dragonfly": "res://assets/factions/swarm/units/dragonfly/source/dragonfly.glb.glb",
	"mosquito": "res://assets/factions/swarm/units/mosquito/source/mosquito.glb",
	"living_caterpillar": "res://assets/factions/swarm/units/caterpillar/source/caterpillar.glb",
	"fire_moth": "res://assets/factions/swarm/units/firefly/source/firefly.glb",
	"admiral": "res://assets/factions/swarm/units/admiral/source/admiral.glb",
}
const EXPECTED_MISSING := [
	"poison_dart_frog", "bullfrog", "unke", "brimstone_butterfly",
]

var failures := 0
var instances_checked := 0

func contains_skeleton(node: Node) -> bool:
	if node is Skeleton3D:
		return true
	for child: Node in node.get_children():
		if contains_skeleton(child):
			return true
	return false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var mapping := VisualMap.new()
	var validation := mapping.validation_errors()
	check(validation.is_empty(), "Model visual registry must validate: " + "; ".join(validation))
	check(mapping.registered_model_ids().size() == 14, "Swarm models and both supplied village defenders have visual profiles")
	var registry := ContentRegistry.default()
	var faction := registry.faction("living_migration")
	check(faction != null, "Living Migration content exists")
	for unit_id: String in EXPECTED_MAPPINGS:
		var definition := registry.unit(unit_id)
		check(definition != null and definition.visual_id == unit_id, "Stable visual ID remains configured for " + unit_id)
		var profile := mapping.model_definition(unit_id)
		check(profile != null, "Mapped model profile exists for " + unit_id)
		if profile == null:
			continue
		check(profile.model_path == EXPECTED_MAPPINGS[unit_id], "Expected source model is mapped for " + unit_id)
		check(profile.model_scale.x > 0.0 and profile.model_scale.y > 0.0 and profile.model_scale.z > 0.0, "Positive scale is configured for " + unit_id)
		var packed := mapping.asset_scene(unit_id)
		check(packed != null, "Mapped asset loads for " + unit_id)
		if packed != null:
			var instance := packed.instantiate()
			check(instance != null, "Mapped asset instantiates for " + unit_id)
			if instance != null:
				var meshes:=instance.find_children("*","MeshInstance3D",true,false)
				if not meshes.is_empty():
					var mesh:=meshes[0] as MeshInstance3D
					var source:=mesh.get_active_material(0) as BaseMaterial3D
					var original_color:=source.albedo_color; var original_metallic:=source.metallic
					TacticalModelMaterials.apply(instance)
					var adjusted:=mesh.get_active_material(0) as BaseMaterial3D
					check(adjusted!=source and adjusted.metallic==0.0 and adjusted.metallic_specular<=0.25,"Biological model uses a restrained matte presentation")
					check(source.albedo_color==original_color and source.metallic==original_metallic,"Presentation never mutates the imported material")
					check(adjusted.albedo_texture==source.albedo_texture and adjusted.albedo_color.a==source.albedo_color.a,"Authored textures and transparency are preserved")
					TacticalModelMaterials.apply(instance)
					check(mesh.get_active_material(0)==adjusted,"Repeated material setup is idempotent")
					var second:=packed.instantiate()
					TacticalModelMaterials.apply(second)
					var second_mesh:=second.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
					check(second_mesh.get_active_material(0)==adjusted,"Multiple units reuse a cached material rather than duplicating textures")
					second.free()
				if unit_id == "living_spider":
					check(contains_skeleton(instance), "Living Spider imported armature is preserved")
				instance.free()
			instances_checked += 1
	for unit_id: String in EXPECTED_MISSING:
		check(unit_id in faction.unit_roster_ids, "Missing model unit remains in the roster: " + unit_id)
		check(not mapping.has_real_model(unit_id), "Missing model retains generated placeholder: " + unit_id)
		check(mapping.asset_scene(unit_id) == null, "Missing model has no accidental asset mapping: " + unit_id)
	var variant := mapping.model_definition("fire_ant_unarmed_variant")
	check(variant != null and variant.model_path.ends_with("fire_ant.glb"), "Unarmed Fire Ant variant is inventoried separately")
	check(registry.unit("fire_ant_unarmed_variant") == null, "Visual-only variant does not create a gameplay unit")
	print("Model asset checks complete: ", instances_checked, " mapped assets, 4 documented placeholders; failures=", failures)
	quit(0 if failures == 0 else 1)
