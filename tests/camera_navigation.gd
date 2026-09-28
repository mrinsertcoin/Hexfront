extends "res://tests/hotseat.gd"

var graphical: bool = false

func capture(label: String) -> void:
	if not graphical: return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/9_camera_" + label + ("_dense" if board.subdivision_level == 4 else "") + ".png") == OK, "Camera capture saved")

func button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

func drag(from: Vector2, to: Vector2) -> void:
	button(from, true)
	for i in range(1, 9):
		var event := InputEventMouseMotion.new()
		event.position = from.lerp(to, float(i) / 8)
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)
	button(to, false)

func tick(seconds: float) -> void:
	for i in range(int(ceil(seconds * 120))): board._process(1.0 / 120)

func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	await setup(true, 4 if "--dense" in OS.get_cmdline_user_args() else 3)
	var nav := board.navigation
	var snapshot := TestState.snapshot(board.game_state)
	await capture("default")
	var displacements: Array[float] = []
	for fps: int in [30, 60, 144]:
		nav.reset(Vector3.LEFT)
		for frame in range(fps): nav.update(1.0 / fps, Vector2(1, 0))
		var displacement := acos(clampf(Vector3.LEFT.dot(nav.focus_direction), -1, 1))
		displacements.append(displacement)
	check(displacements.min() > 0.01 and displacements.max() - displacements.min() < 0.002, "Pan speed is stable across frame rates")
	board._reset_camera()
	for corner: Vector2 in [Vector2(1, 1), Vector2(1151, 1), Vector2(1, 647), Vector2(1151, 647)]:
		check(board.pick_cell(corner) != -1, "Default tactical framing has terrain through all corners")
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		nav.reset(direction)
		var before := nav.focus_direction
		var ahead := nav.forward()
		for frame in range(30): nav.update(1.0 / 60, Vector2(0, 1))
		check((nav.focus_direction - before).dot(ahead) > 0, "W follows screen-forward tangent on every hemisphere")
		var right := nav.forward().cross(nav.focus_direction)
		before = nav.focus_direction
		for frame in range(30): nav.update(1.0 / 60, Vector2(1, 0))
		check((nav.focus_direction - before).dot(right) > 0, "D follows screen-right tangent on every hemisphere")
		check(absf(nav.focus_direction.length() - 1) < 0.00001 and absf(nav.heading.dot(nav.focus_direction)) < 0.00001, "Transport retains orthonormal tangent frame")
		check(board.camera.transform.is_finite(), "Camera finite across pole traversal")
		await capture("hemisphere_%s" % direction)
	nav.reset(Vector3.UP)
	var previous_right := board.camera.basis.x
	for frame in range(360):
		nav.update(1.0 / 60, Vector2(0, 1))
		check(previous_right.dot(board.camera.basis.x) > 0.99, "No roll flip while crossing pole")
		previous_right = board.camera.basis.x
		check(board.camera.position.length() >= board.terrain_surface.radius_at(board.camera.position.normalized()) + board.camera_config.terrain_clearance - 0.0001, "Camera clears actual terrain")
	board._reset_camera()
	var source := board.game_state.units[1].cell_id
	var screen := _screen(source)
	button(screen, true)
	check(board.selected_unit_id == -1, "Mouse down defers selection")
	button(screen, false)
	check(board.selected_unit_id == 1 and nav.focused_entity == 1, "Unit click selects and links focus")
	var model_point := board.unit_views[1].global_transform * Vector3(0, 0.7, 0)
	check(board.pick_selectable_cell(board.camera.unproject_position(model_point)) == source, "Visible entity takes priority over underlying terrain")
	tick(1)
	await capture("selected_unit")
	for kind in range(3):
		var cell: int = source if kind == 0 else board.rules.reachable(1, 1)[0]
		if kind == 2:
			board.clear_selection()
			cell = board.grid.get_neighbors(source)[0]
		screen = _screen(cell)
		var initial_selection := board.selected
		var anchor := board.terrain_surface.ray_hit(board.camera.project_ray_origin(screen), board.camera.project_ray_normal(screen))
		drag(screen, screen + Vector2(60, 35))
		check(board.selected == initial_selection, "Occupied/reachable/empty drag never executes a click")
		check(nav.focused_entity == -1 and not nav.transitioning, "Drag breaks follow and interrupts focus")
		check(board.camera.unproject_position(anchor).distance_to(screen + Vector2(60, 35)) < 3.0, "Grabbed terrain follows cursor")
		await capture("drag_%d" % kind)
	screen = _screen(source)
	drag(screen, screen + Vector2(2, 1))
	check(board.selected_unit_id == 1, "Subthreshold motion remains a normal click")
	var destination := board.rules.reachable(1, 1)[0]
	var focus_before := nav.focus_direction
	click(_screen(destination, false), MOUSE_BUTTON_RIGHT)
	check(board.game_state.units[1].cell_id == destination, "Movement command retained")
	check(nav.focus_direction.is_equal_approx(focus_before), "Movement click does not recenter immediately")
	var view := board.unit_views[1]
	view.set_process(false)
	for frame in range(120):
		view.advance_movement(1.0 / 60)
		board._process(1.0 / 60)
	check(nav.focus_direction.dot(view.position.normalized()) > 0.9999, "Follow tracks moving presentation root")
	await capture("follow_arrived")
	nav.update(0.1, Vector2(1, 0))
	check(nav.focused_entity == -1, "Manual pan breaks follow")
	keypress(KEY_F)
	check(nav.focused_entity == 1, "F restores selected entity focus")
	tick(1)
	click(_screen(board.game_state.structures[100].cell_id))
	check(board.selected_structure_id == 100 and nav.focused_entity == 100, "HQ click focuses")
	tick(1)
	await capture("hq")
	board.clear_selection()
	var transform_before := board.camera.transform
	keypress(KEY_F)
	check(board.camera.transform == transform_before and not nav.transitioning, "F without entity is a no-op")
	for target: Vector3 in [-nav.focus_direction, Vector3(0.00001, 1, 0).normalized(), Vector3.DOWN]:
		var zoom_before := nav.target_distance
		nav.focus(target)
		nav.update(0.2)
		await capture("travel_%s" % target)
		for frame in range(120):
			nav.update(1.0 / 120)
			check(board.camera.transform.is_finite() and board.camera.position.length() > board.planet_radius, "Distant/antipodal travel remains outside planet")
		check(nav.focus_direction.dot(target) > 0.99999 and is_equal_approx(nav.distance, zoom_before), "Distant arrival restores zoom")
		await capture("distant_%s" % target)
	nav.focus(-nav.focus_direction)
	nav.update(0.15)
	screen = Vector2(576, 380)
	drag(screen, screen + Vector2(45, 20))
	check(not nav.transitioning, "Drag interrupts an in-progress antipodal transition")
	nav.orbit(Vector2(90, 10000))
	tick(1)
	check(is_equal_approx(nav.pitch, board.camera_config.min_pitch), "Pitch lower clamp")
	nav.orbit(Vector2(0, -10000))
	tick(1)
	check(is_equal_approx(nav.pitch, board.camera_config.max_pitch), "Pitch upper clamp")
	board._reset_camera()
	nav.zoom(200)
	tick(2)
	check(is_equal_approx(nav.distance, nav.max_distance()), "Continuous wheel zoom reaches radius/FOV planet distance")
	for axis: Vector3 in [board.camera.basis.x, board.camera.basis.y]:
		for sign_value: float in [-1.0, 1.0]:
			check(root.get_visible_rect().has_point(board.camera.unproject_position(axis * board.planet_radius * sign_value)), "Whole globe fits viewport")
	await capture("planet")
	drag(Vector2(576, 350), Vector2(630, 380))
	check(board.camera.transform.is_finite(), "Planet-scale surface drag remains stable")
	await capture("planet_drag")
	nav.zoom(-200)
	tick(2)
	check(is_equal_approx(nav.distance, board.camera_config.min_distance), "Close zoom clamp")
	await capture("closest")
	# Only the explicit movement command above may change authoritative state.
	check(board.game_state.units[1].cell_id == destination and snapshot != TestState.snapshot(board.game_state), "Navigation preserves commanded destination")
	await finish("Surface camera")
