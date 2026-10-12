class_name PlanetBoard
extends Node3D


const VisualMap = preload("res://scripts/view/visual_map.gd")
var visual_map: VisualMap = VisualMap.new()

const SURFACE_OFFSET: float = 0.006
const NONE: int = -1

var selected: int = NONE
var tiles: Dictionary[int, MeshInstance3D] = {}
var camera: Camera3D
var coordinate_label: Label
var selected_material: StandardMaterial3D
var reachable_material: StandardMaterial3D
var path_material: StandardMaterial3D
var attack_material: StandardMaterial3D
var road_material: StandardMaterial3D
var connected_material: StandardMaterial3D
var depleted_material: StandardMaterial3D
var regrowing_material: StandardMaterial3D
var heal_material: StandardMaterial3D
var repair_material: StandardMaterial3D
var designation_material: StandardMaterial3D
var interaction_material: StandardMaterial3D
# Direct/debug instantiation uses the inexpensive internal preset. Normal games
# are always overridden by MatchConfig before this node enters the scene tree.
@export_range(0, 5) var subdivision_level: int = 3
@export var planet_radius: float = 12.0
@export var generation_config: PlanetGenerationConfig
@export var population_config: WorldPopulationConfig
var game_state: GameState
var population_result: WorldPopulationResult
var grid: PlanetGrid
var generated_planet: GeneratedPlanet
@export var terrain_config: TerrainRenderConfig
var match_config: MatchConfig
var terrain_renderer: PlanetTerrainRenderer
var terrain_surface: TerrainSurfaceSampler
var world_debug_view: PlanetWorldDebugView
var world_debug_panel: PlanetWorldDebugPanel
var hover_material: StandardMaterial3D
var debug_outlines: MeshInstance3D
var debug_centers: MeshInstance3D
var debug_pentagons: MeshInstance3D
var debug_labels: Node3D
var rules: GameRules
var unit_views: Dictionary[int, EntityView] = {}
var site_views: Dictionary[int, Node3D]={}
var contact_views: Dictionary[int, Node3D]={}
var fog_overlay: FogOfWarOverlay
var view_observation: TeamObservation
var view_team_id: int=-1
var selected_contact_id: int=-1
var visibility_omniscient: bool=false
var _handled_visibility_revision: int=-1
@export var animate_movement: bool = true
var health_fills: Dictionary[int, MeshInstance3D] = {}
var attack_tiles: Array[int] = []
var restart_button: Button
var attack_preview_label: Label
var selected_unit_id: int = -1
var selected_structure_id: int = -1
var selected_site_id: int = -1
var selected_district_id: int = -1
var reachable_tiles: Array[int] = []
var preview_path: Array[int] = []
var hover_cell: int = NONE
var hud_panel: PanelContainer
var top_bar: PanelContainer
var action_panel: PanelContainer
var resource_bar: HBoxContainer
var strategic_panel: StrategicResearchPanel
var research_backdrop: PanelContainer
var notification_feed: StrategicNotificationFeed
var privacy_overlay: PanelContainer
var privacy_label: Label
var turn_label: Label
var players_label: Label
var selection_legend: Label
var unit_label: Label
var feedback_label: Label
var end_turn_button: Button
var feedback_seconds: float = 0.0
var placement_mode: bool = false
var input_mode: int = StrategicInputMode.Kind.NORMAL
var mode_source_id: int = -1
var mode_path: Array[int] = []
var recruit_choice: String = ""
var recruit_hq_id: int = -1
var materials_label: Label
var recruit_highlights: Array[int] = []
var road_highlights: Array[int] = []
var site_highlights: Array[int]=[]
var recruit_box: VBoxContainer
var match_mode: String = "Vs AI" # "Vs AI" or "Hotseat"
var player_controllers: Dictionary[int, String] = {1: "Human", 2: "AI"}

# AI runtime state
var _ai_running: bool = false
var _ai_token: int = 0
var _ai_delay: float = 0.25
const SimpleAI = preload("res://scripts/ai/simple_ai.gd")
var ai_agent: SimpleAI = SimpleAI.new()
var neutral_agent:=NeutralAI.new()

@export var camera_config: TacticalCameraConfig
var navigation := SurfaceCamera.new()
var _is_middle_dragging: bool = false
var _last_mouse_pos := Vector2.ZERO
var _left_pending: bool = false
var _left_dragging: bool = false
var _left_start := Vector2.ZERO
var _grab_direction := Vector3.ZERO
var camera_diagnostics: bool = false
var ui_scale: float = 1.0
var supply_overlay_visible: bool = false
var population_debug_visible: bool=false
var network_session: NetworkSession
var network_indicator: Label
var minimap: StrategicMinimap
var ant_road_overlay: AntRoadOverlay
var attack_order_overlay: AttackOrderOverlay
var management_panel: VBoxContainer
var next_unit_button: Button
var manage_cities_button: Button
var select_research_button: Button
var model_preview: ModelPreview
var unit_info_panel: UnitInfoPanel
var _building_unit_overlay: bool=false
var _unit_action_group: String=UnitInfoPanel.GROUP_SPECIAL
var _unit_actions_disabled_reason: String=""
var reviewed_units: Dictionary[int,bool]={}
var reviewed_cities: Dictionary[int,bool]={}
var management_turn_serial: int=-1
var _hover_query_valid: bool=false
var _hover_query_mouse:=Vector2.ZERO
var _hover_query_camera:=Transform3D.IDENTITY
var _hover_query_viewport:=Vector2.ZERO
var _connection_overlay_cells: Dictionary={}
var _selection_content: VBoxContainer
var _selection_layout_pending: bool=false


func configure_match(config: MatchConfig, settings: UserSettings) -> void:
	match_config = config.copy()
	var size := match_config.size_definition()
	subdivision_level = size.subdivision
	planet_radius = size.radius
	generation_config = PlanetGenerationConfig.new()
	generation_config.world_seed = match_config.world_seed
	generation_config.terraced_terrain=true
	generation_config.cliff_generation=match_config.cliff_generation
	population_config=WorldPopulationConfig.from_preset(match_config.world_population_preset)
	population_config.population_seed=match_config.private_population_seed
	population_config.villages_per_player=match_config.villages_per_player
	population_config.player_count=match_config.player_ids().size()
	if match_config.player_assignments.is_empty():
		player_controllers = {1: "Human", 2: match_config.opponent_controller}
		match_mode = "Hotseat" if match_config.opponent_controller == "Human" else "Vs AI"
	else:
		player_controllers.clear()
		for assignment: Dictionary in match_config.player_assignments:
			var player_id:=int(assignment.player_id)
			player_controllers[player_id]="Human" if player_id==1 else "Remote"
		match_mode="Network"
	apply_user_settings(settings)

func configure_network_host(config: MatchConfig,settings: UserSettings,session: NetworkSession) -> void:
	network_session=session
	configure_match(config,settings)

func apply_user_settings(settings: UserSettings) -> void:
	camera_config = settings.camera_configuration()
	if terrain_config == null: terrain_config = TerrainRenderConfig.new()
	terrain_config.terrain_subdivision_level = settings.terrain_subdivision()
	ui_scale = settings.ui_scale
	if camera != null:
		navigation.config = camera_config
		navigation.apply_transform()
	if top_bar!=null: _layout_hud()


func _ready() -> void:
	grid = PlanetGrid.new(subdivision_level, planet_radius)
	if generation_config == null:
		generation_config = PlanetGenerationConfig.new()
		generation_config.terraced_terrain=true
	generated_planet = GeneratedPlanet.generate(grid, generation_config)
	# Retain the canonical snapshot, including its deep-copied recipe.
	generation_config = generated_planet.config
	var faction_ids: Array[String]=["blue","red"]
	var controller_kinds: Array[String]=[ControllerState.HUMAN,ControllerState.PLAYER_AI]
	var team_ids: Array[int]=[1,2]
	var player_ids: Array[int]=[1,2]
	var player_names: Array[String]=["Player 1","Player 2"]
	var player_colors: Array[String]=[]
	if match_config!=null:
		faction_ids=match_config.faction_ids(); controller_kinds=match_config.controller_kinds(); team_ids=match_config.team_ids()
		player_ids=match_config.player_ids(); player_names=match_config.player_names()
		if not match_config.player_assignments.is_empty(): player_colors=match_config.player_colors()
	var start_suitability:=_build_start_suitability(player_ids,faction_ids)
	game_state = GameState.new(grid,{"faction_ids":faction_ids,"controller_kinds":controller_kinds,"team_ids":team_ids,
		"player_ids":player_ids,"player_names":player_names,"player_colors":player_colors,
		"start_suitability":start_suitability,"start_seed":generation_config.world_seed,"match_seed":generation_config.world_seed,
		"water_cells":_water_cell_ids(),"simultaneous_combat":true,"simultaneous_player_turns":true})
	game_state.terrain=generated_planet.terraces
	if population_config==null:
		population_config=WorldPopulationConfig.new()
		# Direct/debug boards retain their historical empty-world fixture. Normal
		# matches always arrive through MatchConfig, whose village default is two.
		population_config.villages_per_player=0
	population_config.start_cells=_player_start_cells()
	population_result=WorldPopulationGenerator.generate(generated_planet,game_state.registry,population_config)
	game_state.apply_population(population_result)
	print(population_result.summary())
	for player_id: int in game_state.start_diagnostics: print("FFA start P%d: %s" % [player_id,game_state.start_diagnostics[player_id]])
	rules = GameRules.new(game_state)
	print("PlanetGrid version=", grid.grid_generation_version, " subdivision=", subdivision_level,
		" cells=", grid.get_cell_count(), " pentagons=12 fingerprint=", grid.fingerprint)
	selected_material = _material(Color("#ffd166"))
	reachable_material = _material(Color("#578d4d"))
	path_material = _material(Color("#82e1ed"))
	attack_material = _material(Color("#d46bbe"))
	road_material = _material(Color("#d7c26a"))
	connected_material = _material(Color("#63c7a2"))
	depleted_material = _material(Color("#6f4d3d"))
	regrowing_material = _material(Color("#809b58"))
	heal_material=_material(Color("#45d6c4"))
	repair_material=_material(Color("#f1a35b"))
	designation_material=_material(Color("#ff5c67"))
	interaction_material=_material(Color("#46d9d0"))
	hover_material = _material(Color("#81989f"))
	if terrain_config == null: terrain_config = TerrainRenderConfig.new()
	terrain_renderer = PlanetTerrainRenderer.new()
	add_child(terrain_renderer)
	terrain_renderer.rebuild(generated_planet, terrain_config, _occupied_directions())
	terrain_surface = terrain_renderer.surface
	ant_road_overlay=AntRoadOverlay.new(); ant_road_overlay.name="AntRoadOverlay"; add_child(ant_road_overlay)
	ant_road_overlay.configure(grid,terrain_surface,generation_config.world_seed)
	attack_order_overlay=AttackOrderOverlay.new(); attack_order_overlay.name="AttackOrderOverlay"; add_child(attack_order_overlay)
	attack_order_overlay.configure(grid,terrain_surface)
	fog_overlay=FogOfWarOverlay.new(); add_child(fog_overlay)
	navigation.surface = terrain_surface
	for material: StandardMaterial3D in [selected_material, reachable_material, path_material, attack_material, hover_material,
			road_material,connected_material,depleted_material,regrowing_material,heal_material,repair_material,designation_material,interaction_material]:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.38
	world_debug_view = PlanetWorldDebugView.new()
	world_debug_view.name = "WorldDebugView"
	world_debug_view.terrain_surface = terrain_surface
	world_debug_view.set_world(generated_planet)
	add_child(world_debug_view)
	debug_outlines = _debug_layer(null, Color("#253940"))
	debug_centers = _debug_layer(null, Color.WHITE)
	debug_pentagons = _debug_layer(null, Color("#ff9b55"))
	debug_outlines.visible = false
	debug_centers.visible = false
	debug_pentagons.visible = false
	debug_labels = Node3D.new()
	debug_labels.visible = false
	add_child(debug_labels)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.05
	camera.far = planet_radius * 20.0
	camera.current = true
	add_child(camera)
	if camera_config == null: camera_config = TacticalCameraConfig.new()
	navigation.initialize(camera, terrain_surface, planet_radius, camera_config)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var sky:=Sky.new()
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("#26364a")
	sky_material.sky_horizon_color=Color("#91a0a0")
	sky_material.ground_bottom_color=Color("#26302f")
	sky_material.ground_horizon_color=Color("#73858a")
	sky_material.sun_angle_max=8.0
	sky.sky_material=sky_material
	environment.environment.sky=sky
	environment.environment.background_mode = Environment.BG_SKY
	# Restrained neutral fill and filmic mapping preserve the palette and silhouettes.
	environment.environment.ambient_light_color = Color("#a5b1b0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.62
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment.adjustment_enabled = true
	environment.environment.adjustment_brightness = 0.94
	environment.environment.adjustment_contrast = 1.04
	environment.environment.adjustment_saturation = 0.92
	add_child(environment)
	# A soft warm sun gives terrain normals and dressing silhouettes useful form.
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color=Color("#fff0d2")
	sun.light_energy = 0.96
	sun.shadow_enabled=true
	sun.shadow_opacity=0.50
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Shadow distance follows the tactical view, rather than growing to cover
	# most of a Medium globe and submitting off-screen armies to shadow maps.
	sun.directional_shadow_max_distance=32.0
	sun.rotation_degrees = Vector3(-52, 28, -12)
	add_child(sun)
	var hud := CanvasLayer.new()
	add_child(hud)
	coordinate_label = Label.new()
	coordinate_label.position = Vector2(18, 16)
	coordinate_label.add_theme_font_size_override("font_size", 16)
	coordinate_label.mouse_filter = Control.MOUSE_FILTER_STOP
	coordinate_label.mouse_force_pass_scroll_events = false
	hud.add_child(coordinate_label)
	_create_turn_hud(hud)
	world_debug_panel = PlanetWorldDebugPanel.new()
	world_debug_panel.name = "WorldDebugPanel"
	world_debug_panel.mode_requested.connect(set_world_debug_mode)
	world_debug_panel.seed_requested.connect(regenerate_world)
	world_debug_panel.new_seed_requested.connect(generate_new_planet)
	world_debug_panel.show_world(generated_planet)
	world_debug_panel.show_population(population_result,population_config.preset)
	hud.add_child(world_debug_panel)
	restart_match()
	if network_session!=null:
		network_session.observation_received.connect(_network_observation_updated)
		network_session.attach_authority(game_state,rules)

func _sync_units() -> void:
	for id: int in unit_views.keys():
		if not game_state.units.has(id) and not game_state.structures.has(id):
			remove_child(unit_views[id])
			unit_views[id].queue_free()
			unit_views.erase(id)
			health_fills.erase(id)
	for unit: GameState.Unit in game_state.units.values():
		if not unit_views.has(unit.id):
			var unit_definition:=game_state.registry.unit(unit.definition_id)
			var unit_visual_id: String=unit_definition.visual_id if unit_definition!=null and not unit_definition.visual_id.is_empty() else unit.definition_id
			_create_entity_view(unit.id, unit.owner_id, unit_visual_id, false)
		_update_entity_view(unit.id, unit.cell_id, unit.hp, unit.max_hp)
		unit_views[unit.id].visible=visibility_omniscient or (view_observation!=null and view_observation.can_observe_entity(unit.id))
	for structure: GameState.Structure in game_state.structures.values():
		if not unit_views.has(structure.id):
			var structure_definition:=game_state.registry.structure(structure.definition_id)
			var structure_visual_id: String=structure_definition.visual_id if structure_definition!=null and not structure_definition.visual_id.is_empty() else structure.definition_id
			_create_entity_view(structure.id, structure.owner_id, structure_visual_id, true)
		_update_entity_view(structure.id, structure.cell_id, structure.hp, structure.max_hp)
		unit_views[structure.id].visible=visibility_omniscient or (view_observation!=null and view_observation.can_observe_entity(structure.id))
	_sync_sites()
	_sync_contacts()

func _sync_sites() -> void:
	for id: int in site_views.keys():
		if not game_state.world_sites.has(id):
			site_views[id].queue_free(); site_views.erase(id)
	for site: WorldSiteState in game_state.world_sites.values():
		if not site_views.has(site.id): site_views[site.id]=_create_site_view(site)
		var cell:=grid.get_cell(site.cell_id)
		site_views[site.id].position=terrain_surface.sample_position(cell.up,0.012 if site.definition_id=="village" else SURFACE_OFFSET)
		site_views[site.id].basis=PlanetCell.tangent_basis(cell.up)
		site_views[site.id].visible=visibility_omniscient or (view_observation!=null and view_observation.has_discovered_site(site.id))
		var ruined:=site_views[site.id].get_node_or_null("DestroyedLabel") as Label3D
		if ruined!=null: ruined.visible=bool(site.runtime_state.get("destroyed",false))

func _sync_contacts() -> void:
	var known: Dictionary[int,Dictionary]={}
	if view_observation!=null and not visibility_omniscient:
		known=view_observation.known_contacts
	for id: int in contact_views.keys():
		if not known.has(id): contact_views[id].queue_free(); contact_views.erase(id)
	for id: int in known:
		var contact: Dictionary=known[id]
		if not contact_views.has(id): contact_views[id]=_create_contact_view(id)
		var cell_id:=int(contact.last_known_cell_id)
		if not grid.contains(cell_id): continue
		var cell:=grid.get_cell(cell_id)
		contact_views[id].position=terrain_surface.sample_position(cell.up,SURFACE_OFFSET+0.02)
		contact_views[id].basis=PlanetCell.tangent_basis(cell.up)

func _create_contact_view(id: int) -> Node3D:
	var root:=Node3D.new(); root.name="LastKnownContact_%d" % id; add_child(root)
	var marker:=MeshInstance3D.new(); var ring:=TorusMesh.new(); ring.inner_radius=0.42; ring.outer_radius=0.50
	marker.mesh=ring; marker.scale.y=0.12
	var material:=_material(Color(0.65,0.69,0.72,0.58)); material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override=material; root.add_child(marker)
	var label:=Label3D.new(); label.text="?"; label.position.y=0.34; label.font_size=28; label.pixel_size=0.009
	label.modulate=Color(0.72,0.76,0.78,0.72); label.no_depth_test=false; root.add_child(label)
	return root

func _create_site_view(site: WorldSiteState) -> Node3D:
	var definition:=game_state.registry.world_site(site.definition_id)
	var root:=Node3D.new(); root.name="WorldSite_%d_%s" % [site.id,definition.id]; add_child(root)
	if definition.visual_id=="village":
		var scene:=visual_map.asset_scene("village")
		if scene!=null:
			var model:=scene.instantiate() as Node3D; model.name="VillageModel"; root.add_child(model)
			_fit_village_to_cell(model,grid.get_cell(site.cell_id),definition.visual_scale)
		var ruined:=Label3D.new(); ruined.name="DestroyedLabel"; ruined.text="DESTROYED"; ruined.position.y=0.9
		ruined.font_size=24; ruined.pixel_size=0.008; ruined.modulate=Color("#b9c0be"); ruined.outline_modulate=Color("#1b1d1d")
		ruined.visible=bool(site.runtime_state.get("destroyed",false)); root.add_child(ruined)
		var village_label:=Label3D.new(); village_label.name="PopulationDebugLabel"; village_label.text="village\ncell %d" % site.cell_id
		village_label.position.y=1.25; village_label.font_size=22; village_label.pixel_size=0.008; village_label.no_depth_test=true; village_label.visible=population_debug_visible; root.add_child(village_label)
		return root
	var body:=MeshInstance3D.new()
	var color:=Color("#d4b15f")
	if definition.category=="trade":
		var mesh:=CylinderMesh.new(); mesh.top_radius=0.35; mesh.bottom_radius=0.48; mesh.height=0.65; body.mesh=mesh; color=Color("#52c7c1")
	elif definition.category=="resource":
		var mesh:=PrismMesh.new(); mesh.size=Vector3(0.62,0.68,0.62); body.mesh=mesh
		color=Color("#78c76d") if definition.id=="food_source" else (Color("#f2a75c") if definition.id=="energy_source" else Color("#9db0bb"))
	else:
		var mesh:=BoxMesh.new(); mesh.size=Vector3(0.72,0.82,0.72); body.mesh=mesh; color=Color("#b08bdd")
	body.position.y=0.35; body.material_override=_material(color); root.add_child(body)
	var marker:=MeshInstance3D.new(); var marker_mesh:=TorusMesh.new(); marker_mesh.inner_radius=0.18; marker_mesh.outer_radius=0.25
	marker.mesh=marker_mesh; marker.position.y=1.0; marker.material_override=_material(color.lightened(0.25)); root.add_child(marker)
	var label:=Label3D.new(); label.name="PopulationDebugLabel"; label.text="%s\ncell %d" % [definition.id,site.cell_id]
	label.position.y=1.3; label.font_size=22; label.pixel_size=0.008; label.no_depth_test=true; label.visible=population_debug_visible; root.add_child(label)
	return root

func _fit_village_to_cell(model: Node3D,cell: PlanetCell,scale_multiplier: float=1.0) -> void:
	var bounds:=AABB(); var found:=false
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var instance:=node as MeshInstance3D
		if instance.mesh==null: continue
		var box: AABB=(model.global_transform.affine_inverse()*instance.global_transform)*instance.mesh.get_aabb()
		bounds=box if not found else bounds.merge(box); found=true
	if not found: return
	var frame:=PlanetCell.tangent_basis(cell.up)
	var minimum:=Vector2(INF,INF); var maximum:=Vector2(-INF,-INF)
	for corner: Vector3 in cell.polygon_vertices:
		var relative:=corner-cell.center_world_position
		var point:=Vector2(relative.dot(frame.x),relative.dot(frame.z))
		minimum=minimum.min(point); maximum=maximum.max(point)
	var footprint:=maximum-minimum
	var fit_scale:=minf(footprint.x/maxf(0.001,bounds.size.x),footprint.y/maxf(0.001,bounds.size.z))
	fit_scale*=scale_multiplier
	model.scale=Vector3.ONE*fit_scale
	model.position=Vector3(-bounds.get_center().x*fit_scale,-bounds.position.y*fit_scale,-bounds.get_center().z*fit_scale)
	model.set_meta("tile_footprint",footprint); model.set_meta("authored_bounds",bounds)

func _player_start_cells() -> Array[int]:
	var result: Array[int]=[]
	if game_state==null: return result
	for unit: GameState.Unit in game_state.units.values():
		if game_state.players.has(unit.controller_id) and "headquarters" in game_state.registry.unit(unit.definition_id).tags: result.append(unit.cell_id)
	for structure: GameState.Structure in game_state.structures.values():
		if game_state.players.has(structure.controller_id) and "headquarters" in game_state.registry.structure(structure.definition_id).tags: result.append(structure.cell_id)
	result.sort()
	return result

func _create_entity_view(id: int, owner_id: int, kind: String, is_structure: bool) -> void:
	var view := EntityView.new()
	view.name = "Entity_%d" % id
	add_child(view)
	unit_views[id] = view
	var packed: PackedScene = visual_map.structure_scene(kind) if is_structure else visual_map.unit_scene(kind)
	var wrapper: Node3D = packed.instantiate() as Node3D if packed != null else Node3D.new()
	wrapper.name = "visual_root"
	view.add_child(wrapper)
	var model_root: Node3D = wrapper.get_node_or_null("ModelRoot") as Node3D
	if model_root == null:
		model_root = Node3D.new()
		model_root.name = "ModelRoot"
		wrapper.add_child(model_root)
	# Preserve authored wrapper children, skeletons and animation tracks.
	if model_root.get_child_count() == 0:
		var asset: PackedScene = visual_map.asset_scene(kind)
		if asset != null:
			model_root.add_child(asset.instantiate())
	var model_profile:=visual_map.model_definition(kind)
	if model_profile!=null:
		model_root.scale=model_profile.model_scale
		model_root.rotation_degrees=model_profile.rotation_offset_degrees
		model_root.position.y=model_profile.height_offset
		TacticalModelMaterials.apply(model_root)
	if model_root.get_child_count() == 0:
		var placeholder := MeshInstance3D.new()
		var size:=Vector3(1.1,0.7,1.1) if is_structure or kind=="living_spider" else Vector3(0.6,0.65,0.6)
		if kind in ["mite","mosquito"]: size=Vector3(0.34,0.32,0.34)
		elif "ant" in kind: size=Vector3(0.72,0.32,0.38)
		elif kind in ["poison_dart_frog","bullfrog","unke"]: size=Vector3(0.72,0.42,0.62)
		elif kind=="pillar_city": size=Vector3(1.0,1.35,1.0)
		elif kind in ["assault_tank","long_range_tank","anti_air_tank"]: size=Vector3(0.9,0.42,0.68)
		elif kind in ["scout_trike","trike_commander"]: size=Vector3(0.72,0.38,0.52)
		elif kind in ["bridgewright","conqueror_squad","medic_squad"]: size=Vector3(0.52,0.72,0.52)
		var box := BoxMesh.new(); box.size=size
		placeholder.mesh = box
		placeholder.position.y = size.y / 2.0
		placeholder.material_override = _material(_owner_color(owner_id))
		model_root.add_child(placeholder)
	_apply_team_accent(model_root, owner_id)
	view.terrain_surface = terrain_surface
	view.configure(wrapper)
	if not is_structure:
		var definition:=game_state.registry.unit(kind)
		view.configure_squad(wrapper,definition.squad_size if definition!=null else 1,
			model_profile.squad_member_scale if model_profile!=null else 1.0,
			model_profile.squad_spacing if model_profile!=null else 1.0,
			model_profile.squad_formation if model_profile!=null else "default")
	var entity_definition:=game_state.registry.unit(kind) if not is_structure else null
	view.prepare_ground_contact(wrapper,entity_definition!=null and "flying" in entity_definition.tags)
	# Ownership remains readable even on textured assets without an accent slot.
	var team_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.rings=24; ring_mesh.ring_segments=6
	ring_mesh.inner_radius = 0.655
	ring_mesh.outer_radius = 0.69
	team_ring.mesh = ring_mesh
	team_ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_ring.scale.y = 0.15
	team_ring.position.y = 0.025
	team_ring.material_override = _material(_owner_color(owner_id).darkened(0.16))
	wrapper.add_child(team_ring)
	var background := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.94, 0.03, 0.13)
	background.mesh = bar
	background.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	background.position = Vector3(0, 0.09, 0.63)
	background.material_override = _material(Color("#101820"))
	view.add_child(background)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.88, 0.03, 0.08)
	fill.mesh = fill_mesh
	fill.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.position = Vector3(0, 0.12, 0.63)
	fill.material_override = _material(Color("#88bb77"))
	view.add_child(fill)
	health_fills[id] = fill
	view.movement_finished.connect(_refresh_display)
	view.prepare_render_culling()

