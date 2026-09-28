extends SceneTree
## Exercises the real Button signal callbacks in one application process.

const Main := preload("res://scenes/main.tscn")
var failures := 0
var app: AppController

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _button_named(text: String) -> Button:
	for node: Node in app.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			return button
	return null

func _press(text: String) -> void:
	var button := _button_named(text)
	check(button != null, "Button exists: " + text)
	if button != null:
		button.pressed.emit()

func _escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)

func _run() -> void:
	root.size = Vector2i(1152, 648)
	app = Main.instantiate() as AppController
	root.add_child(app)
	await process_frame
	print("NAV STEP 1 main")
	_press("Options")
	await process_frame
	print("NAV STEP 2 options returned to loop")
	check(is_instance_valid(app) and app.screen_name == "options", "Main Options keeps AppController alive")
	_press("Back")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "main", "Options Back returns to Main Menu")
	_press("New Game")
	await process_frame
	check(app.screen_name == "setup", "New Game callback opens setup")
	_press("Start Game")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "game" and app.board != null, "Start callback creates first match")
	var first_board := app.board
	_escape()
	await process_frame
	check(app.screen_name == "pause" and paused, "Escape callback opens pause")
	_press("Options")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "options" and app.board == first_board and paused, "Pause Options preserves paused match")
	_press("Back")
	await process_frame
	check(app.screen_name == "pause" and app.board == first_board and paused, "Options Back returns to Pause")
	_press("Resume")
	await process_frame
	check(app.screen_name == "game" and app.board == first_board and not paused, "Resume preserves first match")
	_escape()
	await process_frame
	_press("Main Menu")
	await process_frame
	check(is_instance_valid(app) and app.is_inside_tree() and app.screen_name == "main", "Pause Main Menu keeps AppController alive")
	check(app.board == null and app.current_match_config == null and not paused, "Pause Main Menu clears only match state")
	_press("Options")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "options", "Main Options still works after a match")
	_press("Back")
	await process_frame
	_press("New Game")
	await process_frame
	_press("Start Game")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "game" and app.board != null and app.board != first_board, "Second match starts in same application")
	_escape()
	await process_frame
	_press("Main Menu")
	await process_frame
	check(is_instance_valid(app) and app.screen_name == "main" and app.board == null and not paused, "Second return reaches live Main Menu")
	print("NAV STEPS 1-11 complete without quit")
	if "--verify-quit" in OS.get_cmdline_user_args():
		print("NAV STEP 12 explicit Quit")
		_press("Quit")
		return
	print("Frontend callback navigation checks complete; failures=", failures)
	app.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
