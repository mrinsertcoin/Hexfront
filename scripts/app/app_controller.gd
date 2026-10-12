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
var music_manager: MusicManager
var network_session: NetworkSession
var network_view: NetworkMatchView
var network_name: LineEdit
var network_address: LineEdit
var network_port: SpinBox
var network_faction: OptionButton
var network_feedback: Label
var network_ready: bool=false
var network_slots: OptionButton
var network_planet_size: OptionButton
var network_population: OptionButton
var network_villages: OptionButton
var network_cliffs: OptionButton
var network_seed: LineEdit
var disconnected_player_id: int=0

# Public references make keyboard focus and UI flow straightforward to verify.
var new_game_button: Button
var load_game_button: Button
var setup_player_faction: OptionButton
var setup_opponent_faction: OptionButton
var setup_controller: OptionButton
var setup_difficulty: OptionButton
var setup_planet_size: OptionButton
var setup_world_population: OptionButton
var setup_villages: OptionButton
var setup_cliffs: OptionButton
var setup_seed: LineEdit
var setup_feedback: Label
var options_fullscreen: CheckButton
var options_vsync: CheckButton
var options_master: HSlider
var options_music: HSlider
var options_orbit: HSlider
var options_zoom: HSlider
var options_drag: HSlider
var options_quality: OptionButton
var options_ui_scale: HSlider

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_manager=MusicManager.new()
	music_manager.name="MusicManager"
	add_child(music_manager)
	network_session=NetworkSession.new(); network_session.name="NetworkSession"; add_child(network_session)
	network_session.status_changed.connect(_network_status_changed)
	network_session.lobby_changed.connect(_network_lobby_changed)
	network_session.match_announced.connect(_network_match_announced)
	network_session.session_ended.connect(_network_session_ended)
	network_session.participant_disconnected.connect(_network_participant_disconnected)
	settings.load_from_disk()
	settings.apply_global()
	show_main_menu()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE: return
	match screen_name:
		"game":
			if board!=null and board.has_active_input_mode(): board.cancel_input_mode()
			else: show_pause_menu()
		"pause": resume_game()
		"setup": show_main_menu()
		"multiplayer", "host_setup", "join_setup", "lobby": show_main_menu()
		"network_game", "network_interrupt": show_main_menu()
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
	if network_view!=null:
		var old_network_view:=network_view; network_view=null
		remove_child(old_network_view); old_network_view.queue_free()
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
	MythicFrame.apply(panel)
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
	heading.add_theme_font_override("font",MythicFrame.TITLE_FONT)
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
	if network_session!=null and network_session.role!=NetworkSession.Role.OFFLINE: network_session.shutdown("Returned to main menu.")
	music_manager.play_title()
	screen_name = "main"
	var column := _menu_column("HEXFRONT")
	var subtitle := Label.new()
	subtitle.text = "Turn-based planetary strategy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color("#a8bac8")
	column.add_child(subtitle)
	new_game_button = _button(column, "New Game", show_match_setup)
	_button(column,"Multiplayer",show_multiplayer_menu)
	load_game_button = _button(column, "Load Game — Coming Later", func() -> void: pass)
	load_game_button.disabled = true
	load_game_button.tooltip_text = "Save and load are not implemented yet."
	_button(column, "Options", show_options.bind(false))
	_button(column, "Quit", get_tree().quit)
	new_game_button.grab_focus()

func show_multiplayer_menu() -> void:
	music_manager.play_title(); screen_name="multiplayer"
	var column:=_menu_column("Multiplayer",480)
	var text:=Label.new(); text.text="Host-authoritative development multiplayer"; text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; text.modulate=Color("#a8bac8"); column.add_child(text)
	_button(column,"Host Game",show_host_setup)
	_button(column,"Join Game",show_join_setup)
	_button(column,"Back",show_main_menu)