func _update_entity_view(id: int, cell_id: int, hp: int, max_hp: int) -> void:
	# Ground-origin wrapper; logical coordinates never depend on model transforms.
	var view: EntityView=unit_views[id]
	view.sync_position(terrain_surface.ground_position(grid.get_cell(cell_id).up,SURFACE_OFFSET) if view.grounded else terrain_surface.sample_position(grid.get_cell(cell_id).up,0.28))
	var fraction: float = float(hp) / max_hp
	health_fills[id].scale.x = fraction
	health_fills[id].position.x = -0.44 * (1.0 - fraction)
	if game_state.units.has(id): unit_views[id].sync_squad_health(hp,max_hp)

func _water_cell_ids() -> Array[int]:
	var result: Array[int]=[]
	if generated_planet==null: return result
	for data: PlanetWorldCellData in generated_planet.cell_world_data:
		if data.hydrology!=null and data.hydrology.surface_water_type!=HydrologyCellData.SurfaceWater.NONE: result.append(data.cell_id)
	return result

func _create_turn_hud(hud: CanvasLayer) -> void:
	top_bar=PanelContainer.new(); top_bar.name="TopBar"; top_bar.mouse_filter=Control.MOUSE_FILTER_STOP; top_bar.z_index=52; hud.add_child(top_bar)
	MythicFrame.apply(top_bar,true)
	var top_margin:=MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: top_margin.add_theme_constant_override("margin_"+side,8)
	top_bar.add_child(top_margin)
	var top_row:=HBoxContainer.new(); top_row.add_theme_constant_override("separation",12); top_margin.add_child(top_row)
	turn_label=_hud_label(top_row); turn_label.add_theme_font_size_override("font_size",20)
	network_indicator=_hud_label(top_row); network_indicator.visible=network_session!=null
	if network_session!=null:
		network_indicator.text="Host P%d | %s" % [network_session.local_player_id,network_session.status_message]
		network_session.status_changed.connect(_network_status_changed)
	resource_bar=HBoxContainer.new(); resource_bar.name="ResourceBar"; resource_bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; resource_bar.add_theme_constant_override("separation",8); top_row.add_child(resource_bar)
	var research_button:=Button.new(); research_button.name="ResearchButton"; research_button.text="📖 Research  [R]"; research_button.tooltip_text="Toggle Research Overlay"; research_button.focus_mode=Control.FOCUS_NONE; research_button.pressed.connect(_toggle_research); top_row.add_child(research_button)
	end_turn_button=Button.new(); end_turn_button.name="EndTurnButton"; end_turn_button.custom_minimum_size.x=150; end_turn_button.focus_mode=Control.FOCUS_NONE; end_turn_button.pressed.connect(request_end_turn); top_row.add_child(end_turn_button)

	hud_panel = PanelContainer.new()
	hud_panel.name="SelectionPanel"
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_panel.mouse_force_pass_scroll_events = false
	hud_panel.z_index=4
	var selection_style:=StyleBoxFlat.new()
	selection_style.bg_color=Color(0.035,0.065,0.07,0.96)
	selection_style.border_color=Color(0.24,0.46,0.49,0.85)
	selection_style.set_border_width_all(1)
	selection_style.corner_radius_top_left=5; selection_style.corner_radius_top_right=5
	selection_style.corner_radius_bottom_left=5; selection_style.corner_radius_bottom_right=5
	selection_style.shadow_color=Color(0,0,0,0.45); selection_style.shadow_size=5
	hud_panel.add_theme_stylebox_override("panel",selection_style)
	MythicFrame.apply(hud_panel,true)
	hud.add_child(hud_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	materials_label = _hud_label(column)
	materials_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	materials_label.visible=false
	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(restart_match)
	restart_button.visible=network_session==null
	column.add_child(restart_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var details := VBoxContainer.new()
	_selection_content=details
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 10)
	scroll.add_child(details)
	unit_info_panel=UnitInfoPanel.new(); details.add_child(unit_info_panel)
	model_preview=unit_info_panel.preview
	players_label=_hud_label(details)
	players_label.name="MultiplayerPlayers"
	players_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var legend: Label = _hud_label(details); selection_legend=legend
	var names:=PackedStringArray()
	for player_id: int in game_state.players:
		names.append("%s: P%d" % [game_state.registry.faction(game_state.players[player_id].faction_id).display_name,player_id])
	legend.text = " | ".join(names)+"\nGreen: move | Cyan: path\nPurple: attack | Gold: selection"
	unit_label=unit_info_panel.details_label
	unit_label.custom_minimum_size.x=0
	attack_preview_label = _hud_label(details)
	attack_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attack_preview_label.visible=false
	feedback_label = _hud_label(details)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.visible=false

	action_panel=PanelContainer.new(); action_panel.name="ActionBar"; action_panel.mouse_filter=Control.MOUSE_FILTER_STOP; hud.add_child(action_panel)
	MythicFrame.apply(action_panel,true)
	var action_margin:=MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: action_margin.add_theme_constant_override("margin_"+side,8)
	action_panel.add_child(action_margin)
	var action_scroll:=ScrollContainer.new(); action_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; action_margin.add_child(action_scroll)
	recruit_box=VBoxContainer.new(); recruit_box.name="ContextActions"; recruit_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; recruit_box.add_theme_constant_override("separation",5); action_scroll.add_child(recruit_box)

	research_backdrop=PanelContainer.new(); research_backdrop.name="ResearchBackdrop"; research_backdrop.visible=false
	research_backdrop.mouse_filter=Control.MOUSE_FILTER_STOP; research_backdrop.z_index=50
	var research_backdrop_style:=StyleBoxFlat.new(); research_backdrop_style.bg_color=Color(0.01,0.018,0.024,0.96)
	research_backdrop.add_theme_stylebox_override("panel",research_backdrop_style); hud.add_child(research_backdrop)
	strategic_panel=StrategicResearchPanel.new(); strategic_panel.name="StrategicPanel"; strategic_panel.visible=false; strategic_panel.z_index=51
	strategic_panel.research_requested.connect(_start_research_ui); strategic_panel.close_requested.connect(_close_strategic_panel); hud.add_child(strategic_panel)
	notification_feed=StrategicNotificationFeed.new(); notification_feed.name="Notifications"; notification_feed.focus_requested.connect(_focus_notification); hud.add_child(notification_feed)
	privacy_overlay=PanelContainer.new(); privacy_overlay.name="HotseatPrivacy"; privacy_overlay.visible=false
	privacy_overlay.mouse_filter=Control.MOUSE_FILTER_STOP; privacy_overlay.z_index=100; hud.add_child(privacy_overlay)
	var privacy_style:=StyleBoxFlat.new(); privacy_style.bg_color=Color("#0b1115"); privacy_overlay.add_theme_stylebox_override("panel",privacy_style)
	var privacy_center:=CenterContainer.new(); privacy_center.name="PrivacyCenter"; privacy_overlay.add_child(privacy_center)
	var privacy_column:=VBoxContainer.new(); privacy_column.name="PrivacyColumn"; privacy_column.custom_minimum_size=Vector2(360,150); privacy_column.add_theme_constant_override("separation",18); privacy_center.add_child(privacy_column)
	privacy_label=Label.new(); privacy_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; privacy_label.add_theme_font_size_override("font_size",28); privacy_column.add_child(privacy_label)
	var ready:=Button.new(); ready.name="ReadyButton"; ready.text="Reveal my view"; ready.custom_minimum_size.y=52; ready.pressed.connect(_dismiss_privacy); privacy_column.add_child(ready)
	management_panel=VBoxContainer.new(); management_panel.name="ManagementWorkflow"; management_panel.add_theme_constant_override("separation",6); hud.add_child(management_panel)
	next_unit_button=Button.new(); next_unit_button.name="NextUnitButton"; next_unit_button.text="Next Unit"; next_unit_button.pressed.connect(_next_manageable_unit); management_panel.add_child(next_unit_button)
	manage_cities_button=Button.new(); manage_cities_button.name="ManageCitiesButton"; manage_cities_button.text="Manage Cities"; manage_cities_button.pressed.connect(_next_manageable_city); management_panel.add_child(manage_cities_button)
	select_research_button=Button.new(); select_research_button.name="SelectResearchButton"; select_research_button.text="Select Research"; select_research_button.pressed.connect(_toggle_research); management_panel.add_child(select_research_button)
	minimap=StrategicMinimap.new(); minimap.name="Minimap"; minimap.cell_focused.connect(focus_cell.bind(true)); management_panel.add_child(minimap)
	_layout_hud()
	details.minimum_size_changed.connect(_schedule_selection_layout)
	get_viewport().size_changed.connect(_layout_hud)

func _schedule_selection_layout() -> void:
	if _selection_layout_pending: return
	_selection_layout_pending=true
	_apply_selection_layout.call_deferred()

func _apply_selection_layout() -> void:
	_selection_layout_pending=false
	if is_inside_tree(): _layout_hud()

func _hud_label(parent: Control) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _network_status_changed(_status: int,message: String) -> void:
	if network_indicator!=null: network_indicator.text="Host P%d | %s" % [network_session.local_player_id,message]

func _network_observation_updated(_snapshot: Dictionary) -> void:
	if is_node_ready(): _refresh_display()

func _network_result(data: Dictionary) -> GameRules.Result:
	var result:=GameRules.Result.new(bool(data.get("accepted",false)),String(data.get("public_reason","")),data.get("path",[]))
	var outcome: Dictionary=data.get("outcome",{})
	result.damage=int(outcome.get("damage",0)); result.target_hp=int(outcome.get("target_hp",0))
	result.killed=bool(outcome.get("killed",false)); result.winner_id=int(outcome.get("winner_id",0))
	return result

func _network_command(type: String,parameters: Dictionary) -> GameRules.Result:
	return _network_result(network_session.submit_host_command(type,parameters))

func _network_authoritative_command(actor: int,type: String,parameters: Dictionary) -> GameRules.Result:
	return _network_result(network_session.submit_authoritative_command(actor,type,parameters))

func _new_match(mode: String) -> void:
	match_mode = mode
	player_controllers = {1: "Human", 2: "Human" if mode == "Hotseat" else "AI"}
	if match_config != null:
		match_config.opponent_controller = player_controllers[2]
	if game_state!=null:
		game_state.setup["controller_kinds"]=[ControllerState.HUMAN,
			ControllerState.HUMAN if mode=="Hotseat" else ControllerState.PLAYER_AI]
	restart_match()

func _layout_hud() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale:=clampf(ui_scale,0.8,1.4)
	var margin:=12.0*scale
	var right_width:=340.0*scale
	var top_height:=58.0*scale
	top_bar.position=Vector2(margin,margin); top_bar.size=Vector2(maxf(420.0,viewport_size.x-margin*2.0),top_height)
	var available_height:=maxf(144.0,viewport_size.y-top_height-margin*3.0)
	var content_height:=_selection_content.get_combined_minimum_size().y+22.0
	if restart_button.visible: content_height+=restart_button.get_combined_minimum_size().y+8.0
	var selection_height:=clampf(content_height,144.0*scale,available_height)
	hud_panel.position=Vector2(margin,viewport_size.y-selection_height-margin)
	hud_panel.size=Vector2(right_width,selection_height)
	var action_width:=minf(620.0*scale,maxf(300.0,viewport_size.x-right_width-margin*4.0))
	action_panel.position=Vector2((viewport_size.x-right_width-action_width)/2.0,viewport_size.y-220.0*scale-margin)
	action_panel.size=Vector2(action_width,208.0*scale)
	if research_backdrop!=null: research_backdrop.position=Vector2.ZERO; research_backdrop.size=viewport_size
	var research_width:=minf(1150.0*scale,viewport_size.x-margin*2.0)
	var research_top:=top_height+margin*2.0
	var research_height:=maxf(360.0,minf(760.0*scale,viewport_size.y-research_top-margin))
	strategic_panel.position=Vector2((viewport_size.x-research_width)*0.5,research_top)
	strategic_panel.size=Vector2(research_width,research_height)
	var feed_height:=minf(178.0*scale,28.0*scale+34.0*scale*maxi(1,notification_feed.records.size()))
	notification_feed.position=Vector2(margin+right_width+margin,top_height+margin*2.0); notification_feed.size=Vector2(minf(430.0*scale,viewport_size.x-right_width-margin*3.0),feed_height)
	if management_panel!=null:
		management_panel.position=Vector2(viewport_size.x-270.0*scale-margin,viewport_size.y-250.0*scale-margin)
		management_panel.size=Vector2(270.0*scale,250.0*scale)
	coordinate_label.position=Vector2(margin+6.0,notification_feed.position.y+notification_feed.size.y+8.0)
	if privacy_overlay!=null: privacy_overlay.position=Vector2.ZERO; privacy_overlay.size=viewport_size

func _dismiss_privacy() -> void:
	privacy_overlay.visible=false
	_feedback("Player %d view revealed." % game_state.active_player)

func _clear_recruit_box() -> void:
	if unit_info_panel!=null: unit_info_panel.clear_actions()
	while recruit_box.get_child_count() > 0:
		var child := recruit_box.get_child(0)
		recruit_box.remove_child(child)
		child.queue_free()

func has_active_input_mode() -> bool:
	return input_mode!=StrategicInputMode.Kind.NORMAL

func _set_input_mode(mode: int,source_id: int=-1,message: String="") -> void:
	input_mode=mode; mode_source_id=source_id; mode_path.clear()
	hover_cell=NONE
	placement_mode=mode==StrategicInputMode.Kind.RECRUIT
	if not message.is_empty(): _feedback(message)
	_refresh_tile_materials()

func cancel_input_mode(show_feedback: bool=true) -> void:
	var previous:=input_mode
	input_mode=StrategicInputMode.Kind.NORMAL; mode_source_id=-1; mode_path.clear()
	placement_mode=false; recruit_choice=""; recruit_hq_id=-1; recruit_highlights.clear()
	if show_feedback and previous!=StrategicInputMode.Kind.NORMAL:
		_feedback(StrategicInputMode.display_name(previous)+" mode cancelled.")
	if not tiles.is_empty() and reachable_material!=null: _refresh_tile_materials()

func _toggle_research() -> void:
	if game_state.turn_state.neutral_phase: return
	strategic_panel.visible=not strategic_panel.visible
	research_backdrop.visible=strategic_panel.visible
	action_panel.visible=not strategic_panel.visible
	notification_feed.visible=not strategic_panel.visible and not notification_feed.records.is_empty()
	coordinate_label.visible=not strategic_panel.visible
	if strategic_panel.visible:
		end_turn_button.disabled=true
		strategic_panel.configure(rules,_view_controller_id())
	else: _refresh_display()

func _close_strategic_panel() -> void:
	strategic_panel.visible=false; research_backdrop.visible=false; action_panel.visible=true; notification_feed.visible=not notification_feed.records.is_empty(); coordinate_label.visible=true
	_refresh_display()

func _focus_action_bar() -> void:
	if selected_unit_id!=-1 and unit_info_panel.visible:
		for group: String in [UnitInfoPanel.GROUP_CITY,UnitInfoPanel.GROUP_SPECIAL,UnitInfoPanel.GROUP_ATTACKS,UnitInfoPanel.GROUP_STANCES]:
			for child: Node in unit_info_panel.action_flows[group].get_children():
				if child is Button and not child.disabled:
					child.focus_mode=Control.FOCUS_ALL; child.grab_focus(); return
	if recruit_box.get_child_count()>0:
		var first:=recruit_box.get_child(0)
		if first is Control: (first as Control).grab_focus()
	else: _feedback("Select a unit, structure, district, or site to see context actions.")

func _cycle_controllable(direction: int) -> void:
	var ids: Array[int]=[]
	var view_controller:=_view_controller_id()
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==view_controller: ids.append(unit.id)
	ids.sort()
	if ids.is_empty(): return
	var index:=ids.find(selected_unit_id)
	index=0 if index<0 else posmod(index+direction,ids.size())
	var unit: GameState.Unit=game_state.units[ids[index]]
	selected=unit.cell_id; selected_unit_id=unit.id; selected_structure_id=-1; selected_site_id=-1; selected_district_id=-1
	_focus_selected(); _refresh_display()

func _reset_management_queues_if_needed() -> void:
	if game_state.turn_state.phase!=TurnState.MANAGEMENT: return
	if management_turn_serial==game_state.turn_state.serial: return
	management_turn_serial=game_state.turn_state.serial; reviewed_units.clear(); reviewed_cities.clear()

func _manageable_unit_ids(controller_id: int) -> Array[int]:
	var ids: Array[int]=[]
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==controller_id and unit.hp>0 and not unit.moved and not unit.attacked and not reviewed_units.has(unit.id): ids.append(unit.id)
	ids.sort(); return ids

func _manageable_city_ids(controller_id: int) -> Array[int]:
	var ids: Array[int]=[]
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==controller_id and unit.spider_state!=null and not reviewed_cities.has(unit.id): ids.append(unit.id)
	for structure: GameState.Structure in game_state.structures.values():
		if structure.controller_id==controller_id and structure.pillar_state!=null and not reviewed_cities.has(structure.id): ids.append(structure.id)
	ids.sort(); return ids

func _next_manageable_unit() -> void:
	var controller:=_view_controller_id()
	if selected_unit_id>=0: reviewed_units[selected_unit_id]=true
	var ids:=_manageable_unit_ids(controller)
	if ids.is_empty(): _refresh_display(); return
	var unit: GameState.Unit=game_state.units[ids[0]]; selected=unit.cell_id; selected_unit_id=unit.id; selected_structure_id=-1
	_focus_selected(); _refresh_display()

func _next_manageable_city() -> void:
	var controller:=_view_controller_id(); var current:=selected_unit_id if selected_unit_id>=0 and game_state.units.has(selected_unit_id) and game_state.units[selected_unit_id].spider_state!=null else selected_structure_id
	if current>=0: reviewed_cities[current]=true
	var ids:=_manageable_city_ids(controller)
	if ids.is_empty(): _refresh_display(); return
	var id:=ids[0]
	if game_state.units.has(id): selected_unit_id=id; selected_structure_id=-1; selected=game_state.units[id].cell_id
	else: selected_structure_id=id; selected_unit_id=-1; selected=game_state.structures[id].cell_id
	_focus_selected(); _refresh_display()

func _refresh_management_workflow(controller_id: int,can_act: bool) -> void:
	if not game_state.turn_state.simultaneous_combat_enabled:
		next_unit_button.visible=false; manage_cities_button.visible=false; select_research_button.visible=false
		end_turn_button.visible=true; return
	_reset_management_queues_if_needed()
	var management:=game_state.turn_state.phase==TurnState.MANAGEMENT and can_act
	var units: Array[int]=[]; var cities: Array[int]=[]
	if management: units=_manageable_unit_ids(controller_id); cities=_manageable_city_ids(controller_id)
	next_unit_button.visible=management and not units.is_empty()
	manage_cities_button.visible=management and not cities.is_empty()
	var queues_done:=units.is_empty() and cities.is_empty()
	var player: PlayerState=game_state.players.get(controller_id)
	var needs_research:=player!=null and player.research.current_technology_id.is_empty() and not rules.available_technologies(controller_id).is_empty()
	select_research_button.visible=management and queues_done and needs_research
	end_turn_button.visible=management and queues_done and not needs_research
	if management:
		end_turn_button.text="End Movement Phase"; end_turn_button.tooltip_text="Finish this player's movement and management phase."

func _focus_notification(cell_id: int,entity_id: int) -> void:
	if entity_id>=0:
		if game_state.units.has(entity_id): cell_id=game_state.units[entity_id].cell_id
		elif game_state.structures.has(entity_id): cell_id=game_state.structures[entity_id].cell_id
	if cell_id>=0: focus_cell(cell_id)

func _handle_mode_click(screen_position: Vector2) -> void:
	if input_mode==StrategicInputMode.Kind.RECRUIT: handle_recruit_click(screen_position); return
	var cell_id:=pick_selectable_cell(screen_position)
	if input_mode==StrategicInputMode.Kind.MOVE:
		var result:=_network_command(CommandDispatcher.MOVE,{"unit_id":mode_source_id,"destination":cell_id}) if network_session!=null else rules.try_move(_action_actor(),mode_source_id,cell_id)
		if result.success:
			selected=game_state.units[mode_source_id].cell_id; _present_move(mode_source_id,result); cancel_input_mode(false)
		_apply_ui_result(result,cell_id,mode_source_id); return
	if input_mode==StrategicInputMode.Kind.ATTACK:
		var result:=GameRules.Result.new(false,"Choose a highlighted hostile target.")
		var combat_actor:=_action_actor()
		var target:=_legal_attack_target_at_cell(combat_actor,mode_source_id,cell_id)
		if target!=null:
			if game_state.turn_state.simultaneous_combat_enabled: result=_network_command(CommandDispatcher.COMBAT_INTENT,{"unit_id":mode_source_id,"option_id":"attack","target_id":target.id}) if network_session!=null else rules.submit_combat_intent(combat_actor,mode_source_id,"attack",target.id)
			else: result=rules.try_attack(combat_actor,mode_source_id,target.id)
		if result.success: cancel_input_mode(false)
		_apply_ui_result(result,cell_id,target.id if target!=null else -1); return
	if input_mode==StrategicInputMode.Kind.ROAD:
		_handle_road_cell(cell_id); return
	if input_mode in [StrategicInputMode.Kind.PILLAR,StrategicInputMode.Kind.BRIDGE]:
		var source: GameState.Structure=game_state.structures.get(selected_structure_id) as GameState.Structure
		var engineer:=_available_engineer(_action_actor(),source.cell_id) if source!=null else null
		var result:=GameRules.Result.new(false,"Select a valid highlighted Pillar destination.")
		if source!=null and engineer!=null:
			result=_network_command(CommandDispatcher.START_BRIDGE_EXTENSION,{"engineer_id":engineer.id,"pillar_id":source.id,"cell_id":cell_id}) if network_session!=null else rules.start_bridge_extension(_action_actor(),engineer.id,source.id,cell_id)
		if result.success: cancel_input_mode(false)
		_apply_ui_result(result,cell_id); return
	if input_mode in [StrategicInputMode.Kind.HEAL,StrategicInputMode.Kind.REPAIR,StrategicInputMode.Kind.DESIGNATE]:
		var target:=game_state.entity_at(cell_id)
		var result:=GameRules.Result.new(false,"Select a valid highlighted target.")
		if target!=null:
			match input_mode:
				StrategicInputMode.Kind.HEAL: result=_network_command(CommandDispatcher.HEAL_UNIT,{"healer_id":mode_source_id,"target_id":target.id}) if network_session!=null else rules.heal_unit(_action_actor(),mode_source_id,target.id)
				StrategicInputMode.Kind.REPAIR:
					if game_state.units.has(target.id): result=_network_command(CommandDispatcher.REPAIR_UNIT,{"engineer_id":mode_source_id,"target_id":target.id}) if network_session!=null else rules.repair_unit(_action_actor(),mode_source_id,target.id)
					elif game_state.structures.has(target.id): result=_network_command(CommandDispatcher.REPAIR_STRUCTURE,{"engineer_id":mode_source_id,"structure_id":target.id}) if network_session!=null else rules.repair_structure(_action_actor(),mode_source_id,target.id)
				StrategicInputMode.Kind.DESIGNATE: result=_network_command(CommandDispatcher.DESIGNATE_TARGET,{"commander_id":mode_source_id,"target_id":target.id}) if network_session!=null else rules.designate_target(_action_actor(),mode_source_id,target.id)
		if result.success: cancel_input_mode(false)
		_apply_ui_result(result,cell_id)

func _handle_road_cell(cell_id: int) -> void:
	if not road_highlights.has(cell_id): _feedback("Choose a highlighted adjacent road cell."); return
	mode_path.append(cell_id)
	var result:=_network_command(CommandDispatcher.BUILD_ROAD,{"worker_id":mode_source_id,"path":[cell_id]}) if network_session!=null else rules.try_build_road(_action_actor(),mode_source_id,[cell_id])
	if result.success:
		var worker: GameState.Unit=game_state.units.get(mode_source_id) as GameState.Unit
		if worker==null or worker.road_segments_built_this_turn>=rules.living_migration_rules.config_for(_action_actor()).road_segments_per_turn:
			cancel_input_mode(false)
	_apply_ui_result(result,cell_id)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _process(delta: float) -> void:
	if feedback_seconds > 0.0:
		feedback_seconds -= delta
		if feedback_seconds <= 0.0:
			feedback_label.text = ""
			feedback_label.visible=false
	if strategic_panel!=null and strategic_panel.visible:
		return
	var horizontal: float = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var vertical: float = float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var rotate := float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if rotate != 0:
		navigation.manual_navigation()
		navigation.target_yaw += rotate * camera_config.keyboard_yaw_speed * delta
	var followed := Vector3.ZERO
	if navigation.focused_entity != -1:
		if unit_views.has(navigation.focused_entity):
			followed = unit_views[navigation.focused_entity].position
		else:
			navigation.focused_entity = -1
	navigation.update(delta, Vector2(horizontal, vertical), followed)
	_update_entity_rendering()
	if terrain_renderer!=null and terrain_renderer.dressing!=null:
		terrain_renderer.dressing.set_zoom_band(navigation.zoom_band())
	if camera_diagnostics: _update_label()
	_update_preview()

func _update_entity_rendering() -> void:
	# The solid planet occludes far-side objects even when the camera frustum
	# contains them. A conservative sphere test avoids submitting their meshes
	# and shadows, while preserving fog, selection and logical entity state.
	var camera_position:=camera.global_position
	var camera_distance:=camera_position.length()
	if camera_distance<=planet_radius: return
	var occlusion_radius:=maxf(0.1,planet_radius+terrain_config.mapped_height(0.0)-0.1)
	var horizon:=acos(clampf(occlusion_radius/camera_distance,0.0,1.0))
	var camera_direction:=camera_position/camera_distance
	for view: EntityView in unit_views.values():
		var extent:=view.position.length()+view.render_radius
		var object_horizon:=acos(clampf(occlusion_radius/maxf(occlusion_radius,extent),0.0,1.0))
		var in_front:=camera_direction.dot(view.position.normalized())>=cos(horizon+object_horizon+0.02)
		view.set_render_active(view.visible and in_front)

func _unhandled_input(event: InputEvent) -> void:
	if strategic_panel!=null and strategic_panel.visible:
		if event is InputEventKey:
			var modal_key:=event as InputEventKey
			if modal_key.pressed and not modal_key.echo and modal_key.physical_keycode in [KEY_ESCAPE,KEY_R]:
				_close_strategic_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_left_pending = true
					_left_dragging = false
					_left_start = button.position
					_grab_direction = terrain_surface.ray_hit(camera.project_ray_origin(button.position), camera.project_ray_normal(button.position)).normalized()
				else:
					if _left_pending and not _left_dragging:
						if input_mode!=StrategicInputMode.Kind.NORMAL: _handle_mode_click(button.position)
						else: select_at(button.position)
					_left_pending = false
					_left_dragging = false
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					if input_mode==StrategicInputMode.Kind.ATTACK: _handle_mode_click(button.position)
					elif input_mode!=StrategicInputMode.Kind.NORMAL: cancel_input_mode()
					else: request_action_at(button.position)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					navigation.zoom(-1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			MOUSE_BUTTON_MIDDLE:
				_is_middle_dragging = button.pressed
				_last_mouse_pos = button.position
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_pending and not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_left_pending = false
			_left_dragging = false
		if _left_pending:
			if motion.position.distance_to(_left_start) > camera_config.drag_threshold:
				_left_dragging = true
				navigation.manual_navigation()
			if _left_dragging and _grab_direction != Vector3.ZERO:
				navigation.grab(_grab_direction, motion.position)
		if _is_middle_dragging and not (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			_is_middle_dragging = false
		if _is_middle_dragging:
			navigation.orbit(motion.position - _last_mouse_pos)
			_last_mouse_pos = motion.position
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			if has_active_input_mode(): cancel_input_mode()
			else: clear_selection()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.physical_keycode==KEY_R:
			_toggle_research(); get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.physical_keycode==KEY_P:
			_focus_action_bar(); get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.physical_keycode==KEY_TAB:
			_cycle_controllable(-1 if key.shift_pressed else 1); get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and (key.physical_keycode==KEY_ENTER or key.physical_keycode==KEY_KP_ENTER):
			request_end_turn(); get_viewport().set_input_as_handled()
		elif key.pressed and key.physical_keycode == KEY_F:
			_focus_selected()
		elif key.pressed and key.physical_keycode == KEY_F1:
			_toggle_debug_geometry(debug_outlines)
		elif key.pressed and key.physical_keycode == KEY_F2:
			_toggle_debug_geometry(debug_pentagons,false,true)
		elif key.pressed and key.physical_keycode == KEY_F3:
			_toggle_debug_geometry(debug_centers,true)
		elif key.pressed and key.physical_keycode == KEY_F4:
			_toggle_debug_labels()
		elif key.pressed and key.physical_keycode == KEY_F6:
			if network_session==null:
				world_debug_panel.visible = not world_debug_panel.visible
				world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)
		elif key.pressed and key.physical_keycode == KEY_F7:
			set_world_debug_mode((world_debug_view.mode + 1) % PlanetWorldDebugView.MODE_NAMES.size())
		elif key.pressed and key.physical_keycode == KEY_F8:
			camera_diagnostics = not camera_diagnostics
			_update_label()
		elif key.pressed and key.physical_keycode == KEY_F9:
			population_debug_visible=not population_debug_visible
			for view: Node3D in site_views.values():
				var label:=view.get_node_or_null("PopulationDebugLabel")
				if label!=null: label.visible=population_debug_visible
			_update_label()
		elif key.pressed and key.physical_keycode == KEY_F10:
			visibility_omniscient=not visibility_omniscient
			_update_visibility_presentation(true)
			_refresh_display()
		elif key.pressed and key.physical_keycode == KEY_HOME:
			_reset_camera()

func pick_cell(screen_position: Vector2) -> int:
	return pick_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func pick_ray(origin: Vector3, direction: Vector3) -> int:
	var hit: Vector3 = terrain_surface.ray_hit(origin, direction)
	return grid.find_cell(hit.normalized()) if hit != Vector3.ZERO else NONE

func select_at(screen_position: Vector2) -> void:
	selected = pick_selectable_cell(screen_position)
	selected_site_id=-1; selected_district_id=-1; selected_contact_id=-1
	var observed_entity:=_observed_entity_at_cell(selected)
	var unit: GameState.Unit=observed_entity as GameState.Unit
	if unit != null:
		selected_unit_id = unit.id
		selected_structure_id = -1
	else:
		var s: GameState.Structure=observed_entity as GameState.Structure
		if s != null:
			selected_structure_id = s.id
			selected_unit_id = -1
		else:
			selected_unit_id = -1
			selected_structure_id = -1
			var district:=game_state.baumeister.district_at(selected) if _can_view_cell(selected) else null
			if district!=null and _can_view_cell(district.cell_id): selected_district_id=district.id
			else:
				var site:=_observed_site_at_cell(selected)
				if site!=null and game_state.registry.world_site(site.definition_id).selectable: selected_site_id=site.id
				elif view_observation!=null:
					var contact:=view_observation.contact_at(selected)
					if not contact.is_empty(): selected_contact_id=int(contact.contact_id)
	if selected_unit_id != -1 or selected_structure_id != -1:
		_focus_selected()
	else:
		navigation.manual_navigation()
	_refresh_display()

func clear_selection() -> void:
	navigation.manual_navigation()
	selected = NONE
	selected_unit_id = -1
	selected_structure_id = -1
	selected_site_id=-1; selected_district_id=-1; selected_contact_id=-1
	cancel_input_mode(false)
	_refresh_display()

func request_action_at(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if game_state.winner_id != 0:
		return
	# If placement mode is active, right click cancels and left handled elsewhere
	if placement_mode:
		return
	var target_cell:=pick_selectable_cell(screen_position)
	var actor:=_view_controller_id()
	var selected_unit: GameState.Unit=game_state.units.get(selected_unit_id) as GameState.Unit
	var target:=_legal_attack_target_at_cell(actor,selected_unit_id,target_cell) if selected_unit!=null and selected_unit.controller_id==actor else null
	if target==null and selected_unit!=null and selected_unit.controller_id==actor:
		var observed_target:=_observed_entity_at_cell(target_cell)
		if observed_target==null: observed_target=_observed_site_at_cell(target_cell)
		if _can_attempt_attack(actor,observed_target): target=observed_target
	if target!=null:
		var target_id: int=target.id
		var result: GameRules.Result
		if game_state.turn_state.simultaneous_combat_enabled:
			var parameters:={"unit_id":selected_unit_id,"option_id":"attack","target_id":target_id}
			result=_network_command(CommandDispatcher.COMBAT_INTENT,parameters) if network_session!=null else rules.submit_combat_intent(actor,selected_unit_id,"attack",target_id)
		else:
			result=_network_command(CommandDispatcher.ATTACK,{"attacker_id":selected_unit_id,"target_id":target_id}) if network_session!=null else rules.try_attack(actor,selected_unit_id,target_id)
		_refresh_display()
		_feedback(result.reason)
	else:
		request_move_at(screen_position)

func _legal_attack_target_at_cell(actor: int,attacker_id: int,cell_id: int) -> RefCounted:
	if cell_id==NONE or not game_state.units.has(attacker_id): return null
	for target_id: int in rules.attack_targets(actor,attacker_id):
		var target:=game_state.combat_target(target_id)
		if target!=null and target.cell_id==cell_id: return target
	return null

func _can_attempt_attack(actor: int,target: RefCounted) -> bool:
	if target==null: return false
	if target is GameState.Unit or target is GameState.Structure: return target.controller_id!=actor
	if target is WorldSiteState:
		var definition:=game_state.registry.world_site(target.definition_id)
		return definition!=null and definition.category=="village" and not target.runtime_state.get("destroyed",false)
	return false

func request_move_at(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if placement_mode:
		# In placement mode left clicks are handled by placement logic
		return
	if selected_unit_id == -1:
		_feedback("Select one of your units first.")
		return
	var destination:=pick_cell(screen_position)
	var result: GameRules.Result = _network_command(CommandDispatcher.MOVE,{"unit_id":selected_unit_id,"destination":destination}) if network_session!=null else rules.try_move(_action_actor(), selected_unit_id, destination)
	if result.success:
		selected = game_state.units[selected_unit_id].cell_id
		_present_move(selected_unit_id, result)
	_refresh_display()
	_feedback(result.reason)

func request_end_turn() -> void:
	if _human_action_blocked():
		return
	var actor:=_action_actor()
	var player:=game_state.players[actor]
	if player.research.current_technology_id.is_empty() and not rules.available_technologies(actor).is_empty():
		notification_feed.post("No research is active.",StrategicNotificationFeed.Severity.WARNING)
	if rules.living_migration_rules.is_living_migration(actor):
		for unit: GameState.Unit in game_state.units.values():
			if unit.controller_id==actor and unit.spider_state!=null:
				for job: BiologicalProductionState in unit.spider_state.nursery_jobs:
					if job.held: notification_feed.post("Completed brood is waiting for deployment.",StrategicNotificationFeed.Severity.WARNING,unit.cell_id,unit.id)
	var event_snapshot:=_turn_event_snapshot(actor)
	var result: GameRules.Result = _network_command(CommandDispatcher.END_TURN,{}) if network_session!=null else rules.try_end_turn(actor)
	if result.success:
		_post_turn_events(actor,event_snapshot)
		_feedback(result.reason)
		notification_feed.post(result.reason,StrategicNotificationFeed.Severity.INFO)
		clear_selection()
	else:
		_feedback(result.reason)
		notification_feed.post(result.reason,StrategicNotificationFeed.Severity.WARNING)
	_queue_ai_turn()

func _turn_event_snapshot(controller_id: int) -> Dictionary:
	var unit_ids: Array[int]=[]; var unit_cells: Dictionary[int,int]={}; var held_jobs:=0; var complete_districts: Array[int]=[]; var operational_bridges: Array[int]=[]
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id!=controller_id: continue
		unit_ids.append(unit.id)
		unit_cells[unit.id]=unit.cell_id
		if unit.spider_state!=null:
			for job: BiologicalProductionState in unit.spider_state.nursery_jobs:
				if job.held: held_jobs+=1
	for district: DistrictState in game_state.baumeister.districts.values():
		if district.controller_id==controller_id and district.completed: complete_districts.append(district.id)
	for bridge: BridgeState in game_state.baumeister.bridges.values():
		if bridge.controller_id==controller_id and bridge.operational: operational_bridges.append(bridge.id)
	return {"unit_ids":unit_ids,"unit_cells":unit_cells,"held_jobs":held_jobs,"research":Array(game_state.players[controller_id].research.completed_ids),
		"districts":complete_districts,"bridges":operational_bridges}

func _post_turn_events(controller_id: int,before: Dictionary) -> void:
	for technology_id: String in game_state.players[controller_id].research.completed_ids:
		if technology_id not in before.research:
			notification_feed.post("Research completed: "+game_state.registry.technology(technology_id).display_name,StrategicNotificationFeed.Severity.SUCCESS)
	for unit_id: int in before.unit_ids:
		if not game_state.units.has(unit_id): notification_feed.post("A temporary or diseased unit expired.",StrategicNotificationFeed.Severity.WARNING,int(before.unit_cells[unit_id]))
	var held_jobs:=0
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==controller_id and unit.spider_state!=null:
			for job: BiologicalProductionState in unit.spider_state.nursery_jobs:
				if job.held: held_jobs+=1
	if held_jobs>int(before.held_jobs): notification_feed.post("Biological production completed.",StrategicNotificationFeed.Severity.SUCCESS)
	for district: DistrictState in game_state.baumeister.districts.values():
		if district.controller_id==controller_id and district.completed and district.id not in before.districts:
			notification_feed.post(game_state.registry.district(district.definition_id).display_name+" completed.",StrategicNotificationFeed.Severity.SUCCESS,district.cell_id)
	for bridge: BridgeState in game_state.baumeister.bridges.values():
		if bridge.controller_id==controller_id and bridge.operational and bridge.id not in before.bridges:
			notification_feed.post("Bridge network connection completed.",StrategicNotificationFeed.Severity.SUCCESS,bridge.path[0] if not bridge.path.is_empty() else -1)
	for structure: GameState.Structure in game_state.structures.values():
		if structure.controller_id==controller_id and structure.pillar_state!=null and structure.pillar_state.integrity*3<=structure.pillar_state.max_integrity:
			notification_feed.post("Pillar Integrity is critically low.",StrategicNotificationFeed.Severity.CRITICAL,structure.cell_id,structure.id)

func _reset_camera() -> void:
	var home_cell:=0
	var best_id:=2147483647
	var focus_controller:=_view_controller_id()
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==focus_controller and "headquarters" in game_state.registry.unit(unit.definition_id).tags and unit.id<best_id:
			best_id=unit.id; home_cell=unit.cell_id
	for structure: GameState.Structure in game_state.structures.values():
		if structure.controller_id==focus_controller and "headquarters" in game_state.registry.structure(structure.definition_id).tags and structure.id<best_id:
			best_id=structure.id; home_cell=structure.cell_id
	navigation.reset(grid.get_cell(home_cell).up)
	_is_middle_dragging = false
	_left_pending = false
	_left_dragging = false

func restart_match() -> void:
	_ai_token += 1
	_ai_running = false
	ai_agent.reset()
	rules.restart_match()
	if population_result!=null: game_state.apply_population(population_result)
	if notification_feed!=null: notification_feed.clear_all()
	if privacy_overlay!=null: privacy_overlay.visible=false
	for view: MeshInstance3D in unit_views.values():
		remove_child(view)
		view.queue_free()
	unit_views.clear()
	health_fills.clear()
	for view: Node3D in site_views.values(): view.queue_free()
	site_views.clear()
	for view: Node3D in contact_views.values(): view.queue_free()
	contact_views.clear(); view_observation=null; view_team_id=-1; _handled_visibility_revision=-1
	# Visibility revisions restart with the match. Invalidate presentation
	# caches even when a new observation reuses the previous numeric revision.
	if fog_overlay!=null: fog_overlay.last_revision=-1
	if terrain_renderer!=null and terrain_renderer.dressing!=null: terrain_renderer.dressing.last_visibility_revision=-1
	if terrain_renderer!=null and terrain_renderer.cliff_overlay!=null: terrain_renderer.cliff_overlay._revision=-1
	if minimap!=null: minimap.invalidate_terrain()
	selected = NONE
	selected_unit_id = -1
	selected_structure_id = -1
	selected_site_id=-1; selected_district_id=-1; selected_contact_id=-1
	cancel_input_mode(false)
	feedback_seconds = 0.0
	feedback_label.text = ""
	_reset_camera()
	_refresh_display()
	_queue_ai_turn()

func regenerate_world(seed: int = generation_config.world_seed) -> void:
	if network_session!=null:
		_feedback("World regeneration is disabled during a network match.")
		return
	# Topology remains stable; logical population is rebuilt from the new seed.
	var recipe: PlanetGenerationConfig = generation_config.duplicate(true) as PlanetGenerationConfig
	recipe.world_seed = seed
	var replacement: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe)
	if replacement == null:
		_feedback("World generation failed validation.")
		return
	generated_planet = replacement
	game_state.terrain=replacement.terraces
	generation_config = replacement.config
	if match_config != null:
		match_config.world_seed = replacement.config.world_seed
	game_state.clear_population()
	population_config.start_cells=_player_start_cells()
	population_result=WorldPopulationGenerator.generate(replacement,game_state.registry,population_config)
	game_state.apply_population(population_result)
	rebuild_terrain()
	world_debug_view.set_world(replacement)
	world_debug_panel.show_world(replacement)
	world_debug_panel.show_population(population_result,population_config.preset)
	world_debug_panel.mode_select.select(world_debug_view.mode)
	_feedback("Generated world seed %d with %d sites and %d neutral groups." % [seed,population_result.site_records.size(),population_result.neutral_group_records.size()])

func generate_new_planet() -> void:
	# The random value is chosen once; every field then derives only from this seed.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed: int = rng.randi_range(-2147483648, 2147483647)
	if seed == generation_config.world_seed:
		seed = 0 if seed == 2147483647 else seed + 1
	regenerate_world(seed)

func set_world_debug_mode(mode: int) -> void:
	world_debug_view.set_mode(mode)
	terrain_renderer.water.visible = mode == PlanetWorldDebugView.Mode.NORMAL
	for chunk: MeshInstance3D in terrain_renderer.chunks:
		chunk.visible = mode in [PlanetWorldDebugView.Mode.NORMAL, PlanetWorldDebugView.Mode.FLOW_DIRECTION, PlanetWorldDebugView.Mode.RIVERS]
	if terrain_renderer.dressing!=null:
		terrain_renderer.dressing.visible=mode==PlanetWorldDebugView.Mode.NORMAL
	if fog_overlay!=null: fog_overlay.visible=mode==PlanetWorldDebugView.Mode.NORMAL
	world_debug_panel.mode_select.select(world_debug_view.mode)
	world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)

func _view_controller_id() -> int:
	if match_mode=="Network" and network_session!=null: return network_session.local_player_id
	if not game_state.turn_state.neutral_phase and game_state.controllers.has(game_state.active_player) \
			and game_state.controllers[game_state.active_player].kind==ControllerState.HUMAN:
		return game_state.active_player
	var humans: Array[int]=[]
	for id: int in game_state.players:
		if game_state.controllers[id].kind==ControllerState.HUMAN: humans.append(id)
	humans.sort()
	return humans[0] if not humans.is_empty() else game_state.active_player

func _action_actor() -> int:
	var controller_id:=_view_controller_id()
	return controller_id if game_state.turn_state.can_act(controller_id) else game_state.active_player

func _update_visibility_presentation(force: bool=false) -> void:
	if game_state==null or terrain_surface==null: return
	var controller_id:=_view_controller_id()
	var next_observation:=game_state.visibility_system.observation_for_controller(controller_id)
	var changed_team:=view_team_id!=-1 and view_team_id!=next_observation.team_id
	view_team_id=next_observation.team_id; view_observation=next_observation
	if changed_team:
		selected=NONE; selected_unit_id=-1; selected_structure_id=-1; selected_site_id=-1
		selected_district_id=-1; selected_contact_id=-1; cancel_input_mode(false)
		if notification_feed!=null: notification_feed.clear_all()
		if privacy_overlay!=null and match_mode=="Hotseat":
			privacy_label.text="Pass to Player %d\nPress when ready" % game_state.active_player
			privacy_overlay.visible=true
		_handled_visibility_revision=-1
	if fog_overlay!=null:
		fog_overlay.omniscient=visibility_omniscient
		fog_overlay.update_observation(grid,terrain_surface,view_observation,force or changed_team)
	if terrain_renderer!=null and terrain_renderer.dressing!=null:
		terrain_renderer.dressing.apply_visibility(view_observation,grid,visibility_omniscient)
	if terrain_renderer!=null and terrain_renderer.cliff_overlay!=null:
		if force: terrain_renderer.cliff_overlay._revision=-1
		terrain_renderer.cliff_overlay.update_observation(view_observation,visibility_omniscient)
	if notification_feed!=null and _handled_visibility_revision!=view_observation.revision:
		for id: int in view_observation.newly_observed_entity_ids:
			if view_observation.visible_entities.has(id):
				var snapshot: Dictionary=view_observation.visible_entities[id]
				notification_feed.post("Contact observed: "+StrategicTooltip.pretty(snapshot.definition_id),StrategicNotificationFeed.Severity.INFO,int(snapshot.cell_id),id)
		for id: int in view_observation.lost_entity_ids:
			if view_observation.known_contacts.has(id):
				var contact: Dictionary=view_observation.known_contacts[id]
				notification_feed.post("Contact lost; last known position recorded.",StrategicNotificationFeed.Severity.WARNING,int(contact.last_known_cell_id))
		for id: int in view_observation.newly_discovered_site_ids:
			if view_observation.observed_sites.has(id):
				var site: Dictionary=view_observation.observed_sites[id]
				notification_feed.post("Site discovered: "+StrategicTooltip.pretty(site.definition_id),StrategicNotificationFeed.Severity.SUCCESS,int(site.cell_id))
		_handled_visibility_revision=view_observation.revision

func _can_view_entity(id: int) -> bool:
	return visibility_omniscient or (view_observation!=null and view_observation.can_observe_entity(id))

func _can_view_cell(id: int) -> bool:
	return visibility_omniscient or (view_observation!=null and view_observation.is_visible(id))

func _can_view_site(id: int) -> bool:
	return visibility_omniscient or (view_observation!=null and view_observation.has_discovered_site(id))

func _observed_entity_at_cell(cell_id: int) -> RefCounted:
	if visibility_omniscient: return game_state.entity_at(cell_id)
	if view_observation==null: return null
	var ids: Array[int]=[]
	for id: int in view_observation.visible_entities:
		if int(view_observation.visible_entities[id].cell_id)==cell_id: ids.append(id)
	ids.sort_custom(func(a: int,b: int)->bool:
		var a_unit: bool=view_observation.visible_entities[a].kind=="unit"
		var b_unit: bool=view_observation.visible_entities[b].kind=="unit"
		return a_unit and not b_unit if a_unit!=b_unit else a<b)
	for id: int in ids:
		if game_state.units.has(id): return game_state.units[id]
		if game_state.structures.has(id): return game_state.structures[id]
	return null

func _observed_site_at_cell(cell_id: int) -> WorldSiteState:
	if visibility_omniscient: return game_state.site_at(cell_id)
	if view_observation==null: return null
	var ids: Array[int]=[]
	for id: int in view_observation.observed_sites:
		if int(view_observation.observed_sites[id].cell_id)==cell_id: ids.append(id)
	ids.sort()
	if ids.is_empty(): return null
	return game_state.world_sites.get(ids[0]) as WorldSiteState

func _is_view_ally(controller_id: int) -> bool:
	return visibility_omniscient or (game_state.players.has(controller_id) and game_state.visibility_system.team_id_for_controller(controller_id)==view_team_id)

func _feedback(message: String) -> void:
	feedback_label.text = message
	feedback_label.visible=not message.is_empty()
	feedback_seconds = 5.0

func _refresh_display() -> void:
	_hover_query_valid=false
	_connection_overlay_cells.clear()
	_update_visibility_presentation()
	_sync_units()
	if selected_unit_id != -1 and (not game_state.units.has(selected_unit_id) or not _can_view_entity(selected_unit_id)):
		if view_observation!=null and view_observation.known_contacts.has(selected_unit_id): selected_contact_id=selected_unit_id
		selected_unit_id = -1
		selected = NONE
	if selected_structure_id != -1 and (not game_state.structures.has(selected_structure_id) or not _can_view_entity(selected_structure_id)):
		if view_observation!=null and view_observation.known_contacts.has(selected_structure_id): selected_contact_id=selected_structure_id
		selected_structure_id = -1
		selected = NONE
	if selected_site_id!=-1 and not _can_view_site(selected_site_id): selected_site_id=-1
	if selected_contact_id!=-1 and (view_observation==null or not view_observation.known_contacts.has(selected_contact_id)): selected_contact_id=-1
	if placement_mode and (game_state.winner_id != 0 or not game_state.structures.has(recruit_hq_id)):
		_cancel_recruit(false)
	var presenting: bool = is_presenting()
	var neutral_phase:=game_state.turn_state.neutral_phase
	var view_controller:=_view_controller_id()
	var human_turn: bool = not neutral_phase and game_state.controllers.has(view_controller) and game_state.controllers[view_controller].kind==ControllerState.HUMAN and game_state.turn_state.can_act(view_controller)
	var can_act: bool = human_turn and not presenting
	road_highlights.clear()
	site_highlights.clear()
	if selected_site_id!=-1 and game_state.world_sites.has(selected_site_id):
		var highlighted_site: WorldSiteState=game_state.world_sites[selected_site_id]
		site_highlights=[highlighted_site.cell_id]
		site_highlights.append_array(grid.get_neighbors(highlighted_site.cell_id))
	reachable_tiles.clear()
	if can_act:
		reachable_tiles = rules.reachable(view_controller, selected_unit_id)
	attack_tiles.clear()
	if can_act:
		for id: int in rules.attack_targets(view_controller, selected_unit_id):
			if game_state.units.has(id):
				attack_tiles.append(game_state.units[id].cell_id)
			elif game_state.structures.has(id):
				attack_tiles.append(game_state.structures[id].cell_id)
			elif game_state.world_sites.has(id):
				attack_tiles.append(game_state.world_sites[id].cell_id)
	if can_act and selected_unit_id!=-1 and game_state.units.has(selected_unit_id):
		var selected_unit: GameState.Unit=game_state.units[selected_unit_id]
		if "road_builder" in game_state.registry.unit(selected_unit.definition_id).tags:
			road_highlights=rules.living_migration_rules.valid_road_extensions(selected_unit.controller_id,selected_unit.id)
	if can_act and selected_structure_id!=-1 and game_state.structures.has(selected_structure_id):
		var selected_structure: GameState.Structure=game_state.structures[selected_structure_id]
		if selected_structure.pillar_state!=null:
			var engineer:=_available_engineer(selected_structure.controller_id,selected_structure.cell_id)
			if engineer!=null: road_highlights=rules.baumeister_rules.candidate_pillar_cells(selected_structure.controller_id,engineer.id,selected_structure.id)
	preview_path.clear()
	attack_preview_label.text = ""
	hover_cell = NONE
	if world_debug_panel.visible:
		world_debug_panel.inspect_cell(selected)
	_refresh_tile_materials()
	_update_label()
	if neutral_phase:
		turn_label.text="Round %d · Enemy turn" % game_state.round_number
		materials_label.text="AI factions, wildlife, and guardians are acting."
	else:
		if game_state.turn_state.simultaneous_player_turns_enabled and game_state.turn_state.simultaneous_stage_started:
			var remaining:=0
			for player_id: int in game_state.turn_state.simultaneous_player_ids(): remaining+=int(game_state.turn_state.can_act(player_id))
			turn_label.text="Round %d · Simultaneous player turns · %d planning" % [game_state.round_number,remaining]
		else:
			var active_player:=game_state.players[game_state.active_player]
			var active_faction:=game_state.registry.faction(active_player.faction_id)
			turn_label.text="Round %d · Enemy turn · P%d · %s" % [game_state.round_number,game_state.active_player,active_faction.display_name]
		materials_label.text = _resource_text(view_controller)
	if players_label!=null: players_label.text=_player_overview_text()
	_refresh_resource_bar(view_controller)
	end_turn_button.text = "Neutral activity..." if neutral_phase else "End Movement Phase"
	end_turn_button.disabled = game_state.winner_id != 0 or not can_act
	if presenting:
		end_turn_button.text = "Moving..."
	restart_button.visible = game_state.winner_id != 0 and network_session==null
	if game_state.winner_id != 0:
		var winner: PlayerState=game_state.players[game_state.winner_id]
		var winner_faction:=game_state.registry.faction(winner.faction_id)
		turn_label.text = "%s wins as %s · Round %d · %ds" % [winner.player_name,
			winner_faction.display_name if winner_faction!=null else winner.faction_id,game_state.round_number,game_state.match_duration_seconds()]
	if strategic_panel.visible and not neutral_phase: strategic_panel.configure(rules,view_controller)
	_refresh_management_workflow(view_controller,can_act)
	if minimap!=null: minimap.configure(game_state,view_observation,view_controller,navigation.focus_direction)
	_clear_recruit_box()
	if selected_unit_id != -1:
		var unit: GameState.Unit = game_state.units[selected_unit_id]
		var unit_definition:=game_state.registry.unit(unit.definition_id)
		var own_unit:=unit.controller_id==view_controller
		var visual_id:=unit_definition.visual_id if not unit_definition.visual_id.is_empty() else unit.definition_id
		var role_tags:=PackedStringArray()
		for tag: String in unit_definition.tags:
			if tag in ["worker","support","military","vehicle","armored","flying","engineer","healer","reconnaissance","anti_air","biological"]: role_tags.append(StrategicTooltip.pretty(tag))
		var role:=" · ".join(role_tags) if not role_tags.is_empty() else (unit_definition.description.get_slice(".",0) if not unit_definition.description.is_empty() else "Tactical unit")
		role+=" · P%d" % unit.controller_id
		unit_info_panel.show_unit(unit_definition.display_name,role,visual_id,unit.hp,unit.max_hp,
			EntityView.visible_member_count(unit_definition.squad_size,unit.hp,unit.max_hp),unit_definition.squad_size,unit_definition.icon_path,unit.id)
		unit_info_panel.set_stats(_unit_stat_presentations(unit))
		unit_info_panel.set_statuses(_unit_status_presentations(unit,own_unit))
		unit_info_panel.set_queued(_queued_combat_text(unit) if own_unit else "")
		var move_status: String = "Moved" if unit.moved else "Ready"
		if unit.attacked:
			move_status = "Spent (attacked)"
		var attack_status: String = "Spent" if unit.attacked else "Ready"
		if game_state.winner_id != 0 or not human_turn:
			move_status = "Disabled"
			attack_status = "Disabled"
		unit_label.text = "Player %d | %s #%d\nCell %d | HP: %d/%d\nMovement: %d | Damage: %d | Range: %d\nMove: %s | Attack: %s" % [
			unit.owner_id, unit.unit_type, unit.id, unit.cell_id, unit.hp, unit.max_hp,
			unit.movement, unit.attack_damage, unit.attack_range, move_status, attack_status,
		]
		if unit_definition.squad_size>1: unit_label.text+="\nSquad members: %d/%d" % [EntityView.visible_member_count(unit_definition.squad_size,unit.hp,unit.max_hp),unit_definition.squad_size]
		if own_unit and unit.counter_cooldown_remaining>0: unit_label.text+="\nCounter cooldown: %d rounds" % unit.counter_cooldown_remaining
		if own_unit and game_state.combat_orders.intents.has(unit.id):
			var queued: CombatIntent=game_state.combat_orders.intents[unit.id]
			unit_label.text+="\nCombat order queued: "+queued.option_id.capitalize()
			if queued.option_id=="attack": unit_label.text+="\nTarget: "+_combat_target_display_name(queued.target_id)
			unit_label.text+="\nResolves after movement phases."
		if own_unit and unit.ready_next_turn:
			unit_label.text += "\nReady next turn."
		if unit.controller_id==view_controller:
			unit_label.text += "\nUpkeep: %s (%s)" % [_resource_record(game_state.registry.unit(unit.definition_id).upkeep),"paid" if unit.upkeep_paid else "UNPAID — production inactive"]
		if own_unit and unit.remaining_lifetime_turns>0: unit_label.text += "\nLifetime: %d owner turns" % unit.remaining_lifetime_turns
		if own_unit and unit.development!=null:
			unit_label.text += "\nDevelopment: %d/%d | Food: %d | Matter: %d" % [unit.development.progress_turns,
				unit.development.required_turns,unit.development.stored_food,unit.development.stored_matter]
		if own_unit and unit.active_disease!=null: unit_label.text += "\nDisease: %s (%d)" % [unit.active_disease.definition_id.capitalize(),unit.active_disease.remaining_turns]
		if own_unit and unit.designation!=null: unit_label.text += "\nDesignated: %d turns" % unit.designation.remaining_turns
		if own_unit and "deployable_artillery" in game_state.registry.unit(unit.definition_id).tags:
			unit_label.text += "\nArtillery state: "+("DEPLOYED" if unit.deployed else "MOBILE")
		if "engineer" in game_state.registry.unit(unit.definition_id).tags: unit_label.text += "\nActions: infrastructure build/repair, field vehicle repair"
		if "healer" in game_state.registry.unit(unit.definition_id).tags: unit_label.text += "\nAction: heal adjacent biological personnel"
		if "designator" in game_state.registry.unit(unit.definition_id).tags: unit_label.text += "\nAction: bounded target designation"
		if own_unit and "ant" in game_state.registry.unit(unit.definition_id).tags:
			unit_label.text += "\nConnection: %s | Disconnected turns: %d" % ["connected" if rules.living_migration_rules.is_ant_connected(unit) else "disconnected",unit.disconnected_turns]
		if unit.controller_id != view_controller:
			var relationship:=game_state.relationships.between(view_controller,unit.controller_id)
			var relationship_name: String=RelationshipState.Kind.keys()[relationship].capitalize()
			unit_label.text += "\n%s unit: inspection only." % relationship_name
		else:
			_building_unit_overlay=true
			_unit_actions_disabled_reason="" if can_act else "This unit is not currently actionable."
			_unit_action_group=UnitInfoPanel.GROUP_ATTACKS
			_action_button("Move — choose green cell",_begin_target_mode.bind(StrategicInputMode.Kind.MOVE,unit.id),"Movement range and destination are validated by the movement rules.","Unit has spent movement." if unit.moved or unit.attacked else ("No legal destination." if reachable_tiles.is_empty() else ""))
			_action_button("Attack — choose purple target",_begin_target_mode.bind(StrategicInputMode.Kind.ATTACK,unit.id),"Queue an attack for automatic resolution after all movement phases.","No visible legal target." if attack_tiles.is_empty() else "")
			if game_state.turn_state.simultaneous_combat_enabled:
				_unit_action_group=UnitInfoPanel.GROUP_STANCES
				_action_button("Dodge",_submit_combat_option.bind(unit.id,"dodge"),"Reduce every incoming hit by 2 this resolution.")
				_action_button("Counter",_submit_combat_option.bind(unit.id,"counter"),"Block 2 and retaliate for 2 against the first incoming hit. Cooldown: 2 rounds.","Cooldown: %d rounds" % unit.counter_cooldown_remaining if unit.counter_cooldown_remaining>0 else "")
				if game_state.combat_orders.intents.has(unit.id): _action_button("Cancel Combat Order",_clear_combat_option.bind(unit.id),"Remove this unit's queued order before ending movement.")
		_unit_action_group=UnitInfoPanel.GROUP_SPECIAL
		if unit.controller_id==view_controller and unit.spider_state!=null:
			_unit_action_group=UnitInfoPanel.GROUP_CITY
			_populate_spider_panel(unit)
		elif unit.controller_id==view_controller and "disease_carrier" in game_state.registry.unit(unit.definition_id).tags and can_act:
			var selected_disease:=game_state.registry.disease(unit.selected_disease_id)
			unit_label.text += "\nSelected disease: "+(selected_disease.display_name if selected_disease!=null else StrategicTooltip.pretty(unit.selected_disease_id))
			for disease_id: String in rules.living_migration_rules.available_diseases(unit.controller_id):
				var disease:=game_state.registry.disease(disease_id)
				var detail:="%s\nDuration: %d turns | Immunity: %d turns\nDamage/turn: %d | Attack reduction: %d" % [
					disease.description if not disease.description.is_empty() else "Temporary mite-delivered disease.",disease.duration_turns,disease.immunity_turns,disease.damage_per_turn,disease.attack_damage_reduction]
				_action_button("Select "+disease.display_name,_select_disease_ui.bind(unit.id,disease_id),detail)
		elif unit.development!=null and unit.development.has_consumed and can_act:
			for outcome_id: String in rules.living_migration_rules.available_transformations(unit.controller_id,unit.id):
				_action_button("Transform: "+game_state.registry.unit(outcome_id).display_name,_transform_selected.bind(unit.id,outcome_id),"Complete this unit's current development path.")
		if own_unit and unit.definition_id in ["dragonfly","mosquito"]:
			var larva_reason:=_unit_actions_disabled_reason
			if larva_reason.is_empty():
				var has_water:=false
				for cell_id: int in grid.get_cells_within_distance(unit.cell_id,rules.living_migration_rules.config_for(unit.controller_id).larva_interaction_range): has_water=has_water or game_state.is_water_cell(cell_id)
				if not has_water: larva_reason="No valid water target is in range."
			_action_button("Lay Larva",_lay_larva_auto.bind(unit.id),"Lay on a water cell in range. Matures after five rounds with deterministic 25% emergence.",larva_reason)
		if own_unit and unit.development!=null and not unit.development.has_consumed:
			var consume_reason:=_unit_actions_disabled_reason
			if consume_reason.is_empty():
				var has_vegetation:=false
				for cell_id: int in grid.get_cells_within_distance(unit.cell_id,1): has_vegetation=has_vegetation or (not game_state.is_water_cell(cell_id) and game_state.living_migration.terrain_at(cell_id).kind==TerrainConsumptionState.Kind.FRESH)
				if not has_vegetation: consume_reason="No eligible vegetation is in range."
			_action_button("Consume Vegetation",_consume_vegetation_auto.bind(unit.id),"Gain Food and begin the five-round transformation countdown.",consume_reason)
			for corpse: CorpseState in game_state.living_migration.corpses.values():
				if not corpse.consumed and game_state.grid.distance(unit.cell_id,corpse.cell_id)<=1: _action_button("Consume Corpse",_consume_caterpillar_corpse.bind(unit.id,corpse.id),"Gain Matter and begin transformation.",_unit_actions_disabled_reason)
		if can_act and "ant" in game_state.registry.unit(unit.definition_id).tags:
			for corpse: CorpseState in game_state.living_migration.corpses.values():
				if not corpse.consumed and game_state.grid.distance(unit.cell_id,corpse.cell_id)<=1:
					_action_button("Consume corpse (+%d Food)" % corpse.food_value,_consume_corpse_ui.bind(unit.id,corpse.id))
		if own_unit and "deployable_artillery" in game_state.registry.unit(unit.definition_id).tags:
			_action_button("Become "+("MOBILE" if unit.deployed else "DEPLOYED"),_toggle_deployment_ui.bind(unit.id),"Switch between mobile and deployed combat profiles.",_unit_actions_disabled_reason)
		if own_unit and "healer" in game_state.registry.unit(unit.definition_id).tags:
			_action_button("Heal target",_begin_target_mode.bind(StrategicInputMode.Kind.HEAL,unit.id),"Choose an adjacent damaged biological unit. Teal cells are valid targets.",_unit_actions_disabled_reason)
		if own_unit and "engineer" in game_state.registry.unit(unit.definition_id).tags:
			_action_button("Repair target",_begin_target_mode.bind(StrategicInputMode.Kind.REPAIR,unit.id),"Choose a damaged adjacent vehicle or Pillar. Orange cells are valid targets.",_unit_actions_disabled_reason)
			for bridge: BridgeState in game_state.baumeister.bridges.values():
				if bridge.controller_id==unit.controller_id and bridge.hp<bridge.max_hp:
					_action_button("Repair Bridge #%d" % bridge.id,_repair_bridge_ui.bind(unit.id,bridge.id))
		if own_unit and "designator" in game_state.registry.unit(unit.definition_id).tags:
			_action_button("Designate target",_begin_target_mode.bind(StrategicInputMode.Kind.DESIGNATE,unit.id),"Choose a hostile target within command range. Red cells are valid targets.",_unit_actions_disabled_reason)
		_building_unit_overlay=false; _unit_actions_disabled_reason=""
	elif selected_structure_id != -1:
		var headquarters: GameState.Structure = game_state.structures[selected_structure_id]
		var structure_definition:=game_state.registry.structure(headquarters.definition_id)
		unit_info_panel.show_context(structure_definition.display_name,"Structure · P%d" % headquarters.controller_id,
			structure_definition.visual_id if not structure_definition.visual_id.is_empty() else headquarters.definition_id,headquarters.hp,headquarters.max_hp)
		unit_label.text = "%s | Player %d\nCell %d | HP: %d/%d\nRecruit available: %s" % [
			structure_definition.display_name,
			headquarters.owner_id, headquarters.cell_id, headquarters.hp, headquarters.max_hp,
			"Yes" if headquarters.recruit_available else "No",
		]
		if headquarters.pillar_state!=null:
			_populate_pillar_panel(headquarters,can_act)
		if headquarters.owner_id == view_controller and can_act and game_state.winner_id == 0:
			var faction:=game_state.registry.faction(game_state.players[view_controller].faction_id)
			for unit_id: String in faction.unit_roster_ids:
				var definition:=game_state.registry.unit(unit_id)
				var reason: String = _unit_lock_reason(view_controller,unit_id)
				if reason.is_empty(): reason=rules.recruit_error(view_controller, headquarters.id, unit_id)
				if reason.is_empty() and rules.recruit_destinations(view_controller, headquarters.id, unit_id).is_empty():
					reason = "No free adjacent tiles."
				var button := Button.new()
				button.name = "Recruit" + definition.display_name
				button.text = "%s: %s\nHP %d | Move %d | Range %d | Damage %d" % [
					definition.display_name, _resource_record(definition.costs), definition.max_hp,
					definition.movement, definition.attack_range, definition.attack_damage,
				]
				button.focus_mode = Control.FOCUS_NONE
				ContentIcon.apply(button,definition)
				button.disabled = not reason.is_empty()
				button.tooltip_text = StrategicTooltip.unit(definition)+("\n\nUnavailable: "+reason if not reason.is_empty() else "")
				button.pressed.connect(_begin_recruit.bind(unit_id, headquarters.id))
				recruit_box.add_child(button)
				if not reason.is_empty():
					var explanation: Label = _hud_label(recruit_box)
					explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					explanation.text = reason
	elif selected_district_id!=-1 and game_state.baumeister.districts.has(selected_district_id):
		var district: DistrictState=game_state.baumeister.districts[selected_district_id]
		var definition:=game_state.registry.district(district.definition_id)
		unit_info_panel.show_context(definition.display_name,"District · P%d" % district.controller_id)
		var district_status:="Building"
		if district.completed: district_status="Operational" if district.maintenance_paid else "Unmaintained"
		unit_label.text="%s district\nCell %d | Player %d\nConstruction: %d/%d (%s)\nProduction: %s\nUpkeep: %s" % [
			definition.display_name,district.cell_id,district.controller_id,district.construction_progress,district.required_turns,
			district_status,_resource_record(definition.turn_production),_resource_record(definition.upkeep)]
	elif selected_site_id!=-1 and game_state.world_sites.has(selected_site_id):
		var site: WorldSiteState=game_state.world_sites[selected_site_id]
		var definition:=game_state.registry.world_site(site.definition_id)
		unit_info_panel.show_context(definition.display_name,definition.category.capitalize(),definition.visual_id,
			site.hp if definition.max_hp>0 else -1,site.max_hp)
		var site_visible:=_can_view_cell(site.cell_id)
		var observed_site: Dictionary=view_observation.observed_sites.get(site.id,{}) if view_observation!=null else {}
		var runtime: Dictionary=site.runtime_state if site_visible or visibility_omniscient else observed_site.get("runtime_state",{})
		var observed_controller:=site.controller_id if site_visible or visibility_omniscient else int(observed_site.get("controller_id",0))
		var relation:="World"
		if observed_controller>0:
			relation=RelationshipState.Kind.keys()[game_state.relationship_for_site(view_controller,site)].capitalize() if definition.category=="village" else RelationshipState.Kind.keys()[game_state.relationships.between(view_controller,observed_controller)].capitalize()
		var status:="Available"
		if definition.interaction_type=="gather":
			status="Charges %d/%d" % [runtime.get("remaining_charges",0),definition.initial_charges]
			if runtime.get("exhausted",false): status="Exhausted"+(" · regenerates in %d rounds" % runtime.get("regeneration_remaining",0) if definition.regeneration_turns>0 else "")
		elif definition.interaction_type=="explore": status="Explored" if runtime.get("explored",false) else "Unexplored"
		if definition.category=="village":
			status=("Destroyed - loot %s" % ("available" if runtime.get("loot_available",false) else "claimed")) if runtime.get("destroyed",false) else ("Hostile" if relation=="Hostile" else "Peaceful trade")
		if not site_visible and not visibility_omniscient: status+=" (last observed round %d)" % int(observed_site.get("observed_round",0))
		unit_label.text="%s · %s\n%s\nCell %d | Relation: %s\nInteraction: %s" % [definition.display_name,definition.category.capitalize(),definition.description,
			site.cell_id,relation,status]
		if definition.category=="village":
			var shown_hp:=site.hp if site_visible or visibility_omniscient else int(observed_site.get("hp",site.hp))
			var guards:=0; var knight_alive:=false
			if site_visible:
				for guard: GameState.Unit in game_state.units.values():
					if guard.home_site_id==site.id and _can_view_entity(guard.id): guards+=1; knight_alive=knight_alive or guard.definition_id=="knight_of_the_land"
			unit_label.text+="\nHP: %d/%d\nGuards observed: %d - Knight: %s\nAllegiance: %s" % [shown_hp,site.max_hp,guards,"present" if knight_alive else "not observed",definition.neutral_allegiance_id.capitalize()]
		if can_act and site_visible:
			for interaction: Dictionary in rules.available_site_interactions(view_controller,site.id):
				var detail:="Cost: %s\nReward: %s" % [_resource_record(interaction.cost),_resource_record(interaction.reward)]
				_action_button(interaction.label,_site_interact_ui.bind(site.id,interaction.id,interaction.unit_id),detail,interaction.error)
	elif selected_contact_id!=-1 and view_observation!=null and view_observation.known_contacts.has(selected_contact_id):
		var contact: Dictionary=view_observation.known_contacts[selected_contact_id]
		unit_info_panel.show_context(StrategicTooltip.pretty(contact.observed_definition_id),"Last-seen contact")
		unit_info_panel.set_statuses([{"label":"LAST SEEN","tooltip":"Historical intelligence only; current HP, position, and orders are unknown.","color":"#765b36"}])
		unit_label.text="Last-known contact\n%s #%d\nCell %d | last seen round %d\nHistorical intelligence: live position, HP, and orders are unknown." % [
			StrategicTooltip.pretty(contact.observed_definition_id),selected_contact_id,int(contact.last_known_cell_id),int(contact.last_seen_round)]
	else:
		unit_info_panel.hide_panel()
		unit_label.text = "No unit selected.\nLeft click: inspect / select\nRight click: move / attack\nEsc: clear"
	if input_mode!=StrategicInputMode.Kind.NORMAL:
		unit_label.text+="\n\nMODE: %s\nRight click or Escape cancels." % StrategicInputMode.display_name(input_mode)
	action_panel.visible=selected_unit_id==-1 and not strategic_panel.visible
	players_label.visible=selected_unit_id==-1
	selection_legend.visible=selected_unit_id==-1
	coordinate_label.visible=not strategic_panel.visible and selected_unit_id==-1 and selected_structure_id==-1 and selected_district_id==-1 and selected_site_id==-1 and selected_contact_id==-1
	feedback_label.visible=not feedback_label.text.is_empty()
	attack_preview_label.visible=not attack_preview_label.text.is_empty()
	_schedule_selection_layout()

func _resource_text(controller_id: int=-1) -> String:
	var lines:=PackedStringArray()
	var player_id:=game_state.active_player if controller_id<0 else controller_id
	var player: PlayerState=game_state.players[player_id]
	var faction:=game_state.registry.faction(player.faction_id)
	var amounts:=PackedStringArray()
	for resource_id: String in faction.resource_ids:
		amounts.append("%s %d" % [game_state.registry.resource(resource_id).display_name,player.resource_amount(resource_id)])
	lines.append("P%d %s: %s" % [player_id,faction.display_name," | ".join(amounts)])
	if rules.living_migration_rules.is_living_migration(player_id):
		var summary:=rules.living_migration_rules.economic_summary(player_id)
		lines.append("Expected production: "+_resource_record(summary.production))
		lines.append("Current upkeep: "+_resource_record(summary.upkeep))
		if not summary.unpaid.is_empty(): lines.append("Unpaid upkeep; affected production inactive: "+_resource_record(summary.unpaid))
	elif rules.baumeister_rules.is_baumeister(player_id):
		var summary:=rules.baumeister_rules.economic_summary(player_id)
		lines.append("Expected production: "+_resource_record(summary.production))
		lines.append("Upkeep + maintenance: "+_resource_record(summary.upkeep))
		if summary.unpaid_maintenance>0: lines.append("Unpaid bridge maintenance: %d Materials" % summary.unpaid_maintenance)
		if summary.unmaintained_districts>0: lines.append("Unmaintained districts (production inactive): %d" % summary.unmaintained_districts)
	lines.append("Active: Player %d (%s)" % [game_state.active_player,player_controllers[game_state.active_player]])
	return "\n".join(lines)

func _refresh_resource_bar(controller_id: int=-1) -> void:
	for child: Node in resource_bar.get_children():
		resource_bar.remove_child(child); child.queue_free()
	var player_id:=game_state.active_player if controller_id<0 else controller_id
	if not game_state.players.has(player_id): return
	var player: PlayerState=game_state.players[player_id]
	var faction:=game_state.registry.faction(player.faction_id)
	var production: Dictionary=faction.turn_resource_income.duplicate()
	var upkeep: Dictionary={}
	var summary: Dictionary={}
	if rules.living_migration_rules.is_living_migration(player_id): summary=rules.living_migration_rules.economic_summary(player_id)
	elif rules.baumeister_rules.is_baumeister(player_id): summary=rules.baumeister_rules.economic_summary(player_id)
	for id: String in summary.get("production",{}): production[id]=production.get(id,0)+summary.production[id]
	upkeep=summary.get("upkeep",{})
	for resource_id: String in faction.resource_ids:
		var definition:=game_state.registry.resource(resource_id)
		var chip:=Button.new(); chip.name="Resource_"+resource_id; chip.disabled=true; chip.focus_mode=Control.FOCUS_NONE; chip.add_theme_constant_override("icon_max_width",20)
		var income:=int(production.get(resource_id,0)); var cost:=int(upkeep.get(resource_id,0))
		chip.text="%s  %d  (%+d)" % [definition.display_name,player.resource_amount(resource_id),income-cost]
		chip.tooltip_text=StrategicTooltip.resource(definition,player.resource_amount(resource_id),income,cost)
		ContentIcon.apply(chip,definition)
		chip.mouse_filter=Control.MOUSE_FILTER_STOP; resource_bar.add_child(chip)
	var research:=player.research
	var research_chip:=Label.new(); research_chip.name="ResearchProgress"
	if research.current_technology_id.is_empty(): research_chip.text="Research: none"
	else:
		var technology:=game_state.registry.technology(research.current_technology_id)
		research_chip.text="%s %d/%d" % [technology.display_name,research.accumulated_progress,technology.research_cost]
	research_chip.mouse_filter=Control.MOUSE_FILTER_STOP; resource_bar.add_child(research_chip)

func _unit_lock_reason(controller_id: int,unit_id: String) -> String:
	if rules.research_rules.is_unit_unlocked(controller_id,unit_id): return ""
	var faction:=game_state.registry.faction(game_state.players[controller_id].faction_id)
	for technology_id: String in faction.technology_ids:
		var technology:=game_state.registry.technology(technology_id)
		if unit_id in technology.unlock_unit_ids: return "Requires research: "+technology.display_name
	return "Unit is not available to this faction."

func _resource_record(values: Dictionary) -> String:
	if values.is_empty(): return "none"
	var ids: Array[String]=[]
	for id: String in values: ids.append(id)
	ids.sort()
	var parts:=PackedStringArray()
	for id: String in ids: parts.append("%s %+d" % [game_state.registry.resource(id).display_name,values[id]])
	return ", ".join(parts)

func _populate_spider_panel(unit: GameState.Unit) -> void:
	var spider:=unit.spider_state
	var config:=rules.living_migration_rules.config_for(unit.controller_id)
	var mite_interval:=config.improved_mite_interval if rules.research_rules.has_unlock_tag(unit.controller_id,"improved_mite_interval") else config.mite_production_interval
	unit_info_panel.add_action_note(UnitInfoPanel.GROUP_CITY,"Nursery: "+(StrategicTooltip.pretty(spider.nursery_branch) if not spider.nursery_branch.is_empty() else "Choose a branch"))
	unit_info_panel.add_action_value(UnitInfoPanel.GROUP_CITY,"slots","Internal slots","%d / %d" % [spider.slots.size(),spider.slot_limit],"Internal slots: %d / %d occupied" % [spider.slots.size(),spider.slot_limit])
	unit_info_panel.add_action_value(UnitInfoPanel.GROUP_CITY,"group","Held mites",str(spider.held_mites),"Mites ready to deploy: %d" % spider.held_mites)
	unit_info_panel.add_action_value(UnitInfoPanel.GROUP_CITY,"lifetime","Next mite","%d turns" % maxi(0,mite_interval-spider.mite_progress),"Mite production progress: %d / %d turns" % [spider.mite_progress,mite_interval])
	unit_label.text += "\n\nSpider internals: %d/%d slots\nNursery: %s\nMites: %d | progress %d/%d" % [
		spider.slots.size(),spider.slot_limit,spider.nursery_branch.replace("_"," ").capitalize() if not spider.nursery_branch.is_empty() else "unselected",
		spider.held_mites,spider.mite_progress,mite_interval]
	unit_label.text += "\nSlots: "+(", ".join(spider.slots) if not spider.slots.is_empty() else "empty")
	var slot_cells:=PackedStringArray()
	for slot_index in range(spider.slot_limit):
		var slot_name:="Empty" if slot_index>=spider.slots.size() else StrategicTooltip.pretty(spider.slots[slot_index])
		slot_cells.append("[%d %s]" % [slot_index+1,slot_name])
	unit_label.text+="\nInternal storage (9 slots):\n"+" ".join(slot_cells)
	if spider.construction!=null:
		unit_info_panel.add_action_note(UnitInfoPanel.GROUP_CITY,"Construction: %s · %d / %d turns" % [StrategicTooltip.pretty(spider.construction.recipe_id),spider.construction.progress_turns,spider.construction.required_turns])
		unit_label.text += "\nConstruction [%s]: %s %d/%d" % ["READY" if spider.construction.is_complete() else "ACTIVE",StrategicTooltip.pretty(spider.construction.recipe_id),spider.construction.progress_turns,
			spider.construction.required_turns]
	if spider.nursery_branch.is_empty():
		unit_label.text+="\nNursery branch is permanent once chosen."
		for branch_id: String in LivingMigrationRules.BRANCHES:
			_action_button("Choose "+branch_id.replace("_"," ").capitalize(),_choose_branch.bind(unit.id,branch_id),"Permanent branch choice. Review its brood recipes before confirming.","All internal slots are occupied." if not spider.has_slot() else "")
	else:
		for recipe_id: String in ContentRegistry._sorted_keys(game_state.registry.biological_recipes):
			var recipe:=game_state.registry.biological_recipe(recipe_id)
			if recipe.branch_id==spider.nursery_branch:
				var outcomes:=PackedStringArray()
				for outcome_id: String in recipe.outcome_unit_ids: outcomes.append(game_state.registry.unit(outcome_id).display_name)
				var development_turns:=recipe.development_turns
				if rules.research_rules.has_unlock_tag(unit.controller_id,"nursery_improvements"): development_turns=maxi(1,development_turns-config.nursery_development_reduction)
				var nutrients:=recipe.nutrient_requirement
				if nutrients>0 and rules.research_rules.has_unlock_tag(unit.controller_id,"biological_maturation"): nutrients=maxi(1,nutrients-config.caterpillar_requirement_reduction)
				var production_reason:=""
				if spider.nursery_jobs.size()>=config.nursery_slot_count: production_reason="Nursery storage is full."
				elif not game_state.players[unit.controller_id].can_afford(recipe.costs): production_reason="Insufficient faction resources."
				var unlocked:=false
				for outcome_id: String in recipe.outcome_unit_ids: unlocked=unlocked or rules.research_rules.is_unit_unlocked(unit.controller_id,outcome_id)
				if not unlocked: production_reason="Requires research to unlock a recipe outcome."
				_action_button("Produce %s\n%s · %d turns" % [recipe.display_name,_resource_record(recipe.costs),development_turns],
					_queue_recipe.bind(unit.id,recipe_id),"%s\nOutcome: %s\nNutrients: %d" % [recipe.description if not recipe.description.is_empty() else "Biological production job.",", ".join(outcomes),nutrients],production_reason)
	for index in range(spider.nursery_jobs.size()):
		var job: BiologicalProductionState=spider.nursery_jobs[index]
		var recipe_definition:=game_state.registry.biological_recipe(job.recipe_id)
		var job_label:=Label.new(); job_label.text="[%s] %s: %d/%d | nutrients %d/%d" % ["READY" if job.held else "ACTIVE",recipe_definition.display_name if recipe_definition!=null else StrategicTooltip.pretty(job.recipe_id),job.progress_turns,
			job.required_turns,job.nutrients_collected,job.required_nutrients]
		unit_info_panel.add_action_note(UnitInfoPanel.GROUP_CITY,job_label.text); job_label.free()
		if job.held:
			for outcome_id: String in job.outcome_unit_ids:
				if rules.research_rules.is_unit_unlocked(unit.controller_id,outcome_id):
					var outcome:=game_state.registry.unit(outcome_id)
					var effective_lifetime:=outcome.temporary_lifetime_turns
					if effective_lifetime>0 and rules.research_rules.has_unlock_tag(unit.controller_id,"marsh_longevity"): effective_lifetime+=config.temporary_lifetime_bonus
					var lifetime:=" (%d turns)" % effective_lifetime if effective_lifetime>0 else ""
					_action_button("Deploy "+outcome.display_name+lifetime,_deploy_job_auto.bind(unit.id,index,outcome_id))
	if spider.held_mites>0: _action_button("Deploy Mite",_deploy_mite_auto.bind(unit.id))
	var growth_cost:=rules.living_migration_rules.spider_cost(unit.controller_id)
	var construction_reason:="Construction is already in progress." if spider.construction!=null else ""
	var growth_reason:=construction_reason
	if growth_reason.is_empty() and not game_state.players[unit.controller_id].can_afford(growth_cost): growth_reason="Insufficient Silk."
	_action_button("Grow Spider (%s)" % _resource_record(growth_cost),_start_spider.bind(unit.id),"Construct another mobile headquarters.",growth_reason)
	for building_id: String in LivingMigrationRules.INTERNAL_BUILDINGS:
		var building_reason:=construction_reason
		if not spider.has_slot(): building_reason="All internal slots are occupied."
		elif building_reason.is_empty() and not game_state.players[unit.controller_id].can_afford({"food":config.internal_building_food_cost}): building_reason="Insufficient Food."
		_action_button("Build "+building_id.replace("_"," ").capitalize(),_build_internal.bind(unit.id,building_id),"Cost: %d Food · %d turns\nUses one internal slot." % [config.internal_building_food_cost,config.internal_construction_turns],building_reason)
	if spider.construction!=null and spider.construction.recipe_id=="spider_construction" and spider.construction.is_complete():
		_action_button("Deploy completed Spider",_deploy_spider_auto.bind(unit.id))
	var research_state:=game_state.players[unit.controller_id].research
	if research_state.current_technology_id.is_empty():
		for technology_id: String in rules.available_technologies(unit.controller_id):
			_action_button("Research: "+game_state.registry.technology(technology_id).display_name,_start_research_ui.bind(technology_id))
	else:
		var technology:=game_state.registry.technology(research_state.current_technology_id)
		unit_label.text += "\nResearch: %s %d/%d" % [technology.display_name,research_state.accumulated_progress,technology.research_cost]
		unit_info_panel.add_action_note(UnitInfoPanel.GROUP_CITY,"Research: %s · %d / %d" % [technology.display_name,research_state.accumulated_progress,technology.research_cost])

func _action_button(label: String,callback: Callable,tooltip: String="",disabled_reason: String="",selected_state: bool=false) -> void:
	if _building_unit_overlay and unit_info_panel!=null:
		# Movement remains a direct world interaction; avoid a redundant button.
		if label.begins_with("Move "): return
		if disabled_reason.is_empty() and not _unit_actions_disabled_reason.is_empty(): disabled_reason=_unit_actions_disabled_reason
		if _unit_action_group==UnitInfoPanel.GROUP_ATTACKS and selected_unit_id!=-1:
			var attack_option:=game_state.registry.combat_option("attack")
			label=attack_option.display_name
			tooltip="%s\nDamage: %d\nRange: %d\nResolves during shared combat." % [attack_option.description,
				game_state.units[selected_unit_id].attack_damage,game_state.units[selected_unit_id].attack_range]
		if selected_unit_id!=-1 and game_state.combat_orders.intents.has(selected_unit_id):
			var intent: CombatIntent=game_state.combat_orders.intents[selected_unit_id]
			if _unit_action_group==UnitInfoPanel.GROUP_ATTACKS:
				selected_state=intent.option_id=="attack"
			elif _unit_action_group==UnitInfoPanel.GROUP_STANCES:
				selected_state=intent.option_id==label.to_lower()
		unit_info_panel.add_action(_unit_action_group,label,callback,tooltip,disabled_reason,selected_state); return
	var button:=Button.new(); button.text=label; button.focus_mode=Control.FOCUS_NONE
	button.tooltip_text=tooltip+("\n\nUnavailable: "+disabled_reason if not disabled_reason.is_empty() else "")
	button.disabled=not disabled_reason.is_empty()
	button.pressed.connect(callback); recruit_box.add_child(button)

func _unit_stat_presentations(unit: GameState.Unit) -> Array[Dictionary]:
	var definition:=game_state.registry.unit(unit.definition_id)
	var movement_status:="Spent" if unit.moved or unit.attacked else "Ready"
	var stats: Array[Dictionary]=[
		{"label":"Damage","value":str(unit.attack_damage),"tooltip":_resolved_stat_tooltip("Damage",definition.attack_damage,unit.attack_damage)},
		{"label":"Movement","value":"%d · %s" % [unit.movement,movement_status],"tooltip":_resolved_stat_tooltip("Movement",definition.movement,unit.movement)},
		{"label":"Range","value":str(unit.attack_range),"tooltip":_resolved_stat_tooltip("Attack range",definition.attack_range,unit.attack_range)},
		{"label":"Vision","value":str(definition.vision_range),"tooltip":"Vision: %d cells" % definition.vision_range},
	]
	stats.append({"label":"Armour","value":"Armored" if "armored" in definition.tags else "—","tooltip":"Armour: armored vehicle classification. No separate numeric armour rating is defined." if "armored" in definition.tags else "Armour: no separate armour rating is defined for this unit."})
	if definition.detection_range>0: stats.append({"label":"Detection","value":str(definition.detection_range),"tooltip":"Detection: %d cells" % definition.detection_range})
	return stats

func _resolved_stat_tooltip(label: String,base_value: int,effective_value: int) -> String:
	var text:="%s: %d\nBase: %d" % [label,effective_value,base_value]
	if effective_value!=base_value: text+="\nRuntime modifiers: %s%d" % ["+" if effective_value>base_value else "",effective_value-base_value]
	return text

func _unit_status_presentations(unit: GameState.Unit,own_unit: bool) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var definition:=game_state.registry.unit(unit.definition_id)
	if "flying" in definition.tags: result.append({"label":"FLYING","tooltip":"Uses the unit's authored flying movement class.","color":"#315f78"})
	if "armored" in definition.tags: result.append({"label":"ARMORED","tooltip":"Armored vehicle profile.","color":"#4d5962"})
	if "road_builder" in definition.tags: result.append({"label":"ROAD BUILDER","tooltip":"Builds Ant roads along traversed cells.","color":"#5b4932"})
	if not own_unit: return result
	if "ant" in definition.tags:
		var connected:=rules.living_migration_rules.is_ant_connected(unit)
		result.append({"label":"CONNECTED" if connected else "DISCONNECTED","tooltip":"Connected to the Spider road network." if connected else "Outside the Spider road network for %d turn(s)." % unit.disconnected_turns,"color":"#376849" if connected else "#804840"})
	if unit.active_disease!=null: result.append({"label":unit.active_disease.definition_id.to_upper(),"tooltip":"Disease · %d turn(s) remaining" % unit.active_disease.remaining_turns,"color":"#7d3d66"})
	if unit.designation!=null: result.append({"label":"DESIGNATED","tooltip":"Receives bonus incoming damage for %d turn(s)." % unit.designation.remaining_turns,"color":"#8a4238"})
	if unit.deployed: result.append({"label":"DEPLOYED","tooltip":"Using deployed combat statistics.","color":"#5a536e"})
	if unit.counter_cooldown_remaining>0: result.append({"label":"COUNTER %d" % unit.counter_cooldown_remaining,"tooltip":"Counter cooldown remaining.","color":"#66553a"})
	else: result.append({"label":"COUNTER READY","tooltip":"Counter stance is available.","color":"#376849"})
	if unit.remaining_lifetime_turns>0: result.append({"label":"LIFETIME %d" % unit.remaining_lifetime_turns,"tooltip":"Finite lifespan in owner turns.","color":"#66553a"})
	return result

func _queued_combat_text(unit: GameState.Unit) -> String:
	if not game_state.combat_orders.intents.has(unit.id): return ""
	var intent: CombatIntent=game_state.combat_orders.intents[unit.id]
	var option:=game_state.registry.combat_option(intent.option_id)
	var text:="QUEUED %s" % (option.display_name.to_upper() if option!=null else intent.option_id.to_upper())
	if intent.option_id=="attack": text+="  →  "+_combat_target_display_name(intent.target_id)
	return text+"\nResolves after all players finish movement."

func _site_interact_ui(site_id: int,interaction_id: String,unit_id: int) -> void:
	if _human_action_blocked(): return
	var result:=_network_command(CommandDispatcher.SITE_INTERACTION,{"site_id":site_id,"interaction_id":interaction_id,"unit_id":unit_id}) if network_session!=null else rules.try_site_interaction(_action_actor(),site_id,interaction_id,unit_id)
	_feedback(result.reason)
	notification_feed.post(result.reason,StrategicNotificationFeed.Severity.SUCCESS if result.success else StrategicNotificationFeed.Severity.WARNING,
		game_state.world_sites[site_id].cell_id if game_state.world_sites.has(site_id) else -1)
	_refresh_display()

func _populate_pillar_panel(pillar: GameState.Structure,can_act: bool) -> void:
	var status:="SUPPLIED" if pillar.pillar_state.supplied else "ISOLATED"
	unit_label.text += "\nIntegrity: %d/%d | %s\nMaintenance: %s" % [pillar.pillar_state.integrity,
		pillar.pillar_state.max_integrity,status,"paid" if pillar.pillar_state.maintenance_paid else "NEGLECTED"]
	if pillar.pillar_state.integrity*3<=pillar.pillar_state.max_integrity: unit_label.text+="\nWARNING: Integrity is critically low."
	unit_label.text += "\nDistrict cells:"
	for slot: Dictionary in rules.baumeister_rules.district_cells(pillar.id):
		var district: DistrictState=game_state.baumeister.districts.get(int(slot.district_id)) as DistrictState
		var detail: String=String(slot.status).replace("_"," ")
		if district!=null: detail+=" (%s %d/%d)" % [game_state.registry.district(district.definition_id).display_name,district.construction_progress,district.required_turns]
		unit_label.text += "\n  Cell %d: %s" % [slot.cell_id,detail]
		if can_act and slot.status=="available":
			for district_id: String in ContentRegistry._sorted_keys(game_state.registry.districts):
				var error:=rules.baumeister_rules.district_error(pillar.controller_id,pillar.id,slot.cell_id,district_id)
				var district_definition:=game_state.registry.district(district_id)
				_action_button("Cell %d: Build %s — %s — %d turns" % [slot.cell_id,district_definition.display_name,_resource_record(district_definition.costs),district_definition.construction_turns],
					_build_district_ui.bind(pillar.id,slot.cell_id,district_id),StrategicTooltip.district(district_definition),error)
		elif can_act and district!=null and district.completed:
			var district_definition:=game_state.registry.district(district.definition_id)
			if "heals_biological" in district_definition.tags or "repairs_vehicle" in district_definition.tags:
				for target: GameState.Unit in game_state.units.values():
					if target.controller_id==pillar.controller_id and target.hp<target.max_hp and game_state.grid.distance(district.cell_id,target.cell_id)<=1:
						var category_ok:=("heals_biological" in district_definition.tags and "biological" in game_state.registry.unit(target.definition_id).tags) or ("repairs_vehicle" in district_definition.tags and "vehicle" in game_state.registry.unit(target.definition_id).tags)
						if category_ok: _action_button("%s: support %s" % [district_definition.display_name,target.unit_type],_district_support_ui.bind(district.id,target.id))
	var connections:=0
	for bridge: BridgeState in game_state.baumeister.bridges.values():
		if bridge.endpoint_a==pillar.id or bridge.endpoint_b==pillar.id: connections+=1
	unit_label.text += "\nBridge connections: %d" % connections
	var research_state:=game_state.players[pillar.controller_id].research
	if research_state.current_technology_id.is_empty() and can_act:
		for technology_id: String in rules.available_technologies(pillar.controller_id):
			_action_button("Research: "+game_state.registry.technology(technology_id).display_name,_start_research_ui.bind(technology_id))
	elif not research_state.current_technology_id.is_empty():
		var technology:=game_state.registry.technology(research_state.current_technology_id)
		unit_label.text += "\nResearch: %s %d/%d" % [technology.display_name,research_state.accumulated_progress,technology.research_cost]
	if can_act:
		var engineer:=_available_engineer(pillar.controller_id,pillar.cell_id)
		if engineer!=null:
			var candidates:=rules.baumeister_rules.candidate_pillar_cells(pillar.controller_id,engineer.id,pillar.id)
			unit_label.text += "\nExpansion candidates: %d" % candidates.size()
			_action_button("Build pillar + bridge (planning mode)",_begin_pillar_mode.bind(pillar.id),"Choose a highlighted destination to preview and begin the bridge project.","No legal destination." if candidates.is_empty() else "")
			if pillar.hp<pillar.max_hp or pillar.pillar_state.integrity<pillar.pillar_state.max_integrity:
				_action_button("Repair pillar",_repair_pillar_ui.bind(engineer.id,pillar.id))
		_action_button("Supply overlay: "+("ON" if supply_overlay_visible else "OFF"),_toggle_supply_overlay,"Show supplied Pillars and operational bridge cells.")

func _available_engineer(controller_id: int,cell_id: int) -> GameState.Unit:
	var candidates: Array[GameState.Unit]=[]
	for unit: GameState.Unit in game_state.units.values():
		if unit.controller_id==controller_id and "engineer" in game_state.registry.unit(unit.definition_id).tags and not unit.moved and not unit.attacked and game_state.grid.distance(unit.cell_id,cell_id)<=1: candidates.append(unit)
	candidates.sort_custom(func(a: GameState.Unit,b: GameState.Unit)->bool: return a.id<b.id)
	return candidates[0] if not candidates.is_empty() else null

func _apply_ui_result(result: GameRules.Result,cell_id: int=-1,entity_id: int=-1) -> void:
	_feedback(result.reason)
	if notification_feed!=null:
		notification_feed.post(result.reason,StrategicNotificationFeed.Severity.SUCCESS if result.success else StrategicNotificationFeed.Severity.WARNING,cell_id,entity_id)
		_layout_hud()
	_refresh_display()

func _choose_branch(spider_id: int,branch_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.CHOOSE_NURSERY,{"spider_id":spider_id,"branch_id":branch_id}) if network_session!=null else rules.choose_nursery(_action_actor(),spider_id,branch_id))
func _queue_recipe(spider_id: int,recipe_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.QUEUE_BIOLOGICAL_PRODUCTION,{"spider_id":spider_id,"recipe_id":recipe_id}) if network_session!=null else rules.queue_biological_production(_action_actor(),spider_id,recipe_id))
func _build_internal(spider_id: int,building_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.START_INTERNAL_CONSTRUCTION,{"spider_id":spider_id,"building_id":building_id}) if network_session!=null else rules.start_internal_construction(_action_actor(),spider_id,building_id))
func _start_spider(spider_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.START_SPIDER_CONSTRUCTION,{"spider_id":spider_id}) if network_session!=null else rules.start_spider_construction(_action_actor(),spider_id))
func _start_research_ui(technology_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.START_RESEARCH,{"technology_id":technology_id}) if network_session!=null else rules.start_research(_action_actor(),technology_id))
func _transform_selected(unit_id: int,outcome_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.TRANSFORM_CATERPILLAR,{"unit_id":unit_id,"outcome_id":outcome_id}) if network_session!=null else rules.transform_caterpillar(_action_actor(),unit_id,outcome_id))
func _submit_combat_option(unit_id: int,option_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.COMBAT_INTENT,{"unit_id":unit_id,"option_id":option_id}) if network_session!=null else rules.submit_combat_intent(_view_controller_id(),unit_id,option_id))
func _clear_combat_option(unit_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.CLEAR_COMBAT_INTENT,{"unit_id":unit_id}) if network_session!=null else rules.clear_combat_intent(_view_controller_id(),unit_id))

