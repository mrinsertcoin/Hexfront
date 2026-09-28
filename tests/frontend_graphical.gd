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
	app.show_match_setup()
	await capture("setup")
	app.show_options(false)
	await capture("options")
	app.show_match_setup()
	app.setup_seed.text = "48293617"
	app.start_match_from_setup()
	await capture("game")
	check(app.board.grid.get_cell_count() == 2562, "Graphical launch uses Small")
	app.show_pause_menu()
	await capture("pause")
	app.show_options(true)
	await capture("pause_options")
	app._leave_options()
	app.resume_game()
	check(app.screen_name == "game" and not paused, "Graphical pause flow resumes")
	app.show_main_menu()
	await capture("returned_main")
	check(app.board == null, "Graphical return cleans match")
	app.queue_free()
	await process_frame
	print("Frontend graphical checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)