func show_host_setup() -> void:
	screen_name="host_setup"
	var column:=_menu_column("Host Game",520)
	_network_identity_controls(column,false)
	network_slots=_option(PackedStringArray(["2 players","3 players","4 players"]),2)
	for index in range(network_slots.item_count): network_slots.set_item_metadata(index,index+2)
	_row(column,"Player slots",network_slots)
	network_planet_size=OptionButton.new()
	for size: MatchConfig.PlanetSize in MatchConfig.normal_planet_sizes():
		var definition: Dictionary=MatchConfig.SIZE_DEFINITIONS[size]
		network_planet_size.add_item(definition.name); network_planet_size.set_item_metadata(network_planet_size.item_count-1,size)
	_row(column,"Planet size",network_planet_size)
	network_population=_option(PackedStringArray(WorldPopulationConfig.PRESETS),2); _row(column,"World population",network_population)
	network_villages=_option(PackedStringArray(["0","1","2","3","4"]),2); _row(column,"Villages per Player",network_villages)
	network_seed=LineEdit.new(); network_seed.text=str(48293617); _row(column,"World seed",network_seed)
	network_cliffs=_advanced_terrain_settings(column)
	var actions:=HBoxContainer.new(); actions.add_theme_constant_override("separation",8); column.add_child(actions)
	_button(actions,"Back",show_multiplayer_menu).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(actions,"Create Lobby",_create_network_lobby).size_flags_horizontal=Control.SIZE_EXPAND_FILL

func show_join_setup() -> void:
	screen_name="join_setup"
	var column:=_menu_column("Join Game",520)
	_network_identity_controls(column,true)
	var actions:=HBoxContainer.new(); actions.add_theme_constant_override("separation",8); column.add_child(actions)
	_button(actions,"Back",show_multiplayer_menu).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(actions,"Connect",_join_network_lobby).size_flags_horizontal=Control.SIZE_EXPAND_FILL

func _network_identity_controls(column: VBoxContainer,joining: bool) -> void:
	network_name=LineEdit.new(); network_name.text="Player"; network_name.placeholder_text="Player name"; _row(column,"Player name",network_name)
	if joining:
		network_address=LineEdit.new(); network_address.text="127.0.0.1"; network_address.placeholder_text="Host IP address"; _row(column,"Host address",network_address)
	network_port=SpinBox.new(); network_port.min_value=1; network_port.max_value=65535; network_port.value=NetworkProtocol.DEFAULT_PORT; network_port.allow_greater=false; _row(column,"UDP port",network_port)
	network_faction=OptionButton.new()
	for faction: FactionDefinition in _multiplayer_factions():
		network_faction.add_item(faction.display_name); network_faction.set_item_metadata(network_faction.item_count-1,faction.id)
	_row(column,"Faction",network_faction)
	network_feedback=Label.new(); network_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; network_feedback.modulate=Color("#f2b8a0"); column.add_child(network_feedback)

func _create_network_lobby() -> void:
	var seed_value: Variant=_parse_seed(network_seed.text)
	if seed_value==null:
		network_feedback.text="Enter a signed 64-bit world seed."; return
	var configuration: Dictionary={"planet_size":int(network_planet_size.get_item_metadata(network_planet_size.selected)),
		"world_seed":int(seed_value),"world_population_preset":network_population.get_item_text(network_population.selected),
		"villages_per_player":network_villages.selected,"cliff_generation":network_cliffs.get_item_text(network_cliffs.selected)}
	var error:=network_session.host_game(int(network_port.value),network_name.text,
		String(network_faction.get_item_metadata(network_faction.selected)),int(network_slots.get_item_metadata(network_slots.selected)),configuration)
	if error==OK: network_ready=false; show_network_lobby()
	else: network_feedback.text=network_session.status_message

func _join_network_lobby() -> void:
	var error:=network_session.join_game(network_address.text,int(network_port.value),network_name.text,String(network_faction.get_item_metadata(network_faction.selected)))
	if error==OK:
		network_feedback.text=network_session.status_message
	else: network_feedback.text=network_session.status_message

