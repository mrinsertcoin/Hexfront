class_name PlanetBoard
extends Node3D


const VisualMap = preload("res://scripts/view/visual_map.gd")
var visual_map: VisualMap = VisualMap.new()

const SURFACE_OFFSET: float = 0.15
const NONE: int = -1

var selected: int = NONE
var tiles: Dictionary[int, MeshInstance3D] = {}
var camera: Camera3D
var coordinate_label: Label
var selected_material: StandardMaterial3D
var reachable_material: StandardMaterial3D
var path_material: StandardMaterial3D
var attack_material: StandardMaterial3D
# Direct/debug instantiation uses the inexpensive internal preset. Normal games
# are always overridden by MatchConfig before this node enters the scene tree.
@export_range(0, 5) var subdivision_level: int = 3
@export var planet_radius: float = 12.0
@export var generation_config: PlanetGenerationConfig
var game_state: GameState
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
@export var animate_movement: bool = true
var health_fills: Dictionary[int, MeshInstance3D] = {}
var attack_tiles: Array[int] = []
var restart_button: Button
var attack_preview_label: Label
var selected_unit_id: int = -1
var selected_structure_id: int = -1
var reachable_tiles: Array[int] = []
var preview_path: Array[int] = []
var hover_cell: int = NONE
var hud_panel: PanelContainer
var turn_label: Label
var unit_label: Label
var feedback_label: Label
var end_turn_button: Button
var feedback_seconds: float = 0.0
var placement_mode: bool = false
var recruit_choice: String = ""
var recruit_hq_id: int = -1
var materials_label: Label
var recruit_highlights: Array[int] = []
var recruit_box: VBoxContainer
var match_mode: String = "Vs AI" # "Vs AI" or "Hotseat"
var player_controllers: Dictionary[int, String] = {1: "Human", 2: "AI"}

# AI runtime state
var _ai_running: bool = false
var _ai_token: int = 0
var _ai_delay: float = 0.25
const SimpleAI = preload("res://scripts/ai/simple_ai.gd")
var ai_agent: SimpleAI = SimpleAI.new()

@export var camera_config: TacticalCameraConfig
var navigation := SurfaceCamera.new()
var _is_middle_dragging: bool = false
var _last_mouse_pos := Vector2.ZERO
var _left_pending: bool = false
var _left_dragging: bool = false
var _left_start := Vector2.ZERO
var _grab_direction := Vector3.ZERO
var camera_diagnostics: bool = false


func configure_match(config: MatchConfig, settings: UserSettings) -> void:
	match_config = config.copy()
	var size := match_config.size_definition()
	subdivision_level = size.subdivision
	planet_radius = size.radius
	generation_config = PlanetGenerationConfig.new()
	generation_config.world_seed = match_config.world_seed
	player_controllers = {1: "Human", 2: match_config.opponent_controller}
	match_mode = "Hotseat" if match_config.opponent_controller == "Human" else "Vs AI"
	apply_user_settings(settings)

func apply_user_settings(settings: UserSettings) -> void:
	camera_config = settings.camera_configuration()
	if terrain_config == null: terrain_config = TerrainRenderConfig.new()
	terrain_config.terrain_subdivision_level = settings.terrain_subdivision()
	if camera != null:
		navigation.config = camera_config
		navigation.apply_transform()


