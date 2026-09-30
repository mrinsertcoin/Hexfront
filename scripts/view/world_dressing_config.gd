class_name WorldDressingConfig
extends Resource
## Presentation-only cluster budget and reviewed stylized asset catalog.

const VERSION:=2
const ASSET_VERSION:=2
@export var visual_generation_version: int = VERSION
@export_range(0.0, 2.0) var density_multiplier: float = 1.0
@export_range(0.01, 1.0) var candidates_per_square_unit: float = 0.05
@export var maximum_candidates: int = 1600
@export var enabled: bool = true
@export var definitions: Array[DressingDefinition] = defaults()

static func defaults() -> Array[DressingDefinition]:
	var vegetation:=DressingDefinition.Category.VEGETATION
	var rock:=DressingDefinition.Category.ROCK
	var debris:=DressingDefinition.Category.DEBRIS
	var tactical:=DressingDefinition.DetailBand.TACTICAL
	var regional:=DressingDefinition.DetailBand.REGIONAL
	var strategic:=DressingDefinition.DetailBand.STRATEGIC
	var canopy:=DressingMeshVariant.create("forest_tree_canopy_01","res://assets/environment/stylized/trees/forest_tree_canopy_01","005",1.0,9.0,vegetation,strategic,true,Color("#dce3d4"))
	var conifer:=DressingMeshVariant.create("conifer_pair_01","res://assets/environment/stylized/trees/conifer_pair_01","008",0.9,10.0,vegetation,strategic,true,Color("#d6dfd1"))
	var branching:=DressingMeshVariant.create("forest_tree_branching_01","res://assets/environment/stylized/trees/forest_tree_branching_01","009",1.0,10.0,vegetation,strategic,true,Color("#dce0d2"))
	var bush:=DressingMeshVariant.create("woodland_bush_01","res://assets/environment/stylized/bushes/woodland_bush_01","011",1.2,5.0,vegetation,regional,false,Color("#d7dfcf"))
	var ground:=DressingMeshVariant.create("ground_cover_01","res://assets/environment/stylized/ground_cover/ground_cover_01","012",1.1,3.0,vegetation,tactical,false,Color("#d4d9c7"))
	var boulder:=DressingMeshVariant.create("boulder_01","res://assets/environment/stylized/rocks/boulder_01","013",1.2,5.0,rock,strategic,true,Color("#d2d0c8"))
	var formation:=DressingMeshVariant.create("rock_formation_01","res://assets/environment/stylized/formations/rock_formation_01","017",0.8,9.0,rock,strategic,true,Color("#d0cec5"))
	var deadwood:=DressingMeshVariant.create("deadwood_01","res://assets/environment/stylized/debris/deadwood_01","010",0.7,6.0,debris,regional,false,Color("#d2c5ad"))
	var result: Array[DressingDefinition]=[]
	var forest:=DressingDefinition.create("forest_groves",vegetation,[0.12,1.0,0.02,0.03,0.18],0.34,36.0,5,10,2.8,[canopy,conifer,branching,bush,ground,deadwood])
	forest.fertility_response=.75; forest.moisture_response=.35; forest.roughness_response=-.45; forest.cluster_frequency=1.1; result.append(forest)
	var copse:=DressingDefinition.create("grassland_copses",vegetation,[1.0,.20,.12,.05,.18],.18,42.0,1,3,2.0,[branching,bush,boulder])
	copse.fertility_response=.35; copse.roughness_response=-.25; copse.cluster_frequency=1.8; result.append(copse)
	var rocks:=DressingDefinition.create("rock_fields",rock,[.10,.04,.48,1.0,.08],.28,72.0,4,7,2.1,[boulder,formation])
	rocks.roughness_response=.9; rocks.height_response=.3; rocks.cluster_frequency=1.35; rocks.exclude_rivers=false; result.append(rocks)
	var wet:=DressingDefinition.create("wetland_growth",vegetation,[.08,.15,.02,.01,1.0],.38,25.0,3,6,1.7,[bush,ground,deadwood])
	wet.moisture_response=.8; wet.wetland_response=.9; wet.roughness_response=-.6; wet.cluster_frequency=1.65; result.append(wet)
	var dry:=DressingDefinition.create("dryland_scrub",debris,[.18,.08,1.0,.18,.04],.24,48.0,2,5,2.4,[bush,ground,boulder,deadwood])
	dry.moisture_response=-.7; dry.fertility_response=-.35; dry.cluster_frequency=1.9; result.append(dry)
	return result

func candidate_count(radius: float) -> int:
	return mini(maximum_candidates,maxi(0,roundi(4.0*PI*radius*radius*candidates_per_square_unit*density_multiplier)))

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if visual_generation_version!=VERSION: errors.append("Unsupported visual dressing version")
	if density_multiplier<0 or candidates_per_square_unit<=0 or maximum_candidates<0: errors.append("Invalid dressing density budget")
	var ids:={}
	for definition: DressingDefinition in definitions:
		if definition==null or ids.has(definition.definition_id): errors.append("Dressing definitions require unique IDs"); continue
		ids[definition.definition_id]=true
		var error:=definition.validate()
		if not error.is_empty(): errors.append(error)
	return errors