func show_network_lobby() -> void:
	screen_name="lobby"
	var column:=_menu_column("Multiplayer Lobby",600)
	var status:=Label.new(); status.name="NetworkStatus"; status.text=network_session.status_message; status.modulate=Color("#a8bac8"); column.add_child(status)
	var players:=Label.new(); players.name="LobbyPlayers"
	var lines:=PackedStringArray()
	for record: Dictionary in network_session.lobby_records():
		var faction:=ContentRegistry.default().faction(String(record.faction_id))
		lines.append("P%d  %s  —  %s  —  %s  —  %s  —  %s%s" % [int(record.player_id),String(record.player_name),
			faction.display_name if faction!=null else String(record.faction_id),String(record.get("color_name","Color")),
			"READY" if bool(record.ready) else "not ready","connected" if bool(record.get("connected",true)) else "disconnected",
			"  [HOST]" if bool(record.host) else ""])
	players.text="\n".join(lines); column.add_child(players)
	var config:=network_session.lobby_match_config
	var size: Dictionary=MatchConfig.SIZE_DEFINITIONS.get(int(config.get("planet_size",MatchConfig.PlanetSize.SMALL)),MatchConfig.SIZE_DEFINITIONS[MatchConfig.PlanetSize.SMALL])
	var match_info:=Label.new(); match_info.text="MATCH  %s planet  ·  Seed %d  ·  Population %s  ·  Villages/P %d  ·  Cliffs %s  ·  Capacity %d" % [
		String(size.name),int(config.get("world_seed",0)),String(config.get("world_population_preset",WorldPopulationConfig.STANDARD)),int(config.get("villages_per_player",2)),String(config.get("cliff_generation","Rare")),network_session.lobby_capacity]
	match_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; match_info.modulate=Color("#a8bac8"); column.add_child(match_info)
	var choice:=OptionButton.new()
	for faction: FactionDefinition in _multiplayer_factions():
		choice.add_item(faction.display_name); choice.set_item_metadata(choice.item_count-1,faction.id)
		if faction.id==network_session.local_faction_id: choice.select(choice.item_count-1)
	choice.item_selected.connect(func(index: int)->void:
		network_ready=false
		network_session.set_local_lobby_choice(String(choice.get_item_metadata(index)),false))
	_row(column,"Your faction",choice)
	var ready:=CheckButton.new(); ready.text="Ready"; ready.button_pressed=network_ready
	ready.toggled.connect(func(value: bool)->void: network_ready=value; network_session.set_local_lobby_choice(network_session.local_faction_id,value))
	column.add_child(ready)
	if network_session.role==NetworkSession.Role.HOST:
		var start:=_button(column,"Start Development Match",_start_network_match); start.disabled=not network_session.can_host_start()
	_button(column,"Leave Lobby",show_main_menu)

func _start_network_match() -> void:
	if not network_session.can_host_start(): return
	var config:=MatchConfig.new(); config.network_match=true
	config.planet_size=int(network_session.lobby_match_config.get("planet_size",MatchConfig.PlanetSize.SMALL))
	config.world_seed=int(network_session.lobby_match_config.get("world_seed",48293617))
	config.private_population_seed=config.world_seed ^ 0x51A7E3D
	config.world_population_preset=String(network_session.lobby_match_config.get("world_population_preset",WorldPopulationConfig.STANDARD))
	config.villages_per_player=int(network_session.lobby_match_config.get("villages_per_player",2))
	config.cliff_generation=String(network_session.lobby_match_config.get("cliff_generation","Rare"))
	for record: Dictionary in network_session.lobby_records():
		config.player_assignments.append({"player_id":int(record.player_id),"player_name":String(record.player_name),
			"faction_id":String(record.faction_id),"team_id":int(record.player_id),"controller_kind":ControllerState.HUMAN,
			"player_color":String(record.player_color)})
	config.player_faction_id=String(config.player_assignments[0].faction_id)
	config.opponent_faction_id=String(config.player_assignments[1].faction_id)
	config.player_team_id=int(config.player_assignments[0].team_id); config.opponent_team_id=int(config.player_assignments[1].team_id)
	var errors:=config.validate()
	if not errors.is_empty(): return
	var error:=network_session.announce_match(config.public_network_dictionary())
	if not error.is_empty(): return
	start_network_host_match(config)

func start_network_host_match(config: MatchConfig) -> void:
	_clear_match(); _clear_menu(); current_match_config=config.copy()
	var faction:=ContentRegistry.default().faction(config.player_faction_id); music_manager.play_faction(faction.music_id if faction!=null else config.player_faction_id)
	board=GAME_SCENE.instantiate() as PlanetBoard; board.configure_network_host(current_match_config,settings,network_session); add_child(board)
	screen_name="game"

func _network_match_announced(config_data: Dictionary) -> void:
	if network_session.role!=NetworkSession.Role.CLIENT: return
	_clear_match(); _clear_menu(); current_match_config=MatchConfig.from_network_dictionary(config_data)
	network_view=NetworkMatchView.new(); network_view.configure(network_session); network_view.leave_requested.connect(show_main_menu); add_child(network_view)
	screen_name="network_game"