func _ready() -> void:
	grid = PlanetGrid.new(subdivision_level, planet_radius)
	if generation_config == null:
		generation_config = PlanetGenerationConfig.new()
	generated_planet = GeneratedPlanet.generate(grid, generation_config)
	# Retain the canonical snapshot, including its deep-copied recipe.
	generation_config = generated_planet.config
	game_state = GameState.new(grid)
	rules = GameRules.new(game_state)
	print("PlanetGrid version=", grid.grid_generation_version, " subdivision=", subdivision_level,
		" cells=", grid.get_cell_count(), " pentagons=12 fingerprint=", grid.fingerprint)
	selected_material = _material(Color("#ffd166"))
	reachable_material = _material(Color("#578d4d"))
	path_material = _material(Color("#82e1ed"))
	attack_material = _material(Color("#d46bbe"))
	hover_material = _material(Color("#81989f"))
	if terrain_config == null: terrain_config = TerrainRenderConfig.new()
	terrain_renderer = PlanetTerrainRenderer.new()
	add_child(terrain_renderer)
	terrain_renderer.rebuild(generated_planet, terrain_config)
	terrain_surface = terrain_renderer.surface
	navigation.surface = terrain_surface
	for material: StandardMaterial3D in [selected_material, reachable_material, path_material, attack_material, hover_material]:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.38
	world_debug_view = PlanetWorldDebugView.new()
	world_debug_view.name = "WorldDebugView"
	world_debug_view.terrain_surface = terrain_surface
	world_debug_view.set_world(generated_planet)
	add_child(world_debug_view)
	debug_outlines = _debug_layer(PlanetSurface.debug_mesh(grid, false, false, terrain_surface), Color("#253940"))
	debug_centers = _debug_layer(PlanetSurface.debug_mesh(grid, true, false, terrain_surface), Color.WHITE)
	debug_pentagons = _debug_layer(PlanetSurface.debug_mesh(grid, false, true, terrain_surface), Color("#ff9b55"))
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
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#15212d")
	# Add gentle ambient so PBR models are visible
	environment.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.65
	# Slight tone mapping/adjustment for presentation
	environment.environment.adjustment_enabled = true
	environment.environment.adjustment_brightness = 1.0
	environment.environment.adjustment_contrast = 1.05
	add_child(environment)
	# Add a directional light to illuminate imported models
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 2.0
	sun.rotation_degrees = Vector3(-60, 30, 0)
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
	hud.add_child(world_debug_panel)
	restart_match()

func _sync_units() -> void:
	for id: int in unit_views.keys():
		if not game_state.units.has(id) and not game_state.structures.has(id):
			remove_child(unit_views[id])
			unit_views[id].queue_free()
			unit_views.erase(id)
			health_fills.erase(id)
	for unit: GameState.Unit in game_state.units.values():
		if not unit_views.has(unit.id):
			_create_entity_view(unit.id, unit.owner_id, unit.unit_type, false)
		_update_entity_view(unit.id, unit.cell_id, unit.hp, unit.max_hp)
	for structure: GameState.Structure in game_state.structures.values():
		if not unit_views.has(structure.id):
			_create_entity_view(structure.id, structure.owner_id, structure.structure_type, true)
		_update_entity_view(structure.id, structure.cell_id, structure.hp, structure.max_hp)

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
	if model_root.get_child_count() == 0:
		var placeholder := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.1, 0.7, 1.1) if is_structure else Vector3(0.6, 0.65, 0.6)
		placeholder.mesh = box
		placeholder.position.y = box.size.y / 2.0
		placeholder.material_override = _material(_owner_color(owner_id))
		model_root.add_child(placeholder)
	_apply_team_accent(model_root, owner_id)
	# Ownership remains readable even on textured assets without an accent slot.
	var team_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.64
	ring_mesh.outer_radius = 0.70
	team_ring.mesh = ring_mesh
	team_ring.scale.y = 0.15
	team_ring.position.y = 0.025
	team_ring.material_override = _material(_owner_color(owner_id))
	wrapper.add_child(team_ring)
	var background := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.94, 0.03, 0.13)
	background.mesh = bar
	background.position = Vector3(0, 0.09, 0.63)
	background.material_override = _material(Color("#101820"))
	view.add_child(background)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.88, 0.03, 0.08)
	fill.mesh = fill_mesh
	fill.position = Vector3(0, 0.12, 0.63)
	fill.material_override = _material(Color("#b5ed75"))
	view.add_child(fill)
	health_fills[id] = fill
	view.terrain_surface = terrain_surface
	view.configure(wrapper)
	view.movement_finished.connect(_refresh_display)