func _combat_target_display_name(target_id: int) -> String:
	var target:=game_state.combat_target(target_id)
	if target==null: return "Unavailable"
	if target is GameState.Unit: return game_state.registry.unit(target.definition_id).display_name
	if target is GameState.Structure: return game_state.registry.structure(target.definition_id).display_name
	if target is WorldSiteState: return game_state.registry.world_site(target.definition_id).display_name
	return "Target #%d" % target_id
func _lay_larva_auto(unit_id: int) -> void:
	var unit: GameState.Unit=game_state.units.get(unit_id) as GameState.Unit; var candidates: Array[int]=[]
	if unit!=null:
		for cell_id: int in grid.get_cells_within_distance(unit.cell_id,rules.living_migration_rules.config_for(unit.controller_id).larva_interaction_range):
			if game_state.is_water_cell(cell_id): candidates.append(cell_id)
	candidates.sort()
	var result:=GameRules.Result.new(false,"No legal water cell is in range.")
	if not candidates.is_empty(): result=_network_command(CommandDispatcher.LAY_LARVA,{"unit_id":unit_id,"cell_id":candidates[0]}) if network_session!=null else rules.lay_larva(_action_actor(),unit_id,candidates[0])
	_apply_ui_result(result)
func _consume_vegetation_auto(unit_id: int) -> void:
	var unit: GameState.Unit=game_state.units.get(unit_id) as GameState.Unit; var candidates: Array[int]=[]
	if unit!=null:
		for cell_id: int in grid.get_cells_within_distance(unit.cell_id,1):
			if not game_state.is_water_cell(cell_id) and game_state.living_migration.terrain_at(cell_id).kind==TerrainConsumptionState.Kind.FRESH: candidates.append(cell_id)
	candidates.sort()
	var result:=GameRules.Result.new(false,"No eligible vegetation is in range.")
	if not candidates.is_empty(): result=_network_command(CommandDispatcher.CONSUME,{"unit_id":unit_id,"source_kind":"vegetation","source_id":candidates[0]}) if network_session!=null else rules.consume(_action_actor(),unit_id,"vegetation",candidates[0])
	_apply_ui_result(result)
