class_name AppController
extends Node
## Owns top-level navigation. Gameplay owns neither menus nor scene transitions.

const GAME_SCENE := preload("res://scenes/game.tscn")

var settings := UserSettings.new()
var current_match_config: MatchConfig
var board: PlanetBoard
var menu_layer: CanvasLayer
var screen_name: String = ""
var options_return_to_pause: bool = false

# Public references make keyboard focus and UI flow straightforward to verify.
var new_game_button: Button
var load_game_button: Button
var setup_player_faction: OptionButton
var setup_opponent_faction: OptionButton
var setup_controller: OptionButton
var setup_difficulty: OptionButton
var setup_planet_size: OptionButton
var setup_seed: LineEdit
var setup_feedback: Label
var options_fullscreen: CheckButton
var options_vsync: CheckButton
var options_master: HSlider
var options_orbit: HSlider
var options_zoom: HSlider
var options_drag: HSlider
var options_quality: OptionButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_from_disk()
	settings.apply_global()
	show_main_menu()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE: return
	match screen_name:
		"game": show_pause_menu()
		"pause": resume_game()
		"setup": show_main_menu()
		"options": _leave_options()
		_: return
	get_viewport().set_input_as_handled()

func _clear_menu() -> void:
	if menu_layer != null:
		# Navigation is commonly invoked by a Button inside this layer. Immediate
		# free() destroys the signal emitter while `pressed` is still unwinding,
		# which Godot treats as an error and can terminate a debug run. Detach the
		# old screen immediately, then let SceneTree dispose it safely.
		var old_layer := menu_layer
		menu_layer = null
		remove_child(old_layer)
		old_layer.queue_free()

func _clear_match() -> void:
	get_tree().paused = false
	if board != null:
		board.free()
		board = null
	current_match_config = null

func _menu_column(title: String, width: float = 430.0, overlay: bool = false) -> VBoxContainer:
	_clear_menu()
	menu_layer = CanvasLayer.new()
	menu_layer.name = "MenuLayer"
	menu_layer.layer = 100
	add_child(menu_layer)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.063, 0.098, 0.137, 0.88 if overlay else 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	var rule := HSeparator.new()
	column.add_child(rule)
	return column