func _update_entity_view(id: int, cell_id: int, hp: int, max_hp: int) -> void:
	# Ground-origin wrapper; logical coordinates never depend on model transforms.
	unit_views[id].sync_position(terrain_surface.sample_position(grid.get_cell(cell_id).up, SURFACE_OFFSET))
	var fraction: float = float(hp) / max_hp
	health_fills[id].scale.x = fraction
	health_fills[id].position.x = -0.44 * (1.0 - fraction)

func _create_turn_hud(hud: CanvasLayer) -> void:
	hud_panel = PanelContainer.new()
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_panel.mouse_force_pass_scroll_events = false
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
	turn_label = _hud_label(column)
	turn_label.add_theme_font_size_override("font_size", 22)
	materials_label = _hud_label(column)
	end_turn_button = Button.new()
	end_turn_button.focus_mode = Control.FOCUS_NONE
	end_turn_button.pressed.connect(request_end_turn)
	column.add_child(end_turn_button)
	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(restart_match)
	column.add_child(restart_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 10)
	scroll.add_child(details)
	var legend: Label = _hud_label(details)
	var player_name := match_config.player_faction if match_config != null else "Blue"
	var opponent_name := match_config.opponent_faction if match_config != null else "Red"
	legend.text = "%s: P1 | %s: P2\nGreen: move | Cyan: path\nPurple: attack | Gold: selection" % [player_name, opponent_name]
	unit_label = _hud_label(details)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.custom_minimum_size.x = 270
	recruit_box = VBoxContainer.new()
	recruit_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(recruit_box)
	attack_preview_label = _hud_label(details)
	attack_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attack_preview_label.custom_minimum_size.y = 48
	feedback_label = _hud_label(details)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.custom_minimum_size.y = 54
	_layout_hud()
	get_viewport().size_changed.connect(_layout_hud)

func _hud_label(parent: Control) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _new_match(mode: String) -> void:
	match_mode = mode
	player_controllers = {1: "Human", 2: "Human" if mode == "Hotseat" else "AI"}
	if match_config != null:
		match_config.opponent_controller = player_controllers[2]
	restart_match()

func _layout_hud() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	hud_panel.position = Vector2(maxf(0.0, viewport_size.x - 330.0), 12.0)
	hud_panel.size = Vector2(318, maxf(240.0, viewport_size.y - 24.0))

func _clear_recruit_box() -> void:
	while recruit_box.get_child_count() > 0:
		var child := recruit_box.get_child(0)
		recruit_box.remove_child(child)
		child.queue_free()

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
	if camera_diagnostics: _update_label()
	_update_preview()

func _unhandled_input(event: InputEvent) -> void:
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
						if placement_mode: handle_recruit_click(button.position)
						else: select_at(button.position)
					_left_pending = false
					_left_dragging = false
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					if placement_mode: _cancel_recruit()
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
		if key.pressed and key.physical_keycode == KEY_ESCAPE:
			if placement_mode:
				_cancel_recruit()
			else:
				clear_selection()
		elif key.pressed and key.physical_keycode == KEY_F:
			_focus_selected()
		elif key.pressed and key.physical_keycode == KEY_F1:
			debug_outlines.visible = not debug_outlines.visible
		elif key.pressed and key.physical_keycode == KEY_F2:
			debug_pentagons.visible = not debug_pentagons.visible
		elif key.pressed and key.physical_keycode == KEY_F3:
			debug_centers.visible = not debug_centers.visible
		elif key.pressed and key.physical_keycode == KEY_F4:
			_toggle_debug_labels()
		elif key.pressed and key.physical_keycode == KEY_F6:
			world_debug_panel.visible = not world_debug_panel.visible
			world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)
		elif key.pressed and key.physical_keycode == KEY_F7:
			set_world_debug_mode((world_debug_view.mode + 1) % PlanetWorldDebugView.MODE_NAMES.size())
		elif key.pressed and key.physical_keycode == KEY_F8:
			camera_diagnostics = not camera_diagnostics
			_update_label()
		elif key.pressed and key.physical_keycode == KEY_HOME:
			_reset_camera()