func _consume_caterpillar_corpse(unit_id: int,corpse_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.CONSUME,{"unit_id":unit_id,"source_kind":"corpse","source_id":corpse_id}) if network_session!=null else rules.consume(_action_actor(),unit_id,"corpse",corpse_id))
func _select_disease_ui(unit_id: int,disease_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.SELECT_DISEASE,{"mite_id":unit_id,"disease_id":disease_id}) if network_session!=null else rules.select_disease(_action_actor(),unit_id,disease_id))
func _consume_corpse_ui(unit_id: int,corpse_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.CONSUME_CORPSE,{"ant_id":unit_id,"corpse_id":corpse_id}) if network_session!=null else rules.try_consume_corpse(_action_actor(),unit_id,corpse_id))
func _build_district_ui(pillar_id: int,cell_id: int,district_id: String) -> void: _apply_ui_result(_network_command(CommandDispatcher.BUILD_DISTRICT,{"pillar_id":pillar_id,"cell_id":cell_id,"district_id":district_id}) if network_session!=null else rules.build_district(_action_actor(),pillar_id,cell_id,district_id))
func _expand_ui(engineer_id: int,pillar_id: int,cell_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.START_BRIDGE_EXTENSION,{"engineer_id":engineer_id,"pillar_id":pillar_id,"cell_id":cell_id}) if network_session!=null else rules.start_bridge_extension(_action_actor(),engineer_id,pillar_id,cell_id))
func _toggle_deployment_ui(unit_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.TOGGLE_DEPLOYMENT,{"unit_id":unit_id}) if network_session!=null else rules.toggle_deployment(_action_actor(),unit_id))
func _heal_ui(source_id: int,target_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.HEAL_UNIT,{"healer_id":source_id,"target_id":target_id}) if network_session!=null else rules.heal_unit(_action_actor(),source_id,target_id))
func _repair_unit_ui(source_id: int,target_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.REPAIR_UNIT,{"engineer_id":source_id,"target_id":target_id}) if network_session!=null else rules.repair_unit(_action_actor(),source_id,target_id))
func _repair_bridge_ui(source_id: int,bridge_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.REPAIR_BRIDGE,{"engineer_id":source_id,"bridge_id":bridge_id}) if network_session!=null else rules.repair_bridge(_action_actor(),source_id,bridge_id))
func _repair_pillar_ui(source_id: int,pillar_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.REPAIR_STRUCTURE,{"engineer_id":source_id,"structure_id":pillar_id}) if network_session!=null else rules.repair_structure(_action_actor(),source_id,pillar_id))
func _designate_ui(source_id: int,target_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.DESIGNATE_TARGET,{"commander_id":source_id,"target_id":target_id}) if network_session!=null else rules.designate_target(_action_actor(),source_id,target_id))
func _district_support_ui(district_id: int,target_id: int) -> void: _apply_ui_result(_network_command(CommandDispatcher.DISTRICT_SUPPORT,{"district_id":district_id,"target_id":target_id}) if network_session!=null else rules.district_support(_action_actor(),district_id,target_id))

