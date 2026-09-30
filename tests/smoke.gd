extends "res://tests/hotseat.gd"

func _run() -> void:
	# Retain the entire original 8A sphere regression as a zero-displacement fixture.
	# tests/terrain.gd separately covers the displaced render surface.
	await setup()
	board.terrain_config.terrain_height_scale = 0.0
	board.rebuild_terrain()
	var picks: int = 0
	var started: int = Time.get_ticks_usec()
	for yaw: float in [0.0, 90.0, 180.0, 237.0]:
		for pitch: float in [0.0, 53.0, -65.0, 89.9, -89.9]:
			for altitude: float in [4.0, 16.0, 60.0]:
				_globe_pose(yaw, pitch, altitude)
				var origin: Vector3 = board.camera.position
				check(origin.length() > board.planet_radius, "Camera stays outside")
				for cell: PlanetCell in board.grid.cells:
					var screen: Vector2 = _screen(cell.id, false)
					if board.camera.is_position_behind(cell.center_world_position) or not root.get_visible_rect().has_point(screen):
						continue
					var facing: float = cell.up.dot(origin - cell.center_world_position)
					var picked: int = board.pick_cell(screen)
					if facing > 0.05:
						check(picked == cell.id, "Visible center picked at every orientation and zoom")
						picks += 1
					elif facing < -0.05:
						# A horizon-straddling cell can have a hidden center but a visible
						# front portion under the same pixel. Reject fully hidden cells.
						var fully_hidden: bool = true
						for corner: Vector3 in cell.polygon_vertices:
							if corner.normalized().dot(origin - corner) > -0.05:
								fully_hidden = false
						if fully_hidden:
							check(picked != cell.id, "Fully hidden cell never picked through globe")
				# Sample just inside the geometric horizon, independent of cells.
				var radial: Vector3 = origin.normalized()
				var tangent: Vector3 = PlanetCell.tangent_basis(radial).x
				var angle: float = acos(board.planet_radius / origin.length()) * 0.995
				var direction: Vector3 = radial.rotated(tangent, angle)
				var screen: Vector2 = board.camera.unproject_position(direction * board.planet_radius)
				check(board.pick_cell(screen) == board.grid.find_cell(direction), "Near-horizon picking resolves front intersection")
	print("Picking matrix visible centers=", picks, " elapsed_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3(1, 2, 3).normalized()]:
		var basis: Basis = PlanetCell.tangent_basis(direction)
		check(basis.is_finite() and basis.y.is_equal_approx(direction) and absf(basis.determinant() - 1) < 0.00001, "Non-singular polar and diagonal tangent frame")
		var id: int = board.grid.find_cell(direction)
		board.game_state.units[1].cell_id = id
		board.game_state.structures[100].cell_id = id
		board._sync_units()
		for entity_id in [1, 100]:
			check(board.unit_views[entity_id].basis.y.dot(board.grid.get_cell(id).up) > 0.99999, "Unit and HQ local up radial")
			check(board.unit_views[entity_id].position.length() > board.planet_radius, "Visual offset preserved")
	board.restart_match()
	for id: int in [0, board.game_state.units[1].cell_id, board.game_state.structures[101].cell_id]:
		board.select_at(_screen(id))
		check(board.selected == id and board.tiles[id].visible, "Pentagon/unit/HQ selection overlays")
		var arrays: Array = board.tiles[id].mesh.surface_get_arrays(0)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			check(absf(vertex.length() - board.planet_radius - 0.04) < 0.0001, "Overlay follows spherical radius")
	board.clear_selection()
	board.update_hover_at(_screen(0))
	check(board.hover_cell == 0 and board.tiles[0].visible, "Hover works without selected unit")
	board.navigation.distance = 60
	board._update_camera_transform(0)
	board.update_hover_at(Vector2(30, 600))
	check(board.hover_cell == board.NONE, "Leaving globe clears hover")
	check(board.pick_ray(Vector3.ZERO, Vector3.UP) == -1, "Inside rays do not select rear surface")
	var before: String = TestState.snapshot(board.game_state)
	board.selected = board.game_state.structures[101].cell_id
	board.selected_structure_id = 101
	keypress(KEY_F)
	for i in range(60):
		board._process(0.016)
	check(board.navigation.focus_direction.dot(board.grid.get_cell(board.selected).up) > 0.999, "Smooth focus reaches opposite hemisphere")
	check(TestState.snapshot(board.game_state) == before, "Camera never moves authoritative coordinates")
	# Exercise viewport input routing, not just direct camera parameter changes.
	for i in range(80):
		click(Vector2(600, 400), MOUSE_BUTTON_WHEEL_UP)
	check(board.navigation.target_distance == board.camera_config.min_distance, "Wheel clamps close zoom above surface")
	for i in range(80):
		click(Vector2(600, 400), MOUSE_BUTTON_WHEEL_DOWN)
	check(board.navigation.target_distance == board.navigation.max_distance(), "Wheel reaches whole-planet zoom")
	var old_yaw: float = board.navigation.target_yaw
	var press := InputEventMouseButton.new()
	press.position = Vector2(600, 300)
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	root.push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(700, 340)
	drag.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(drag, true)
	check(not is_equal_approx(board.navigation.target_yaw, old_yaw), "Middle drag orbits through viewport input")
	press.pressed = false
	root.push_input(press, true)
	check(not board._is_middle_dragging, "Middle release stops orbit drag")
	board._process(0.1)
	board.update_hover_at(Vector2(600, 400))
	check(board.hover_cell == board.pick_cell(Vector2(600, 400)), "Stationary cursor hover follows camera motion")
	keypress(KEY_F2)
	keypress(KEY_F3)
	keypress(KEY_F4)
	check(board.debug_pentagons.visible and board.debug_centers.visible and board.debug_labels.visible, "Debug controls")
	check(board.debug_labels.get_child_count() == 642, "Optional IDs and neighbor counts")
	await finish("Globe picking/transform")