func pick_cell(screen_position: Vector2) -> int:
	return pick_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func pick_ray(origin: Vector3, direction: Vector3) -> int:
	var hit: Vector3 = terrain_surface.ray_hit(origin, direction)
	return grid.find_cell(hit.normalized()) if hit != Vector3.ZERO else NONE

func select_at(screen_position: Vector2) -> void:
	selected = pick_selectable_cell(screen_position)
	var unit: GameState.Unit = game_state.unit_at(selected)
	if unit != null:
		selected_unit_id = unit.id
		selected_structure_id = -1
	else:
		var s: GameState.Structure = game_state.structure_at(selected)
		if s != null:
			selected_structure_id = s.id
			selected_unit_id = -1
		else:
			selected_unit_id = -1
			selected_structure_id = -1
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
	_cancel_recruit(false)
	_refresh_display()

func request_action_at(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if game_state.winner_id != 0:
		return
	# If placement mode is active, right click cancels and left handled elsewhere
	if placement_mode:
		return
	var target_entity := game_state.entity_at(pick_selectable_cell(screen_position))
	if target_entity != null and target_entity.owner_id != game_state.active_player and selected_unit_id != -1:
		var result: GameRules.Result = rules.try_attack(game_state.active_player, selected_unit_id, target_entity.id)
		_refresh_display()
		_feedback(result.reason)
	else:
		request_move_at(screen_position)

func request_move_at(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if placement_mode:
		# In placement mode left clicks are handled by placement logic
		return
	if selected_unit_id == -1:
		_feedback("Select one of your units first.")
		return
	var result: GameRules.Result = rules.try_move(game_state.active_player, selected_unit_id, pick_cell(screen_position))
	if result.success:
		selected = game_state.units[selected_unit_id].cell_id
		_present_move(selected_unit_id, result)
	_refresh_display()
	_feedback(result.reason)

func request_end_turn() -> void:
	if _human_action_blocked():
		return
	var result: GameRules.Result = rules.try_end_turn(game_state.active_player)
	if result.success:
		clear_selection()
	_feedback(result.reason)
	_queue_ai_turn()

func _reset_camera() -> void:
	navigation.reset(grid.get_cell(game_state.structures[100].cell_id).up)
	_is_middle_dragging = false
	_left_pending = false
	_left_dragging = false

func restart_match() -> void:
	_ai_token += 1
	_ai_running = false
	ai_agent.reset()
	rules.restart_match()
	for view: MeshInstance3D in unit_views.values():
		remove_child(view)
		view.queue_free()
	unit_views.clear()
	health_fills.clear()
	selected = NONE
	selected_unit_id = -1
	selected_structure_id = -1
	_cancel_recruit(false)
	feedback_seconds = 0.0
	feedback_label.text = ""
	_reset_camera()
	_refresh_display()
	_queue_ai_turn()

func regenerate_world(seed: int = generation_config.world_seed) -> void:
	# World regeneration never rebuilds topology and has no gameplay effects.
	var recipe: PlanetGenerationConfig = generation_config.duplicate(true) as PlanetGenerationConfig
	recipe.world_seed = seed
	var replacement: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe)
	if replacement == null:
		_feedback("World generation failed validation.")
		return
	generated_planet = replacement
	generation_config = replacement.config
	if match_config != null:
		match_config.world_seed = replacement.config.world_seed
	rebuild_terrain()
	world_debug_view.set_world(replacement)
	world_debug_panel.show_world(replacement)
	world_debug_panel.mode_select.select(world_debug_view.mode)
	_feedback("Generated world seed %d." % seed)

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
	world_debug_panel.mode_select.select(world_debug_view.mode)
	world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)

func _feedback(message: String) -> void:
	feedback_label.text = message
	feedback_seconds = 5.0