func _begin_road_mode(worker_id: int) -> void:
	_set_input_mode(StrategicInputMode.Kind.ROAD,worker_id,"Road mode: choose highlighted cells. Right click or Escape cancels.")

func _begin_pillar_mode(pillar_id: int) -> void:
	_set_input_mode(StrategicInputMode.Kind.PILLAR,pillar_id,"Pillar planning: choose a highlighted destination. Orange shows construction.")

func _begin_target_mode(mode: int,source_id: int) -> void:
	_set_input_mode(mode,source_id,"%s mode: choose a highlighted target." % StrategicInputMode.display_name(mode))

func _toggle_supply_overlay() -> void:
	supply_overlay_visible=not supply_overlay_visible; _refresh_display()

func _deploy_job_auto(spider_id: int,job_index: int,outcome_id: String) -> void:
	var deployed_id:="living_caterpillar" if game_state.units[spider_id].spider_state.nursery_jobs[job_index].recipe_id=="caterpillar_brood" else outcome_id
	var cells:=rules.living_migration_rules.deployment_cells(_action_actor(),spider_id,deployed_id)
	var cell_id:=cells[0] if not cells.is_empty() else -1
	_apply_ui_result(_network_command(CommandDispatcher.DEPLOY_BIOLOGICAL,{"spider_id":spider_id,"job_index":job_index,"outcome_id":outcome_id,"cell_id":cell_id}) if network_session!=null else rules.deploy_biological(_action_actor(),spider_id,job_index,outcome_id,cell_id))

