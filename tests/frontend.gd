extends SceneTree

const Main := preload("res://scenes/main.tscn")
var failures: int = 0
var app: AppController

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1152, 648)
	app = Main.instantiate() as AppController
	root.add_child(app)
	await process_frame
	check(app.screen_name == "main" and app.board == null, "Launch opens main menu without gameplay state")
	check(app.music_manager.current_track_id==MusicTrackRegistry.TITLE,"Launch requests title music")
	var title_generation:=app.music_manager.transition_generation
	var saved_music_volume:=app.settings.music_volume_db
	app.show_options(false)
	app.options_music.value=-22.0
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),-22.0),
		"Music slider previews volume immediately")
	app._leave_options()
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),saved_music_volume),
		"Leaving without Apply restores saved music volume")
	check(app.load_game_button.visible and app.load_game_button.disabled, "Load Game is visible and disabled")
	app.show_multiplayer_menu()
	check(app.screen_name=="multiplayer","Main Menu exposes multiplayer navigation")
	app.show_host_setup(); app.network_name.text="Frontend Host"; app.network_port.value=31000+int(Time.get_ticks_msec()%1000)
	app._create_network_lobby()
	check(app.screen_name=="lobby" and app.network_session.role==NetworkSession.Role.HOST,"Host Game creates a development lobby without leaving AppController")
	app.show_main_menu()
	check(app.network_session.role==NetworkSession.Role.OFFLINE and app.network_session.lobby_players.is_empty(),"Returning to Main Menu closes network state cleanly")
	app.show_match_setup()
	check(app.screen_name == "setup", "New Game opens match setup")
	var has_living_migration:=false; var has_baumeister:=false
	for index in range(app.setup_player_faction.item_count):
		has_living_migration=has_living_migration or app.setup_player_faction.get_item_metadata(index)=="living_migration"
		has_baumeister=has_baumeister or app.setup_player_faction.get_item_metadata(index)=="baumeister"
	check(has_living_migration,"Match Setup exposes The Living Migration by stable faction ID")
	check(has_baumeister,"Match Setup exposes Baumeister by stable faction ID")
	check(app.music_manager.current_track_id==MusicTrackRegistry.TITLE
		and app.music_manager.transition_generation==title_generation,"Frontend navigation keeps title music continuous")
	check(app.setup_planet_size.get_item_metadata(app.setup_planet_size.selected) == MatchConfig.PlanetSize.SMALL, "Small is the normal default")
	check(app.setup_planet_size.item_count == 2 and app.setup_planet_size.get_item_text(0).begins_with("Small") and app.setup_planet_size.get_item_text(1).begins_with("Medium"), "Normal setup hides raw subdivision and dev size")
	app.setup_seed.text = "9223372036854775808"
	app.start_match_from_setup()
	check(app.board == null and app.setup_feedback.text.contains("signed"), "Overflow seed is rejected")
	app.setup_seed.text = "13579"
	app.setup_controller.select(1)
	app._controller_changed(1)
	var config := app.setup_config()
	check(config.world_seed == 13579 and config.opponent_controller == "Human", "Setup creates session values")
	check(config.size_definition().subdivision == 4 and config.size_definition().radius == 24.0 and config.size_definition().cells == 2562, "Small maps to subdivision 4, radius 24, and 2562 cells")
	app.start_match(config)
	check(app.screen_name == "game" and app.board != null, "Start transitions into game")
	check(app.music_manager.current_track_id==MusicTrackRegistry.SWARM,"Blue/Swarm match requests faction music")
	check(app.board.grid.get_cell_count() == 2562 and app.board.planet_radius == 24.0, "Small creates the intended world")
	check(app.board.generation_config.world_seed == 13579 and app.board.generated_planet.config.world_seed == 13579, "Board consumes configured seed")
	check(app.board.player_controllers == {1: "Human", 2: "Human"}, "Controller config creates hotseat players")
	check(app.board._owner_color(1) == Color("#75baff") and app.board._owner_color(2) == Color("#f77e75"), "Faction selection controls presentation colors")
	var fingerprint := app.board.generated_planet.generation_fingerprint
	var first_board := app.board
	app.show_main_menu()
	check(not is_instance_valid(first_board) and app.board == null and app.current_match_config == null, "Main Menu destroys the match session")
	app.start_match(config)
	check(app.board.generated_planet.generation_fingerprint == fingerprint, "Same MatchConfig reproduces the world")
	var player_units:=0
	for unit: GameState.Unit in app.board.game_state.units.values(): player_units+=int(app.board.game_state.players.has(unit.controller_id))
	check(app.board.game_state.round_number == 1 and player_units == 6, "New session has no stale gameplay state")
	app.show_pause_menu()
	var match_music_generation:=app.music_manager.transition_generation
	check(app.screen_name == "pause" and paused, "Pause menu pauses gameplay")
	app.show_options(true)
	check(app.screen_name == "options" and paused, "Pause reuses shared options screen")
	check(app.music_manager.current_track_id==MusicTrackRegistry.SWARM
		and app.music_manager.transition_generation==match_music_generation,"Pause Options keeps faction music continuous")
	app._leave_options()
	check(app.screen_name == "pause", "Options returns to pause")
	app.resume_game()
	check(app.screen_name == "game" and not paused, "Resume restores gameplay")
	app.show_main_menu()
	check(app.music_manager.current_track_id==MusicTrackRegistry.TITLE,"Returning to Main Menu requests title music")
	app.show_match_setup()
	app.setup_seed.text = "24680"
	app.setup_controller.select(0)
	for index in range(app.setup_player_faction.item_count):
		if app.setup_player_faction.get_item_metadata(index)=="red": app.setup_player_faction.select(index)
	app.setup_opponent_faction.select(0)
	app._controller_changed(0)
	config = app.setup_config()
	app.start_match(config)
	check(app.music_manager.current_track_id==MusicTrackRegistry.BUILDERS,"Red/Builders match requests faction music")
	check(app.board.player_controllers == {1: "Human", 2: "AI"}, "AI controller config reaches gameplay")
	check(app.board.generated_planet.generation_fingerprint != fingerprint, "Changing seed changes generated world")
	# Persistence uses a test-only user file and leaves the real preferences untouched.
	var path := "user://hexfront_test_%d.cfg" % Time.get_ticks_usec()
	var saved := UserSettings.new()
	saved.storage_path = path
	saved.fullscreen = true
	saved.vsync = false
	saved.master_volume_db = -12
	saved.music_volume_db = -17
	saved.orbit_sensitivity = 0.55
	saved.zoom_response = 1.27
	saved.drag_threshold = 8
	saved.terrain_quality = "Medium"
	saved.ui_scale=1.2
	saved.terrain_quality = "High"
	saved.terrain_quality = "Medium"
	check(saved.save_to_disk() == OK, "Options save to ConfigFile")
	var loaded := UserSettings.new()
	loaded.storage_path = path
	loaded.load_from_disk()
	check(loaded.fullscreen and not loaded.vsync and loaded.master_volume_db == -12 and loaded.music_volume_db == -17 and loaded.orbit_sensitivity == 0.55 and loaded.zoom_response == 1.27 and loaded.drag_threshold == 8 and loaded.terrain_subdivision() == 4 and is_equal_approx(loaded.ui_scale,1.2), "Options persist and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(MatchConfig.SIZE_DEFINITIONS[MatchConfig.PlanetSize.MEDIUM].subdivision == 5 and MatchConfig.SIZE_DEFINITIONS[MatchConfig.PlanetSize.MEDIUM].radius == 48.0 and MatchConfig.SIZE_DEFINITIONS[MatchConfig.PlanetSize.MEDIUM].cells == 10242, "Medium preset scales topology and radius centrally")
	app.queue_free()
	await process_frame
	print("Frontend/session checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)