func _refresh_display() -> void:
	_sync_units()
	if selected_unit_id != -1 and not game_state.units.has(selected_unit_id):
		selected_unit_id = -1
		selected = NONE
	if selected_structure_id != -1 and not game_state.structures.has(selected_structure_id):
		selected_structure_id = -1
		selected = NONE
	if placement_mode and (game_state.winner_id != 0 or not game_state.structures.has(recruit_hq_id)):
		_cancel_recruit(false)
	var presenting: bool = is_presenting()
	var human_turn: bool = player_controllers[game_state.active_player] == "Human"
	var can_act: bool = human_turn and not presenting
	reachable_tiles.clear()
	if can_act:
		reachable_tiles = rules.reachable(game_state.active_player, selected_unit_id)
	attack_tiles.clear()
	if can_act:
		for id: int in rules.attack_targets(game_state.active_player, selected_unit_id):
			if game_state.units.has(id):
				attack_tiles.append(game_state.units[id].cell_id)
			else:
				attack_tiles.append(game_state.structures[id].cell_id)
	preview_path.clear()
	attack_preview_label.text = ""
	hover_cell = NONE
	if world_debug_panel.visible:
		world_debug_panel.inspect_cell(selected)
	_refresh_tile_materials()
	_update_label()
	turn_label.text = "Player %d | Round %d" % [game_state.active_player, game_state.round_number]
	materials_label.text = "Materials: P1 %d | P2 %d\nActive: Player %d (%s)" % [
		game_state.materials[1], game_state.materials[2], game_state.active_player, player_controllers[game_state.active_player],
	]
	end_turn_button.text = "End Turn - Player %d" % game_state.active_player
	end_turn_button.disabled = game_state.winner_id != 0 or not can_act
	if presenting:
		end_turn_button.text = "Moving..."
	restart_button.visible = game_state.winner_id != 0
	if game_state.winner_id != 0:
		turn_label.text = "Player %d wins" % game_state.winner_id
	_clear_recruit_box()
	if selected_unit_id != -1:
		var unit: GameState.Unit = game_state.units[selected_unit_id]
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
		if unit.ready_next_turn:
			unit_label.text += "\nReady next turn."
		if unit.owner_id != game_state.active_player:
			unit_label.text += "\nEnemy unit: inspection only."
	elif selected_structure_id != -1:
		var headquarters: GameState.Structure = game_state.structures[selected_structure_id]
		unit_label.text = "Headquarters | Player %d\nCell %d | HP: %d/%d\nRecruit available: %s" % [
			headquarters.owner_id, headquarters.cell_id, headquarters.hp, headquarters.max_hp,
			"Yes" if headquarters.recruit_available else "No",
		]
		if headquarters.owner_id == game_state.active_player and can_act and game_state.winner_id == 0:
			for kind: String in UnitTypes.STATS:
				var stats: Dictionary = UnitTypes.STATS[kind]
				var reason: String = rules.recruit_error(game_state.active_player, headquarters.id, kind)
				if reason.is_empty() and rules.recruit_destinations(game_state.active_player, headquarters.id, kind).is_empty():
					reason = "No free adjacent tiles."
				var button := Button.new()
				button.name = "Recruit" + kind
				button.text = "%s: %d materials\nHP %d | Move %d | Range %d | Damage %d" % [
					kind, UnitTypes.COSTS[kind], stats.hp, stats.movement, stats.range, stats.damage,
				]
				button.focus_mode = Control.FOCUS_NONE
				button.disabled = not reason.is_empty()
				button.tooltip_text = reason
				button.pressed.connect(_begin_recruit.bind(kind, headquarters.id))
				recruit_box.add_child(button)
				if not reason.is_empty():
					var explanation: Label = _hud_label(recruit_box)
					explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					explanation.text = reason
	else:
		unit_label.text = "No unit selected.\nLeft click: inspect / select\nRight click: move / attack\nEsc: clear"

func _update_preview() -> void:
	update_hover_at(get_viewport().get_mouse_position())