func _deploy_mite_auto(spider_id: int) -> void:
	var cells:=rules.living_migration_rules.deployment_cells(_action_actor(),spider_id,"mite")
	var cell_id:=cells[0] if not cells.is_empty() else -1
	_apply_ui_result(_network_command(CommandDispatcher.DEPLOY_MITE,{"spider_id":spider_id,"cell_id":cell_id}) if network_session!=null else rules.deploy_mite(_action_actor(),spider_id,cell_id))

func _deploy_spider_auto(spider_id: int) -> void:
	var cells:=rules.living_migration_rules.deployment_cells(_action_actor(),spider_id,"living_spider")
	var cell_id:=cells[0] if not cells.is_empty() else -1
	_apply_ui_result(_network_command(CommandDispatcher.DEPLOY_SPIDER,{"spider_id":spider_id,"cell_id":cell_id}) if network_session!=null else rules.deploy_spider(_action_actor(),spider_id,cell_id))

func _build_road_auto(worker_id: int) -> void:
	var worker: GameState.Unit=game_state.units[worker_id]; var path: Array[int]=[]; var previous:=worker.cell_id
	var roads: Dictionary=game_state.living_migration.roads.get(worker.controller_id,{}).duplicate()
	for _step in range(rules.living_migration_rules.config_for(worker.controller_id).road_segments_per_turn-worker.road_segments_built_this_turn):
		var candidates: Array[int]=[]
		for cell_id: int in grid.get_neighbors(previous):
			if not roads.has(cell_id) and not game_state.is_cell_blocked(cell_id): candidates.append(cell_id)
		candidates.sort()
		if candidates.is_empty(): break
		previous=candidates[0]; path.append(previous); roads[previous]=true
	_apply_ui_result(_network_command(CommandDispatcher.BUILD_ROAD,{"worker_id":worker_id,"path":path}) if network_session!=null else rules.try_build_road(_action_actor(),worker_id,path))