func _network_status_changed(status: int,message: String) -> void:
	if network_feedback!=null and is_instance_valid(network_feedback): network_feedback.text=message
	if status==NetworkSession.Status.LOBBY and screen_name=="join_setup": network_ready=false; show_network_lobby()
	elif status==NetworkSession.Status.ACTIVE and screen_name=="network_interrupt" and network_session.role==NetworkSession.Role.CLIENT:
		disconnected_player_id=0; _clear_menu(); screen_name="network_game"
	elif status==NetworkSession.Status.ERROR and screen_name in ["join_setup","host_setup"] and network_feedback!=null: network_feedback.text=message

func _network_lobby_changed(players: Array) -> void:
	for record: Dictionary in players:
		if int(record.player_id)==network_session.local_player_id: network_ready=bool(record.ready)
	if screen_name=="lobby": show_network_lobby()

func _network_session_ended(reason: String) -> void:
	if screen_name not in ["game","network_game","lobby","network_interrupt"]: return
	_clear_match(); music_manager.play_title(); screen_name="multiplayer"
	var column:=_menu_column("Multiplayer Session Ended",520)
	var message:=Label.new(); message.text=reason; message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	_button(column,"Back",show_main_menu)

func _network_participant_disconnected(player_id: int,player_name: String) -> void:
	if screen_name not in ["game","network_game"]: return
	if network_session.status==NetworkSession.Status.ACTIVE:
		if board!=null:
			board._feedback("%s disconnected and was eliminated. The match continues." % player_name)
			board._refresh_display()
		return
	disconnected_player_id=player_id
	screen_name="network_interrupt"
	var column:=_menu_column("Player Disconnected",520,true)
	var message:=Label.new(); message.text="%s disconnected. The authoritative match is paused." % player_name; message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(message)
	if network_session.role==NetworkSession.Role.HOST:
		_button(column,"Remove Player",_remove_disconnected_network_player)
		_button(column,"Abort Match to Lobby",_abort_network_match_to_lobby)
	_button(column,"Main Menu",show_main_menu)

func _remove_disconnected_network_player() -> void:
	if not network_session.remove_disconnected_player(disconnected_player_id): return
	disconnected_player_id=0; _clear_menu(); screen_name="game"
	if board!=null: board._refresh_display()

func _abort_network_match_to_lobby() -> void:
	network_session.abort_match_to_lobby("Match aborted after a disconnect.")
	_clear_match(); show_network_lobby()

func _multiplayer_factions() -> Array[FactionDefinition]:
	var result: Array[FactionDefinition]=[]
	for faction_id: String in NetworkProtocol.MULTIPLAYER_FACTIONS:
		var faction:=ContentRegistry.default().faction(faction_id)
		if faction!=null and faction.playable: result.append(faction)
	return result

func show_match_setup() -> void:
	music_manager.play_title()
	screen_name = "setup"
	var column := _menu_column("New Game", 520)
	var playable:=ContentRegistry.default().playable_factions()
	var faction_names:=PackedStringArray()
	for faction: FactionDefinition in playable: faction_names.append(faction.display_name)
	setup_player_faction = _option(faction_names)
	setup_opponent_faction = _option(faction_names)
	for index in range(playable.size()):
		setup_player_faction.set_item_metadata(index,playable[index].id)
		setup_opponent_faction.set_item_metadata(index,playable[index].id)
		if playable[index].id=="blue": setup_player_faction.select(index)
		if playable[index].id=="red": setup_opponent_faction.select(index)
	setup_controller = _option(["AI", "Human"])
	setup_difficulty = _option(["Standard"])
	setup_planet_size = OptionButton.new()
	for size: MatchConfig.PlanetSize in MatchConfig.normal_planet_sizes():
		var definition: Dictionary = MatchConfig.SIZE_DEFINITIONS[size]
		setup_planet_size.add_item("%s — %d cells" % [definition.name, definition.cells])
		setup_planet_size.set_item_metadata(setup_planet_size.item_count - 1, size)
	setup_planet_size.select(0)
	setup_world_population=_option(PackedStringArray(WorldPopulationConfig.PRESETS),2)
	setup_villages=_option(PackedStringArray(["0","1","2","3","4"]),2)
	setup_seed = LineEdit.new()
	setup_seed.text = "48293617"
	setup_seed.placeholder_text = "Signed 64-bit integer"
	setup_seed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row(column, "Player faction", setup_player_faction)
	_row(column, "Opponent faction", setup_opponent_faction)
	_row(column, "Opponent controller", setup_controller)
	_row(column, "AI difficulty", setup_difficulty)
	_row(column, "Planet size", setup_planet_size)
	_row(column, "World population", setup_world_population)
	_row(column, "Villages per Player", setup_villages)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.add_child(setup_seed)
	setup_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(seed_row, "Randomize", randomize_seed)
	_row(column, "World seed", seed_row)
	setup_cliffs=_advanced_terrain_settings(column)
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