func update_hover_at(mouse: Vector2) -> void:
	var destination: int = NONE
	var over_debug: bool = world_debug_panel.visible and world_debug_panel.get_global_rect().has_point(mouse)
	var over_ui: bool = hud_panel.get_global_rect().has_point(mouse) or coordinate_label.get_global_rect().has_point(mouse) or over_debug
	if not over_ui:
		destination = pick_cell(mouse)
	if destination == hover_cell:
		return
	hover_cell = destination
	if world_debug_panel.visible:
		world_debug_panel.inspect_cell(selected if selected != NONE else hover_cell)
	preview_path.clear()
	attack_preview_label.text = ""
	var target_entity := game_state.entity_at(destination)
	if target_entity != null and target_entity is GameState.Unit:
		var preview: GameRules.Result = rules.preview_attack(game_state.active_player, selected_unit_id, target_entity.id)
		if preview.success:
			var outcome: String = "LETHAL" if preview.killed else "survives"
			attack_preview_label.text = "%s: %d damage\nHP %d -> %d | %s" % [
				target_entity.unit_type, preview.damage, target_entity.hp, preview.target_hp, outcome,
			]
	elif target_entity != null and target_entity is GameState.Structure:
		var preview_s: GameRules.Result = rules.preview_attack(game_state.active_player, selected_unit_id, target_entity.id)
		if preview_s.success:
			attack_preview_label.text = "%s: %d damage\nHP %d -> %d | %s" % [
				target_entity.structure_type, preview_s.damage, target_entity.hp, preview_s.target_hp, "LETHAL" if preview_s.killed else "survives",
			]
	if reachable_tiles.has(destination):
		preview_path = rules.path_to(game_state.active_player, selected_unit_id, destination)
	_refresh_tile_materials()

func _refresh_tile_materials() -> void:
	for tile: MeshInstance3D in tiles.values():
		tile.visible = false
	var active: Dictionary = {}
	for id: int in reachable_tiles + recruit_highlights:
		active[id] = reachable_material
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

func _update_label() -> void:
	var status: String = "none" if selected == NONE else "Cell %d" % selected
	coordinate_label.text = "Selected: %s\nWASD/arrows: pan | Q/E: yaw\nLMB drag: pan | MMB: orbit | Wheel: zoom\nF: focus | Home: reset\nF1 grid | F2 pentagons | F3 centers | F4 IDs\nF6 world panel | F7 world view | F8 camera" % status
	if camera_diagnostics:
		coordinate_label.text += "\nFocus %d %s\nYaw %.1f | Pitch %.1f | Distance %.2f\n%s | Entity %d | Follow %s" % [grid.find_cell(navigation.focus_direction), navigation.focus_direction, navigation.yaw, navigation.pitch, navigation.distance, navigation.zoom_band(), navigation.focused_entity, navigation.focused_entity != -1]

func _owner_color(owner_id: int) -> Color:
	var faction := "Blue" if owner_id == 1 else "Red"
	if match_config != null:
		faction = match_config.player_faction if owner_id == 1 else match_config.opponent_faction
	return Color("#75baff") if faction == "Blue" else Color("#f77e75")

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
	var error: String = rules.recruit_error(game_state.active_player, hq_id, kind)
	if not error.is_empty():
		_feedback(error)
		return
	recruit_highlights = rules.recruit_destinations(game_state.active_player, hq_id, kind)
	if recruit_highlights.is_empty():
		_feedback("No free adjacent tiles.")
		return
	placement_mode = true
	recruit_choice = kind
	recruit_hq_id = hq_id
	preview_path.clear()
	attack_preview_label.text = ""
	_feedback("Place %s: left-click green tile. Right-click / Escape cancels." % kind)
	_refresh_tile_materials()

func _queue_ai_turn() -> void:
	if _ai_running or game_state.winner_id != 0 or player_controllers[game_state.active_player] != "AI":
		return
	_ai_running = true
	_start_ai_turn.call_deferred(_ai_token, game_state.active_player)