func _update_preview() -> void:
	var mouse:=get_viewport().get_mouse_position()
	var viewport_size:=get_viewport().get_visible_rect().size
	if _hover_query_valid and mouse==_hover_query_mouse and camera.global_transform==_hover_query_camera and viewport_size==_hover_query_viewport: return
	_hover_query_valid=true; _hover_query_mouse=mouse; _hover_query_camera=camera.global_transform; _hover_query_viewport=viewport_size
	update_hover_at(mouse)

func update_hover_at(mouse: Vector2) -> void:
	var destination: int = NONE
	var over_debug: bool = world_debug_panel.visible and world_debug_panel.get_global_rect().has_point(mouse)
	var over_ui: bool = hud_panel.get_global_rect().has_point(mouse) or top_bar.get_global_rect().has_point(mouse) or (action_panel.visible and action_panel.get_global_rect().has_point(mouse)) or (notification_feed.visible and notification_feed.get_global_rect().has_point(mouse)) or (strategic_panel.visible and strategic_panel.get_global_rect().has_point(mouse)) or (coordinate_label.visible and coordinate_label.get_global_rect().has_point(mouse)) or (management_panel.visible and management_panel.get_global_rect().has_point(mouse)) or over_debug
	if not over_ui:
		destination = pick_cell(mouse)
	if destination == hover_cell:
		return
	hover_cell = destination
	if world_debug_panel.visible:
		world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)
	preview_path.clear()
	attack_preview_label.text = ""
	if input_mode in [StrategicInputMode.Kind.PILLAR,StrategicInputMode.Kind.BRIDGE] and game_state.structures.has(selected_structure_id) and road_highlights.has(destination):
		var source: GameState.Structure=game_state.structures[selected_structure_id]
		preview_path=rules.baumeister_rules.bridge_path(source.cell_id,destination,_action_actor())
		attack_preview_label.text="Bridge plan: %d edges | %s | %d owner turns" % [maxi(0,preview_path.size()-1),
			_resource_record(rules.baumeister_rules.bridge_cost(_action_actor(),source.cell_id,destination)),
			rules.baumeister_rules.config_for(_action_actor()).bridge_construction_turns]
	var target_entity := game_state.entity_at(destination)
	if target_entity==null: target_entity=game_state.site_at(destination)
	if target_entity != null and target_entity is GameState.Unit:
		var preview: GameRules.Result = rules.preview_attack(_action_actor(), selected_unit_id, target_entity.id)
		if preview.success:
			var outcome: String = "LETHAL" if preview.killed else "survives"
			attack_preview_label.text = "%s: %d damage\nHP %d -> %d | %s" % [
				target_entity.unit_type, preview.damage, target_entity.hp, preview.target_hp, outcome,
			]
	elif target_entity != null and target_entity is GameState.Structure:
		var preview_s: GameRules.Result = rules.preview_attack(_action_actor(), selected_unit_id, target_entity.id)
		if preview_s.success:
			attack_preview_label.text = "%s: %d damage\nHP %d -> %d | %s" % [
				target_entity.structure_type, preview_s.damage, target_entity.hp, preview_s.target_hp, "LETHAL" if preview_s.killed else "survives",
			]
	elif target_entity != null and target_entity is WorldSiteState:
		var preview_site: GameRules.Result=rules.preview_attack(_action_actor(),selected_unit_id,target_entity.id)
		if preview_site.success:
			var site_definition:=game_state.registry.world_site(target_entity.definition_id)
			attack_preview_label.text="%s: %d damage\nHP %d -> %d | %s" % [site_definition.display_name,preview_site.damage,target_entity.hp,preview_site.target_hp,"DESTROYED" if preview_site.killed else "stands"]
	if reachable_tiles.has(destination):
		preview_path = rules.path_to(_action_actor(), selected_unit_id, destination)
	attack_preview_label.visible=not attack_preview_label.text.is_empty()
	_refresh_tile_materials()

func _refresh_tile_materials() -> void:
	_sync_ant_road_overlay()
	_sync_attack_order_overlay()
	for tile: MeshInstance3D in tiles.values():
		tile.visible = false
	var active: Dictionary = {}
	for cell_id: int in game_state.living_migration.terrain:
		if not _can_view_cell(cell_id): continue
		var terrain_state: TerrainConsumptionState=game_state.living_migration.terrain[cell_id]
		if terrain_state.kind==TerrainConsumptionState.Kind.DEPLETED: active[cell_id]=depleted_material
		elif terrain_state.kind==TerrainConsumptionState.Kind.REGROWING: active[cell_id]=regrowing_material
	if input_mode==StrategicInputMode.Kind.ROAD or supply_overlay_visible:
		for unit: GameState.Unit in game_state.units.values():
			var tags:=game_state.registry.unit(unit.definition_id).tags
			if not _can_view_entity(unit.id) or "ant" not in tags: continue
			if not _connection_overlay_cells.has(unit.controller_id):
				_connection_overlay_cells[unit.controller_id]=rules.living_migration_rules.connected_cell_set(unit.controller_id)
			if "connection_independent" in tags or _connection_overlay_cells[unit.controller_id].has(unit.cell_id): active[unit.cell_id]=connected_material
	for district: DistrictState in game_state.baumeister.districts.values():
		if _is_view_ally(district.controller_id) or _can_view_cell(district.cell_id): active[district.cell_id]=connected_material if district.completed else road_material
	for bridge: BridgeState in game_state.baumeister.bridges.values():
		for cell_id: int in bridge.path:
			if _is_view_ally(bridge.controller_id) or _can_view_cell(cell_id): active[cell_id]=(connected_material if supply_overlay_visible else road_material) if bridge.operational else (attack_material if bridge.hp==0 else road_material)
	for id: int in reachable_tiles + recruit_highlights:
		active[id] = reachable_material
	for id: int in road_highlights: active[id]=road_material
	for id: int in site_highlights: active[id]=interaction_material
	if input_mode==StrategicInputMode.Kind.HEAL and game_state.units.has(mode_source_id):
		var source: GameState.Unit=game_state.units[mode_source_id]
		for target: GameState.Unit in game_state.units.values():
			if target.controller_id==source.controller_id and target.hp<target.max_hp and "biological" in game_state.registry.unit(target.definition_id).tags and grid.distance(source.cell_id,target.cell_id)<=1: active[target.cell_id]=heal_material
	elif input_mode==StrategicInputMode.Kind.REPAIR and game_state.units.has(mode_source_id):
		var source: GameState.Unit=game_state.units[mode_source_id]
		for target: GameState.Unit in game_state.units.values():
			if target.controller_id==source.controller_id and target.hp<target.max_hp and "vehicle" in game_state.registry.unit(target.definition_id).tags and grid.distance(source.cell_id,target.cell_id)<=1: active[target.cell_id]=repair_material
		for target: GameState.Structure in game_state.structures.values():
			if target.controller_id==source.controller_id and (target.hp<target.max_hp or (target.pillar_state!=null and target.pillar_state.integrity<target.pillar_state.max_integrity)) and grid.distance(source.cell_id,target.cell_id)<=1: active[target.cell_id]=repair_material
	elif input_mode==StrategicInputMode.Kind.DESIGNATE and game_state.units.has(mode_source_id):
		var source: GameState.Unit=game_state.units[mode_source_id]
		var target_range:=rules.baumeister_rules.config_for(source.controller_id).designation_range
		for target in game_state.units.values()+game_state.structures.values():
			if _can_view_entity(target.id) and game_state.relationships.is_hostile(source.controller_id,target.controller_id) and grid.distance(source.cell_id,target.cell_id)<=target_range: active[target.cell_id]=designation_material
	if supply_overlay_visible:
		for structure: GameState.Structure in game_state.structures.values():
			if (_is_view_ally(structure.controller_id) or _can_view_entity(structure.id)) and structure.pillar_state!=null and structure.pillar_state.supplied: active[structure.cell_id]=connected_material
	for id: int in preview_path:
		active[id] = path_material
	for id: int in attack_tiles:
		active[id] = attack_material
	if hover_cell != NONE and not active.has(hover_cell):
		active[hover_cell] = hover_material
	if selected != NONE:
		active[selected] = selected_material
	for id: int in active:
		if not tiles.has(id):
			var tile := MeshInstance3D.new()
			tile.mesh = PlanetSurface.polygon_mesh(grid.get_cell(id), planet_radius + 0.04, terrain_surface)
			add_child(tile)
			tiles[id] = tile
		tiles[id].material_override = active[id]
		tiles[id].visible = true

func _sync_ant_road_overlay() -> void:
	if ant_road_overlay==null: return
	var visible: Dictionary[int,int]={}
	for controller_id: int in game_state.living_migration.roads:
		for cell_id: int in game_state.living_migration.road_cells(controller_id):
			if _is_view_ally(controller_id) or _can_view_cell(cell_id): visible[cell_id]=controller_id
	ant_road_overlay.sync_roads(visible)