func _advanced_terrain_settings(column: VBoxContainer) -> OptionButton:
	var toggle:=Button.new(); toggle.text="Advanced Settings"; toggle.toggle_mode=true; column.add_child(toggle)
	var section:=VBoxContainer.new(); section.visible=false; column.add_child(section)
	var cliffs:=_option(TerracedTerrain.CLIFF_PRESETS,1); cliffs.tooltip_text="None: every height transition has a ramp. Rare: occasional impassable ground edges. Experimental: many cliffs."
	_row(section,"Cliff generation",cliffs)
	var note:=Label.new(); note.text="Four elevation layers · consistent %d° ramps\nCliffs block ground units; flying units can cross." % int(TerracedTerrain.RAMP_ANGLE_DEGREES)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; section.add_child(note)
	toggle.toggled.connect(func(open: bool)->void: section.visible=open)
	return cliffs

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
	result.player_faction_id = setup_player_faction.get_item_metadata(setup_player_faction.selected)
	result.opponent_faction_id = setup_opponent_faction.get_item_metadata(setup_opponent_faction.selected)
	result.opponent_controller = setup_controller.get_item_text(setup_controller.selected)
	result.ai_difficulty = setup_difficulty.get_item_text(setup_difficulty.selected)
	result.world_population_preset=setup_world_population.get_item_text(setup_world_population.selected)
	result.villages_per_player=setup_villages.selected
	result.cliff_generation=setup_cliffs.get_item_text(setup_cliffs.selected)
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
	var faction:=ContentRegistry.default().faction(current_match_config.player_faction_id)
	music_manager.play_faction(faction.music_id if faction!=null else current_match_config.player_faction_id)
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
	options_music = _slider(-40, 6, 1, settings.music_volume_db)
	options_music.value_changed.connect(_preview_music_volume)
	options_orbit = _slider(0.05, 1.0, 0.05, settings.orbit_sensitivity)
	options_zoom = _slider(1.02, 1.5, 0.01, settings.zoom_response)
	options_drag = _slider(2, 12, 1, settings.drag_threshold)
	options_quality = _option(["Medium", "High"], 0 if settings.terrain_quality == "Medium" else 1)
	options_ui_scale=_slider(0.8,1.4,0.1,settings.ui_scale)
	_row(column, "Fullscreen", options_fullscreen)
	_row(column, "VSync", options_vsync)
	_row(column, "Master volume (dB)", options_master)
	_row(column, "Music volume (dB)", options_music)
	_row(column, "Orbit sensitivity", options_orbit)
	_row(column, "Wheel zoom response", options_zoom)
	_row(column, "Drag threshold (px)", options_drag)
	_row(column, "Terrain quality", options_quality)
	_row(column,"Interface scale",options_ui_scale)
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
	settings.music_volume_db = options_music.value
	settings.orbit_sensitivity = options_orbit.value
	settings.zoom_response = options_zoom.value
	settings.drag_threshold = options_drag.value
	settings.terrain_quality = options_quality.get_item_text(options_quality.selected)
	settings.ui_scale=options_ui_scale.value
	settings.apply_global()
	settings.save_to_disk()
	if board != null:
		board.apply_user_settings(settings)
	_leave_options()

func _leave_options() -> void:
	# Back discards an unapplied preview; Apply updates settings first.
	music_manager.set_music_volume_db(settings.music_volume_db)
	if options_return_to_pause and board != null: show_pause_menu()
	else: show_main_menu()

func _preview_music_volume(value: float) -> void:
	music_manager.set_music_volume_db(value)