func _start_ai_turn(token: int, actor: int) -> void:
	var budget: int = maxi(8, game_state.units.size() * 3)
	var attempts: int = 0
	while token == _ai_token and game_state.winner_id == 0 and game_state.active_player == actor and player_controllers[actor] == "AI":
		var action: Dictionary = ai_agent.choose_action(game_state, rules, actor) if attempts < budget else {"type": "end"}
		attempts += 1
		var result: GameRules.Result
		match action.get("type", "end"):
			"attack":
				result = rules.try_attack(actor, action.attacker, action.target)
			"move":
				result = rules.try_move(actor, action.unit, action.dest)
				_present_move(action.unit, result)
			"recruit":
				result = rules.try_recruit(actor, action.hq_id, action.kind, action.dest)
			_:
				result = rules.try_end_turn(actor)
		ai_agent.record_result(action, result.success)
		clear_selection()
		_feedback(result.reason)
		while token == _ai_token and is_presenting():
			await get_tree().process_frame
		if token != _ai_token:
			return
		if game_state.active_player != actor or game_state.winner_id != 0:
			break
		if DisplayServer.get_name() == "headless" or _ai_delay <= 0.0:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(_ai_delay).timeout
	if token == _ai_token:
		_ai_running = false
		_queue_ai_turn()

func handle_recruit_click(screen_position: Vector2) -> void:
	if _human_action_blocked():
		return
	if not placement_mode or player_controllers[game_state.active_player] != "Human":
		return
	var destination: int = pick_cell(screen_position)
	var result: GameRules.Result = rules.try_recruit(game_state.active_player, recruit_hq_id, recruit_choice, destination)
	if result.success:
		_cancel_recruit(false)
		_refresh_display()
	_feedback(result.reason)

func _cancel_recruit(show_feedback: bool = true) -> void:
	placement_mode = false
	recruit_choice = ""
	recruit_hq_id = -1
	recruit_highlights.clear()
	if show_feedback:
		_feedback("Recruit cancelled.")
	if not tiles.is_empty() and reachable_material != null:
		_refresh_tile_materials()

func is_presenting() -> bool:
	for view: EntityView in unit_views.values():
		if view.moving:
			return true
	return false

func _human_action_blocked() -> bool:
	if player_controllers[game_state.active_player] != "Human":
		return true
	if is_presenting():
		_feedback("Wait for movement to finish.")
		return true
	return false

func _present_move(unit_id: int, result: GameRules.Result) -> void:
	if result.success and animate_movement and unit_views.has(unit_id):
		unit_views[unit_id].play_path(result.path, grid, SURFACE_OFFSET)

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
	for id: int in unit_views:
		var view: EntityView = unit_views[id]
		if not view.visible: continue
		var inverse := view.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_ray: Vector3 = inverse.basis * ray
		var half_width := 0.62 if game_state.structures.has(id) else 0.4
		var bounds := AABB(Vector3(-half_width, 0, -half_width), Vector3(half_width * 2, 1.0, half_width * 2))
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
	terrain_renderer.rebuild(generated_planet, terrain_config)
	terrain_surface = terrain_renderer.surface
	navigation.surface = terrain_surface
	world_debug_view.terrain_surface = terrain_surface
	world_debug_view.set_world(generated_planet)
	for view: EntityView in unit_views.values(): view.terrain_surface = terrain_surface
	for tile: MeshInstance3D in tiles.values(): tile.free()
	tiles.clear()
	debug_outlines.mesh = PlanetSurface.debug_mesh(grid, false, false, terrain_surface)
	debug_centers.mesh = PlanetSurface.debug_mesh(grid, true, false, terrain_surface)
	debug_pentagons.mesh = PlanetSurface.debug_mesh(grid, false, true, terrain_surface)
	for label: Label3D in debug_labels.get_children():
		label.position = terrain_surface.sample_position(label.position.normalized(),0.10)
	set_world_debug_mode(world_debug_view.mode)
	_refresh_display()