func _sync_attack_order_overlay() -> void:
	if attack_order_overlay!=null: attack_order_overlay.sync_orders(game_state,_view_controller_id())

func _update_label() -> void:
	var status: String = "none" if selected == NONE else "Cell %d" % selected
	coordinate_label.text = "Selected: %s\nWASD/arrows: pan | Q/E: yaw\nLMB drag: pan | MMB: orbit | Wheel: zoom\nF: focus | Home: reset\nF1 grid | F2 pentagons | F3 centers | F4 IDs\nF6 world panel | F7 world view | F8 camera | F9 population | F10 intel" % status
	if visibility_omniscient: coordinate_label.text+="\nINTELLIGENCE DEBUG: OMNISCIENT"
	if population_debug_visible: coordinate_label.text+="\nPopulation: %d sites | %d groups | %s..." % [population_result.site_records.size(),population_result.neutral_group_records.size(),population_result.fingerprint.left(12)]
	if camera_diagnostics:
		coordinate_label.text += "\nFocus %d %s\nYaw %.1f | Pitch %.1f | Distance %.2f\n%s | Entity %d | Follow %s" % [grid.find_cell(navigation.focus_direction), navigation.focus_direction, navigation.yaw, navigation.pitch, navigation.distance, navigation.zoom_band(), navigation.focused_entity, navigation.focused_entity != -1]

func _owner_color(owner_id: int) -> Color:
	if game_state==null or not game_state.controllers.has(owner_id): return Color("#9ca3a5")
	if game_state.controllers[owner_id].kind==ControllerState.NEUTRAL_AI:
		return Color("#dd6f6a") if owner_id in [51,52] else Color("#d8c66a")
	if game_state.players.has(owner_id) and game_state.players[owner_id].ownership_color.is_valid_html_color():
		return PlayerIdentity.color_for_hex(game_state.players[owner_id].ownership_color)
	var faction:=game_state.registry.faction(game_state.controllers[owner_id].faction_id)
	if faction==null: return Color("#9ca3a5")
	if faction.visual_theme_id=="blue": return Color("#75baff")
	if faction.visual_theme_id=="living_migration": return Color("#75c96b")
	if faction.visual_theme_id=="baumeister": return Color("#d7a94b")
	return Color("#f77e75")

func _build_start_suitability(player_ids: Array[int],faction_ids: Array[String]) -> Dictionary:
	var result:={}
	for index in range(player_ids.size()):
		var values: Array[float]=[]
		var faction_id:=faction_ids[index] if index<faction_ids.size() else ""
		for cell: PlanetWorldCellData in generated_planet.cell_world_data:
			var neighbor_quality:=0.0
			for neighbor_id: int in grid.get_neighbors(cell.cell_id):
				var neighbor:=generated_planet.get_cell(neighbor_id)
				neighbor_quality+=neighbor.fertility+(1.0-neighbor.terrain_roughness)
			neighbor_quality/=maxf(1.0,float(grid.get_neighbors(cell.cell_id).size())*2.0)
			var score:=0.35*cell.fertility+0.25*(1.0-cell.terrain_roughness)+0.20*neighbor_quality
			if faction_id=="living_migration": score+=0.20*(cell.fertility*0.6+cell.effective_moisture*0.4)
			elif faction_id=="baumeister": score+=0.20*(1.0-cell.terrain_roughness)
			values.append(clampf(score,0.0,1.0))
		result[player_ids[index]]=values
	return result

func _duplicate_and_tint_material(material: Material, color: Color) -> Material:
	if material == null:
		return _material(color)
	var duplicate: Material = material.duplicate() as Material
	if duplicate is StandardMaterial3D:
		(duplicate as StandardMaterial3D).albedo_color = color
	elif duplicate is ShaderMaterial:
		var shader_material: ShaderMaterial = duplicate as ShaderMaterial
		if shader_material.shader != null:
			for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
				if uniform.name in ["albedo_color", "team_accent"]:
					shader_material.set_shader_parameter(uniform.name, color)
	return duplicate

func _player_overview_text() -> String:
	if game_state==null: return ""
	var lines:=PackedStringArray(["PLAYERS"])
	var ids: Array[int]=[]; ids.assign(game_state.players.keys()); ids.sort()
	for player_id: int in ids:
		var player: PlayerState=game_state.players[player_id]
		var faction:=game_state.registry.faction(player.faction_id)
		var slot:=game_state.turn_state.order.find(player_id)
		var markers:=PackedStringArray()
		if game_state.active_player==player_id and not game_state.turn_state.neutral_phase and game_state.winner_id==0: markers.append("ACTIVE")
		markers.append("ELIMINATED" if player.eliminated else "ALIVE")
		if not player.connected: markers.append("DISCONNECTED")
		lines.append("P%d %s · %s · %s · %s" % [player_id,player.player_name,
			PlayerIdentity.color_name_for_slot(slot),faction.display_name if faction!=null else player.faction_id," / ".join(markers)])
	return "\n".join(lines)

func _apply_team_accent(root: Node, owner_id: int) -> void:
	if root is MeshInstance3D:
		var mesh_instance: MeshInstance3D = root as MeshInstance3D
		var color: Color = _owner_color(owner_id)
		if "HX_TeamAccent" in str(mesh_instance.name):
			mesh_instance.material_override = _duplicate_and_tint_material(mesh_instance.material_override, color)
		elif mesh_instance.mesh != null:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var material: Material = mesh_instance.get_active_material(surface)
				if material != null and "HX_TeamAccent" in material.resource_name:
					mesh_instance.set_surface_override_material(surface, _duplicate_and_tint_material(material, color))
	for child: Node in root.get_children():
		_apply_team_accent(child, owner_id)

func _begin_recruit(kind: String, hq_id: int) -> void:
	if _human_action_blocked():
		return
	var error: String = rules.recruit_error(_action_actor(), hq_id, kind)
	if not error.is_empty():
		_feedback(error)
		return
	recruit_highlights = rules.recruit_destinations(_action_actor(), hq_id, kind)
	if recruit_highlights.is_empty():
		_feedback("No free adjacent tiles.")
		return
	placement_mode = true
	input_mode=StrategicInputMode.Kind.RECRUIT
	recruit_choice = kind
	recruit_hq_id = hq_id
	preview_path.clear()
	attack_preview_label.text = ""
	_feedback("Place %s: left-click green tile. Right-click / Escape cancels." %
		game_state.registry.unit(UnitTypes.definition_id(kind)).display_name)
	_refresh_tile_materials()

func _queue_ai_turn() -> void:
	if _ai_running or game_state.winner_id != 0: return
	if game_state.turn_state.neutral_phase:
		_ai_running=true
		_start_neutral_phase.call_deferred(_ai_token)
		return
	if player_controllers.get(game_state.active_player,"") != "AI":
		return
	_ai_running = true
	_start_ai_turn.call_deferred(_ai_token, game_state.active_player)

func _start_ai_turn(token: int, actor: int) -> void:
	var budget: int = maxi(8, game_state.units.size() * 3)
	_run_ai_step(token,actor,0,budget)

func _run_ai_step(token: int,actor: int,attempts: int,budget: int) -> void:
	if token!=_ai_token or game_state.winner_id!=0 or game_state.active_player!=actor or player_controllers.get(actor,"")!="AI":
		_finish_ai_schedule(token); return
	var action: Dictionary=ai_agent.choose_action(game_state,rules,actor) if attempts<budget else {"type":"end"}
	var result: GameRules.Result
	match action.get("type","end"):
		"attack": result=_network_authoritative_command(actor,CommandDispatcher.ATTACK,{"attacker_id":action.attacker,"target_id":action.target}) if network_session!=null else rules.try_attack(actor,action.attacker,action.target)
		"move":
			result=_network_authoritative_command(actor,CommandDispatcher.MOVE,{"unit_id":action.unit,"destination":action.dest}) if network_session!=null else rules.try_move(actor,action.unit,action.dest)
			_present_move(action.unit,result)
		"recruit": result=_network_authoritative_command(actor,CommandDispatcher.RECRUIT,{"headquarters_id":action.hq_id,"unit_id":action.kind,"destination":action.dest}) if network_session!=null else rules.try_recruit(actor,action.hq_id,action.kind,action.dest)
		"lm_queue": result=_network_authoritative_command(actor,CommandDispatcher.QUEUE_BIOLOGICAL_PRODUCTION,{"spider_id":action.spider,"recipe_id":action.recipe}) if network_session!=null else rules.queue_biological_production(actor,action.spider,action.recipe)
		"lm_deploy": result=_network_authoritative_command(actor,CommandDispatcher.DEPLOY_BIOLOGICAL,{"spider_id":action.spider,"job_index":action.job,"outcome_id":action.outcome,"cell_id":action.dest}) if network_session!=null else rules.deploy_biological(actor,action.spider,action.job,action.outcome,action.dest)
		"lm_mite": result=_network_authoritative_command(actor,CommandDispatcher.DEPLOY_MITE,{"spider_id":action.spider,"cell_id":action.dest}) if network_session!=null else rules.deploy_mite(actor,action.spider,action.dest)
		"lm_internal": result=_network_authoritative_command(actor,CommandDispatcher.START_INTERNAL_CONSTRUCTION,{"spider_id":action.spider,"building_id":action.building}) if network_session!=null else rules.start_internal_construction(actor,action.spider,action.building)
		"lm_road": result=_network_authoritative_command(actor,CommandDispatcher.BUILD_ROAD,{"worker_id":action.worker,"path":action.path}) if network_session!=null else rules.try_build_road(actor,action.worker,action.path)
		"bm_district": result=_network_authoritative_command(actor,CommandDispatcher.BUILD_DISTRICT,{"pillar_id":action.pillar,"cell_id":action.cell,"district_id":action.district}) if network_session!=null else rules.build_district(actor,action.pillar,action.cell,action.district)
		"bm_expand": result=_network_authoritative_command(actor,CommandDispatcher.START_BRIDGE_EXTENSION,{"engineer_id":action.engineer,"pillar_id":action.pillar,"cell_id":action.cell}) if network_session!=null else rules.start_bridge_extension(actor,action.engineer,action.pillar,action.cell)
		"bm_repair_bridge": result=_network_authoritative_command(actor,CommandDispatcher.REPAIR_BRIDGE,{"engineer_id":action.engineer,"bridge_id":action.bridge}) if network_session!=null else rules.repair_bridge(actor,action.engineer,action.bridge)
		"bm_repair_pillar": result=_network_authoritative_command(actor,CommandDispatcher.REPAIR_STRUCTURE,{"engineer_id":action.engineer,"structure_id":action.pillar}) if network_session!=null else rules.repair_structure(actor,action.engineer,action.pillar)
		"bm_deploy": result=_network_authoritative_command(actor,CommandDispatcher.TOGGLE_DEPLOYMENT,{"unit_id":action.unit}) if network_session!=null else rules.toggle_deployment(actor,action.unit)
		"research": result=_network_authoritative_command(actor,CommandDispatcher.START_RESEARCH,{"technology_id":action.technology}) if network_session!=null else rules.start_research(actor,action.technology)
		"site": result=_network_authoritative_command(actor,CommandDispatcher.SITE_INTERACTION,{"site_id":action.site,"interaction_id":action.interaction,"unit_id":action.unit}) if network_session!=null else rules.try_site_interaction(actor,action.site,action.interaction,action.unit)
		_: result=_network_authoritative_command(actor,CommandDispatcher.END_TURN,{}) if network_session!=null else rules.try_end_turn(actor)
	ai_agent.record_result(action,result.success); clear_selection()
	_feedback("Player %d movement activity..." % actor if action.get("type","end")!="end" else "Player %d movement phase complete." % actor)
	_wait_ai_step(token,actor,attempts+1,budget)

func _wait_ai_step(token: int,actor: int,attempts: int,budget: int) -> void:
	if token!=_ai_token: return
	if is_presenting():
		get_tree().process_frame.connect(_wait_ai_step.bind(token,actor,attempts,budget),CONNECT_ONE_SHOT); return
	if game_state.active_player!=actor or game_state.winner_id!=0:
		_finish_ai_schedule(token); return
	var continuation:=_run_ai_step.bind(token,actor,attempts,budget)
	if DisplayServer.get_name()=="headless" or _ai_delay<=0.0: get_tree().process_frame.connect(continuation,CONNECT_ONE_SHOT)
	else: get_tree().create_timer(_ai_delay).timeout.connect(continuation,CONNECT_ONE_SHOT)

func _finish_ai_schedule(token: int) -> void:
	if token!=_ai_token: return
	_ai_running=false; _queue_ai_turn()

func _start_neutral_phase(token: int) -> void:
	notification_feed.post("Neutral activity begins.",StrategicNotificationFeed.Severity.INFO)
	var controller_ids: Array[int]=[]
	for controller_id: int in game_state.controllers:
		if game_state.controllers[controller_id].kind==ControllerState.NEUTRAL_AI: controller_ids.append(controller_id)
	controller_ids.sort()
	_run_neutral_step(token,controller_ids,0)

func _run_neutral_step(token: int,controller_ids: Array[int],index: int) -> void:
	if token!=_ai_token or not game_state.turn_state.neutral_phase: return
	if index<controller_ids.size():
		var controller_id:=controller_ids[index]
		if network_session!=null:
			for action: Dictionary in neutral_agent.choose_actions(game_state,controller_id):
				if action.type=="attack": _network_authoritative_command(controller_id,CommandDispatcher.ATTACK,{"attacker_id":action.attacker,"target_id":action.target})
				elif action.type=="move": _network_authoritative_command(controller_id,CommandDispatcher.MOVE,{"unit_id":action.unit,"destination":action.dest})
		else: neutral_agent.execute_actions(game_state,controller_id)
		_refresh_display()
		get_tree().process_frame.connect(_run_neutral_step.bind(token,controller_ids,index+1),CONNECT_ONE_SHOT)
		return
	if token==_ai_token and game_state.turn_state.neutral_phase:
		var result:=rules.finish_neutral_phase()
		if network_session!=null and result.success: network_session.publish_authoritative_update()
		_feedback(result.reason)
		notification_feed.post("Neutral activity complete.",StrategicNotificationFeed.Severity.INFO)
	_ai_running=false
	_refresh_display()
	_queue_ai_turn()

func handle_recruit_click(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if not placement_mode or not game_state.controllers.has(_action_actor()) or game_state.controllers[_action_actor()].kind != ControllerState.HUMAN:
		return
	var destination: int = pick_cell(screen_position)
	var result: GameRules.Result = _network_command(CommandDispatcher.RECRUIT,{"headquarters_id":recruit_hq_id,"unit_id":recruit_choice,"destination":destination}) if network_session!=null else rules.try_recruit(_action_actor(), recruit_hq_id, recruit_choice, destination)
	if result.success:
		_cancel_recruit(false)
		_refresh_display()
	_feedback(result.reason)

func _cancel_recruit(show_feedback: bool = true) -> void:
	cancel_input_mode(show_feedback)

func is_presenting() -> bool:
	for view: EntityView in unit_views.values():
		if view.moving:
			return true
	return false

func _human_action_blocked() -> bool:
	if privacy_overlay!=null and privacy_overlay.visible: return true
	if network_session!=null and network_session.status!=NetworkSession.Status.ACTIVE:
		_feedback("Waiting for all network players to finish loading."); return true
	var controller:=_view_controller_id()
	if game_state.turn_state.neutral_phase or not game_state.controllers.has(controller) or game_state.controllers[controller].kind != ControllerState.HUMAN or not game_state.turn_state.can_act(controller):
		return true
	if is_presenting():
		_feedback("Wait for movement to finish.")
		return true
	return false

func _present_move(unit_id: int, result: GameRules.Result) -> void:
	if result.success and animate_movement and unit_views.has(unit_id):
		unit_views[unit_id].play_path(result.path, grid, SURFACE_OFFSET if unit_views[unit_id].grounded else 0.28)

func _focus_selected() -> void:
	var id := selected_unit_id if selected_unit_id != -1 else selected_structure_id
	if not unit_views.has(id): return
	navigation.focused_entity = id
	navigation.focus(unit_views[id].position.normalized())

func focus_cell(id: int, immediate: bool = false) -> void:
	if grid.contains(id): navigation.focus(grid.get_cell(id).up, immediate)

func _update_camera_transform(_delta: float) -> void:
	navigation.apply_transform()

func pick_selectable_cell(screen: Vector2) -> int:
	# Presentation-root bounds take priority over terrain, but only before its hit.
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var terrain_hit := terrain_surface.ray_hit(origin, ray)
	var nearest := origin.distance_to(terrain_hit) + 0.04 if terrain_hit != Vector3.ZERO else INF
	var result := grid.find_cell(terrain_hit.normalized()) if terrain_hit != Vector3.ZERO else NONE
	# The logical hex under the pointer is authoritative when it contains an
	# observed entity. Adjacent large models may overlap the ray visually, but
	# must not steal an intentional click on this occupied hex.
	if result!=NONE and _observed_entity_at_cell(result)!=null: return result
	for id: int in unit_views:
		var view: EntityView = unit_views[id]
		if not view.visible: continue
		var inverse := view.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_ray: Vector3 = inverse.basis * ray
		var bounds:=view.selectable_bounds()
		var hit: Variant = bounds.intersects_ray(local_origin, local_ray)
		if hit == null: continue
		var world_hit: Vector3 = view.global_transform * hit
		var depth := origin.distance_to(world_hit)
		if depth < nearest:
			nearest = depth
			result = game_state.units[id].cell_id if game_state.units.has(id) else game_state.structures[id].cell_id
	return result

func _debug_layer(mesh: ArrayMesh, color: Color) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.mesh = mesh
	layer.material_override = _material(color)
	add_child(layer)
	return layer

func _toggle_debug_geometry(layer: MeshInstance3D,centers: bool=false,pentagons: bool=false) -> void:
	if layer.mesh==null: layer.mesh=PlanetSurface.debug_mesh(grid,centers,pentagons,terrain_surface)
	layer.visible=not layer.visible

func _toggle_debug_labels() -> void:
	if debug_labels.get_child_count() == 0:
		for cell: PlanetCell in grid.cells:
			var label := Label3D.new()
			label.text = "%d / %d" % [cell.id, cell.neighbor_ids.size()]
			label.font_size = 24
			label.pixel_size = 0.009
			label.position = terrain_surface.sample_position(cell.up, 0.10)
			label.basis = Basis(cell.right, cell.forward, cell.up)
			label.no_depth_test = false
			debug_labels.add_child(label)
	debug_labels.visible = not debug_labels.visible

func rebuild_terrain() -> void:
	terrain_renderer.rebuild(generated_planet, terrain_config, _occupied_directions())
	terrain_surface = terrain_renderer.surface
	if ant_road_overlay!=null:
		ant_road_overlay.terrain=terrain_surface
		ant_road_overlay.sync_roads({})
	if attack_order_overlay!=null:
		attack_order_overlay.configure(grid,terrain_surface)
		_sync_attack_order_overlay()
	if fog_overlay!=null: fog_overlay.last_revision=-1
	navigation.surface = terrain_surface
	world_debug_view.terrain_surface = terrain_surface
	world_debug_view.set_world(generated_planet)
	for view: EntityView in unit_views.values(): view.terrain_surface = terrain_surface
	for tile: MeshInstance3D in tiles.values(): tile.free()
	tiles.clear()
	debug_outlines.mesh = PlanetSurface.debug_mesh(grid, false, false, terrain_surface) if debug_outlines.visible else null
	debug_centers.mesh = PlanetSurface.debug_mesh(grid, true, false, terrain_surface) if debug_centers.visible else null
	debug_pentagons.mesh = PlanetSurface.debug_mesh(grid, false, true, terrain_surface) if debug_pentagons.visible else null
	for label: Label3D in debug_labels.get_children():
		label.position = terrain_surface.sample_position(label.position.normalized(),0.10)
	set_world_debug_mode(world_debug_view.mode)
	_update_visibility_presentation(true)
	_refresh_display()

func _occupied_directions() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	if game_state==null or grid==null: return result
	for unit: GameState.Unit in game_state.units.values():
		result.append(grid.get_cell(unit.cell_id).center_direction)
	for structure: GameState.Structure in game_state.structures.values():
		result.append(grid.get_cell(structure.cell_id).center_direction)
	for site: WorldSiteState in game_state.world_sites.values():
		if site.definition_id=="village": result.append(grid.get_cell(site.cell_id).center_direction)
	return result
