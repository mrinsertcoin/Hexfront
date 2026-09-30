extends SceneTree

const Main := preload("res://scenes/main.tscn")
var failures := 0
var app: AppController

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/10_frontend_" + label + ".png") == OK, "Capture saved")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run frontend_graphical without --headless")
		quit(1)
		return
	root.size = Vector2i(1152, 648)
	app = Main.instantiate() as AppController
	root.add_child(app)
	await capture("main")
	check(app.music_manager.current_track_id==MusicTrackRegistry.TITLE
		and app.music_manager.active_player().playing,"Graphical launch plays title music")
	var title_player:=app.music_manager.active_player()
	app.show_multiplayer_menu()
	await capture("multiplayer")
	app.show_host_setup(); app.network_name.text="Graphical Host"; app.network_port.value=32000+int(Time.get_ticks_msec()%1000); app._create_network_lobby()
	await capture("multiplayer_lobby")
	check(app.screen_name=="lobby" and app.network_session.role==NetworkSession.Role.HOST,"Graphical multiplayer lobby remains inside AppController")
	app.show_main_menu()
	app.show_match_setup()
	await capture("setup")
	check(app.music_manager.active_player()==title_player,"Setup does not restart title music")
	app.show_options(false)
	await capture("options")
	app.show_match_setup()
	app.setup_seed.text = "48293617"
	app.start_match_from_setup()
	await capture("game")
	check(app.music_manager.current_track_id==MusicTrackRegistry.SWARM
		and app.music_manager.active_player().playing,"Graphical match plays configured faction music")
	check(app.board.grid.get_cell_count() == 2562, "Graphical launch uses Small")
	app.show_pause_menu()
	var match_generation:=app.music_manager.transition_generation
	await capture("pause")
	app.show_options(true)
	await capture("pause_options")
	check(app.music_manager.current_track_id==MusicTrackRegistry.SWARM
		and app.music_manager.transition_generation==match_generation,"Pause Options keeps faction music continuous")
	var back: Button
	for node: Node in app.find_children("*", "Button", true, false):
		if (node as Button).text == "Back": back = node as Button
	check(back != null, "Shared Options Back exists")
	if back != null: back.pressed.emit()
	app.resume_game()
	check(app.screen_name == "game" and not paused, "Graphical pause flow resumes")
	app.show_main_menu()
	await capture("returned_main")
	check(app.music_manager.current_track_id==MusicTrackRegistry.TITLE,"Graphical return crossfades to title music")
	check(app.board == null, "Graphical return cleans match")
	app.queue_free()
	await process_frame
	print("Frontend graphical checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)