func _button(parent: Control, label: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label
	result.custom_minimum_size.y = 42
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var text := Label.new()
	text.text = label
	text.custom_minimum_size.x = 180
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	control.custom_minimum_size.x = 210
	row.add_child(control)

func _option(values: PackedStringArray, selected: int = 0) -> OptionButton:
	var result := OptionButton.new()
	for value: String in values: result.add_item(value)
	result.select(selected)
	return result

func show_main_menu() -> void:
	_clear_match()
	screen_name = "main"
	var column := _menu_column("HEXFRONT")
	var subtitle := Label.new()
	subtitle.text = "Turn-based planetary strategy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color("#a8bac8")
	column.add_child(subtitle)
	new_game_button = _button(column, "New Game", show_match_setup)
	load_game_button = _button(column, "Load Game — Coming Later", func() -> void: pass)
	load_game_button.disabled = true
	load_game_button.tooltip_text = "Save and load are not implemented yet."
	_button(column, "Options", show_options.bind(false))
	_button(column, "Quit", get_tree().quit)
	new_game_button.grab_focus()

func show_match_setup() -> void:
	screen_name = "setup"
	var column := _menu_column("New Game", 520)
	setup_player_faction = _option(["Blue", "Red"])
	setup_opponent_faction = _option(["Blue", "Red"], 1)
	setup_controller = _option(["AI", "Human"])
	setup_difficulty = _option(["Standard"])
	setup_planet_size = OptionButton.new()
	for size: MatchConfig.PlanetSize in MatchConfig.normal_planet_sizes():
		var definition: Dictionary = MatchConfig.SIZE_DEFINITIONS[size]
		setup_planet_size.add_item("%s — %d cells" % [definition.name, definition.cells])
		setup_planet_size.set_item_metadata(setup_planet_size.item_count - 1, size)
	setup_planet_size.select(0)
	setup_seed = LineEdit.new()
	setup_seed.text = "48293617"
	setup_seed.placeholder_text = "Signed 64-bit integer"
	setup_seed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row(column, "Player faction", setup_player_faction)
	_row(column, "Opponent faction", setup_opponent_faction)
	_row(column, "Opponent controller", setup_controller)
	_row(column, "AI difficulty", setup_difficulty)
	_row(column, "Planet size", setup_planet_size)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.add_child(setup_seed)
	setup_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(seed_row, "Randomize", randomize_seed)
	_row(column, "World seed", seed_row)
	setup_controller.item_selected.connect(_controller_changed)
	setup_feedback = Label.new()
	setup_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_feedback.modulate = Color("#f2b8a0")
	column.add_child(setup_feedback)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button(actions, "Back", show_main_menu)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var start := _button(actions, "Start Game", start_match_from_setup)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.grab_focus()

func _controller_changed(_index: int) -> void:
	setup_difficulty.disabled = setup_controller.get_item_text(setup_controller.selected) == "Human"

func randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	setup_seed.text = str(rng.randi())

func _parse_seed(text_value: String) -> Variant:
	var input := text_value.strip_edges()
	if not input.is_valid_int(): return null
	var value := input.to_int()
	var digits := input.trim_prefix("+").trim_prefix("-").lstrip("0")
	if digits.is_empty(): digits = "0"
	var canonical := ("-" if input.begins_with("-") and digits != "0" else "") + digits
	return value if str(value) == canonical else null

func setup_config() -> MatchConfig:
	var seed_value: Variant = _parse_seed(setup_seed.text)
	if seed_value == null: return null
	var result := MatchConfig.new()
	result.world_seed = seed_value
	result.planet_size = setup_planet_size.get_item_metadata(setup_planet_size.selected)
	result.player_faction = setup_player_faction.get_item_text(setup_player_faction.selected)
	result.opponent_faction = setup_opponent_faction.get_item_text(setup_opponent_faction.selected)
	result.opponent_controller = setup_controller.get_item_text(setup_controller.selected)
	result.ai_difficulty = setup_difficulty.get_item_text(setup_difficulty.selected)
	return result

func start_match_from_setup() -> void:
	var config := setup_config()
	if config == null:
		setup_feedback.text = "Enter a signed 64-bit integer seed."
		return
	var errors := config.validate()
	if not errors.is_empty():
		setup_feedback.text = "\n".join(errors)
		return
	start_match(config)

func start_match(config: MatchConfig) -> void:
	_clear_match()
	_clear_menu()
	current_match_config = config.copy()
	board = GAME_SCENE.instantiate() as PlanetBoard
	board.configure_match(current_match_config, settings)
	add_child(board)
	screen_name = "game"

func show_pause_menu() -> void:
	if board == null: return
	get_tree().paused = true
	screen_name = "pause"
	var column := _menu_column("Paused", 430, true)
	var resume := _button(column, "Resume", resume_game)
	_button(column, "Options", show_options.bind(true))
	_button(column, "Main Menu", show_main_menu)
	_button(column, "Quit to Desktop", get_tree().quit)
	resume.grab_focus()

func resume_game() -> void:
	_clear_menu()
	get_tree().paused = false
	screen_name = "game"

func show_options(from_pause: bool = false) -> void:
	options_return_to_pause = from_pause
	screen_name = "options"
	var column := _menu_column("Options", 540, from_pause)
	options_fullscreen = CheckButton.new()
	options_fullscreen.button_pressed = settings.fullscreen
	options_vsync = CheckButton.new()
	options_vsync.button_pressed = settings.vsync
	options_master = _slider(-40, 6, 1, settings.master_volume_db)
	options_orbit = _slider(0.05, 1.0, 0.05, settings.orbit_sensitivity)
	options_zoom = _slider(1.02, 1.5, 0.01, settings.zoom_response)
	options_drag = _slider(2, 12, 1, settings.drag_threshold)
	options_quality = _option(["Medium", "High"], 0 if settings.terrain_quality == "Medium" else 1)
	_row(column, "Fullscreen", options_fullscreen)
	_row(column, "VSync", options_vsync)
	_row(column, "Master volume (dB)", options_master)
	_row(column, "Orbit sensitivity", options_orbit)
	_row(column, "Wheel zoom response", options_zoom)
	_row(column, "Drag threshold (px)", options_drag)
	_row(column, "Terrain quality", options_quality)
	var hint := Label.new()
	hint.text = "Terrain quality applies when the next match starts."
	hint.modulate = Color("#a8bac8")
	column.add_child(hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button(actions, "Back", _leave_options)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var apply := _button(actions, "Apply", apply_options)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.grab_focus()

func _slider(minimum: float, maximum: float, step_value: float, current: float) -> HSlider:
	var result := HSlider.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step_value
	result.value = current
	result.tooltip_text = str(current)
	result.value_changed.connect(func(value: float) -> void: result.tooltip_text = str(value))
	return result

func apply_options() -> void:
	settings.fullscreen = options_fullscreen.button_pressed
	settings.vsync = options_vsync.button_pressed
	settings.master_volume_db = options_master.value
	settings.orbit_sensitivity = options_orbit.value
	settings.zoom_response = options_zoom.value
	settings.drag_threshold = options_drag.value
	settings.terrain_quality = options_quality.get_item_text(options_quality.selected)
	settings.apply_global()
	settings.save_to_disk()
	if board != null:
		board.apply_user_settings(settings)
	_leave_options()

func _leave_options() -> void:
	if options_return_to_pause and board != null: show_pause_menu()
	else: show_main_menu()
