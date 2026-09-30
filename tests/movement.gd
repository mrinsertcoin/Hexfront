extends SceneTree
var failures: int = 0
var checks: int = 0
var grid := PlanetGrid.new(2)

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture(start: int = 0, allowance: int = 3) -> GameState:
	var state := GameState.new(grid)
	state.units.clear()
	state.structures.clear()
	state.units[1] = GameState.Unit.new(1, 1, "Scout", start, allowance)
	state.refresh_visibility()
	return state

func reject(state: GameState, actor: int, unit_id: int, destination: int) -> void:
	var before: String = TestState.snapshot(state)
	var rules := GameRules.new(state)
	var result: GameRules.Result = rules.try_move(actor, unit_id, destination)
	check(not result.success and not result.reason.is_empty(), "Illegal move rejected with reason")
	check(TestState.snapshot(state) == before, "Rejected move is completely read-only")
	check(rules.path_to(actor, unit_id, destination).is_empty(), "Illegal move has no preview")

# Independent unweighted relaxation oracle, not a call to production BFS.
func distances(start: int, blocked: Dictionary) -> Dictionary:
	var costs: Dictionary = {start: 0}
	var changed: bool = true
	while changed:
		changed = false
		for cell: PlanetCell in grid.cells:
			if not costs.has(cell.id):
				continue
			for neighbor: int in cell.neighbor_ids:
				if blocked.has(neighbor):
					continue
				if not costs.has(neighbor) or costs[neighbor] > costs[cell.id] + 1:
					costs[neighbor] = costs[cell.id] + 1
					changed = true
	return costs

func _run() -> void:
	var detours: int = 0
	var initial := GameState.new(grid)
	check(initial.units.size() == 6 and initial.structures.size() == 2, "Starting force preserved")
	var occupied: Dictionary = {}
	for unit: GameState.Unit in initial.units.values():
		check(grid.contains(unit.cell_id) and not occupied.has(unit.cell_id), "Distinct valid starting units")
		occupied[unit.cell_id] = true
		check(unit.movement == initial.registry.unit(unit.definition_id).movement and not unit.moved, "Unchanged movement balance")
	for hq: GameState.Structure in initial.structures.values():
		check(not occupied.has(hq.cell_id) and hq.hp == 25, "Distinct HQ and preserved HP")
		occupied[hq.cell_id] = true
	check(grid.distance(initial.structures[100].cell_id, initial.structures[101].cell_id) == grid.breadth_first(0).costs[grid.breadth_first(0).order[-1]], "Starts maximally separated from first HQ")
	for start: int in [0, 12, 50]: # Pentagon and ordinary neighborhoods.
		for allowance in [1, 2, 3]:
			for block_mode in range(3):
				var state: GameState = fixture(start, allowance)
				var blocked: Dictionary = {}
				for neighbor: int in grid.get_neighbors(start):
					if block_mode == 2 or (block_mode == 1 and blocked.is_empty()):
						var id: int = state.allocate_id()
						state.units[id] = GameState.Unit.new(id, 1, "Infantry", neighbor)
						blocked[neighbor] = true
				var rules := GameRules.new(state)
				var before: String = TestState.snapshot(state)
				var expected: Dictionary = distances(start, blocked)
				var reachable: Array[int] = rules.reachable(1, 1)
				check(reachable == rules.reachable(1, 1), "Stable traversal tie break")
				for destination in range(grid.get_cell_count()):
					var legal: bool = destination != start and expected.has(destination) and expected[destination] <= allowance
					var path: Array[int] = rules.path_to(1, 1, destination)
					check(reachable.has(destination) == legal and (not path.is_empty()) == legal, "Highlights and preview agree with independent shortest paths")
					check(TestState.snapshot(state) == before, "Queries preserve all state")
					if legal:
						if expected[destination] > grid.distance(start, destination):
							detours += 1
						check(path[0] == start and path[-1] == destination and path.size() == expected[destination] + 1, "Shortest path reconstructed with exact endpoints")
						for step in range(1, path.size()):
							check(grid.are_neighbors(path[step - 1], path[step]) and not blocked.has(path[step]), "Every step adjacent and unoccupied")
					var result: GameRules.Result = rules.try_move(1, 1, destination)
					check(result.success == legal and result.path == path, "Execution agrees with preview and reachability")
					if legal:
						check(state.units[1].moved and state.unit_at(destination) == state.units[1] and state.unit_at(start) == null, "Move commits occupancy and action")
						reject(state, 1, 1, start)
						state.units[1].cell_id = start
						state.units[1].moved = false
					else:
						check(TestState.snapshot(state) == before, "Rejected destination does not mutate")
	check(detours > 0, "Blocker fixtures include affordable detours longer than unobstructed graph range")
	for start in [0, 12, 50]:
		var expected: Dictionary = distances(start, {})
		for destination: int in expected:
			check(grid.get_graph_distance(start, destination) == expected[destination] and grid.distance(destination, start) == expected[destination], "Graph distance matches independent oracle in both directions")
	check(grid.find_path(-1, 0).is_empty() and grid.find_path(0, -1).is_empty(), "Invalid path endpoints")
	check(grid.find_path(0, grid.get_neighbors(0)[0], 0).is_empty(), "Path limit respected")
	check(grid.find_path(0, grid.get_neighbors(0)[0], -1, {grid.get_neighbors(0)[0]: true}).is_empty(), "Blocked path target")
	var state: GameState = fixture()
	var neighbor: int = grid.get_neighbors(0)[0]
	for actor in [-1, 0, 2, 3]:
		reject(state, actor, 1, neighbor)
		var before: String = TestState.snapshot(state)
		check(not GameRules.new(state).try_end_turn(actor).success and TestState.snapshot(state) == before, "Invalid end-turn immutable")
	for id in [-1, 0, 999]:
		reject(state, 1, id, neighbor)
	for destination in [-1, grid.get_cell_count(), 0, grid.breadth_first(0).order[-1]]:
		reject(state, 1, 1, destination)
	state.structures[100] = GameState.Structure.new(100, 1, "Headquarters", neighbor, 25)
	reject(state, 1, 1, neighbor)
	state.structures.clear()
	var rules := GameRules.new(state)
	check(rules.try_move(1, 1, neighbor).success, "Adjacent pentagon move")
	check(rules.try_end_turn(1).success and state.active_player == 2 and state.round_number == 1 and state.units[1].moved, "Outgoing action stays spent")
	check(rules.try_end_turn(2).success and state.active_player == 1 and state.round_number == 2 and not state.units[1].moved, "Incoming turn restores action")
	check(state.units[1].cell_id == neighbor and rules.try_move(1, 1, 0).success, "Position survives turns and next move works")
	var same_grid: PlanetGrid = state.grid
	var fingerprint: String = grid.fingerprint
	for repeat in range(3):
		rules.restart_match()
		check(state.grid == same_grid and state.grid.fingerprint == fingerprint and TestState.snapshot(state) == TestState.snapshot(initial), "Restart retains cached topology and exact initial state")
	print("Movement checks complete: ", checks, "; failures=", failures)
	quit(0 if failures == 0 else 1)
