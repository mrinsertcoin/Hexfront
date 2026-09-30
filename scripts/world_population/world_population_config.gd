class_name WorldPopulationConfig
extends Resource
## Independent recipe for logical sites and neutral inhabitants.

const VERSION:=2
const OFF:="Off"
const SPARSE:="Sparse"
const STANDARD:="Standard"
const DENSE:="Dense"
const PRESETS:=[OFF,SPARSE,STANDARD,DENSE]

@export var enabled: bool=false
@export var generation_version: int=VERSION
## Zero keeps legacy derivation from the public terrain seed. Network hosts set
## a private non-zero seed that is never included in client match config.
@export var population_seed: int=0
@export_enum("Off","Sparse","Standard","Dense") var preset: String=OFF
@export var site_definition_ids: PackedStringArray=[] # Explicit-count compatibility/testing override.
@export var site_counts: Dictionary[String,int]={}
@export var neutral_group_ids: PackedStringArray=[]
@export_range(0.0,100.0) var trade_posts_per_1000_cells: float=0.0
@export_range(0.0,100.0) var resource_sites_per_1000_cells: float=0.0
@export_range(0.0,100.0) var ruins_per_1000_cells: float=0.0
@export_range(0.0,100.0) var neutral_groups_per_1000_cells: float=0.0
@export_range(0,100) var maximum_trade_posts: int=8
@export_range(0,200) var maximum_resource_sites: int=40
@export_range(0,100) var maximum_ruins: int=12
@export_range(0,200) var maximum_neutral_groups: int=40
@export_range(0,12) var site_spacing: int=3
@export_range(0,20) var safe_start_distance: int=4
@export_range(0,20) var major_site_spacing: int=8
@export_range(0,12) var neutral_spacing: int=3
@export_range(0,20) var neutral_start_distance: int=5
var start_cells: Array[int]=[]

static func from_preset(value: String) -> WorldPopulationConfig:
	var result:=WorldPopulationConfig.new()
	result.preset=value if value in PRESETS else STANDARD
	result.enabled=result.preset!=OFF
	match result.preset:
		SPARSE:
			result.trade_posts_per_1000_cells=2.0; result.resource_sites_per_1000_cells=8.0
			result.ruins_per_1000_cells=2.0; result.neutral_groups_per_1000_cells=7.0
		DENSE:
			result.trade_posts_per_1000_cells=5.0; result.resource_sites_per_1000_cells=22.0
			result.ruins_per_1000_cells=5.0; result.neutral_groups_per_1000_cells=20.0
		STANDARD:
			result.trade_posts_per_1000_cells=3.0; result.resource_sites_per_1000_cells=14.0
			result.ruins_per_1000_cells=3.0; result.neutral_groups_per_1000_cells=12.0
	return result

func validate(registry: ContentRegistry) -> PackedStringArray:
	var errors:=PackedStringArray()
	if generation_version!=VERSION: errors.append("Unsupported world-population version")
	if preset not in PRESETS: errors.append("Unknown world-population preset: "+preset)
	for id: String in site_definition_ids:
		if not registry.world_sites.has(id): errors.append("Unknown population site: "+id)
		if site_counts.get(id,0)<0: errors.append("Negative population count: "+id)
	for id: String in neutral_group_ids:
		if not registry.neutral_groups.has(id): errors.append("Unknown population neutral group: "+id)
	return errors

func fingerprint_record() -> String:
	var starts:=start_cells.duplicate(); starts.sort()
	return JSON.stringify({"version":generation_version,"population_seed":population_seed,"preset":preset,"enabled":enabled,
		"density":[trade_posts_per_1000_cells,resource_sites_per_1000_cells,ruins_per_1000_cells,neutral_groups_per_1000_cells],
		"caps":[maximum_trade_posts,maximum_resource_sites,maximum_ruins,maximum_neutral_groups],
		"spacing":[site_spacing,safe_start_distance,major_site_spacing,neutral_spacing,neutral_start_distance],
		"site_definition_ids":Array(site_definition_ids),"site_counts":site_counts,
		"neutral_group_ids":Array(neutral_group_ids),"start_cells":starts},"",true,true)
