extends SceneTree
const Snapshot = preload("res://tests/test_state.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func reject(state: GameState, actor: int, hq: int, kind: String, hex: int) -> void:
	var before: String = Snapshot.snapshot(state)
	var result: GameRules.Result = GameRules.new(state).try_recruit(actor, hq, kind, hex)
	check(not result.success and not result.reason.is_empty(), "Recruit request rejected with a reason")
	check(Snapshot.snapshot(state) == before, "Rejected recruitment leaves every field unchanged")

func spawn_cell(state: GameState) -> int:
	return state.grid.get_neighbors(0)[3]

func _run() -> void:
	var state := GameState.new()
	var rules := GameRules.new(state)
	check(state.materials == {1: 11, 2: 8}, "Initial income included in core initialization")
	var initial: String = Snapshot.snapshot(state)
	state.start_turn()
	rules._start_turn()
	check(Snapshot.snapshot(state) == initial, "Turn-start effects are idempotent")
	for kind: String in UnitTypes.COSTS:
		rules.restart_match()
		var id: int = state.next_id
		var before_query: String = Snapshot.snapshot(state)
		check(rules.recruit_destinations(1, 100, kind).has(spawn_cell(state)), "Legal placement query")
		check(Snapshot.snapshot(state) == before_query, "Recruit query is side-effect free")
		check(rules.try_recruit(1, 100, kind, spawn_cell(state)).success, "Recruit each unit type")
		check(state.units[id].hp == state.units[id].max_hp and state.units[id].ready_next_turn, "Recruit arrives at full HP, ready next turn")
		check(state.materials[1] == 11 - int(UnitTypes.COSTS[kind]) and not state.structures[100].recruit_available, "Deduct exact centralized cost and consume allowance")
		check(not rules.try_move(1, id, state.grid.get_neighbors(spawn_cell(state))[0]).success, "Recruit cannot move immediately")
		state.units[3].cell_id = state.grid.get_neighbors(spawn_cell(state))[0]
		check(not rules.try_attack(1, id, 3).success, "Recruit cannot attack immediately")
		reject(state, 1, 100, kind, spawn_cell(state))
		check(rules.try_end_turn(1).success and state.materials[2] == 11, "P2 first income")
		check(state.units[id].ready_next_turn, "Recruit still waits during opponent turn")
		check(rules.try_end_turn(2).success, "Return to recruiter")
		check(not state.units[id].ready_next_turn and not state.units[id].moved and not state.units[id].attacked, "Incoming turn restores both recruit actions")
		check(state.materials[1] == 14 - int(UnitTypes.COSTS[kind]) and state.structures[100].recruit_available, "Income and allowance restored once")
	rules.restart_match()
	reject(state, 2, 101, "Scout", state.grid.get_neighbors(state.structures[101].cell_id)[3])
	reject(state, 1, 101, "Scout", state.grid.get_neighbors(state.structures[101].cell_id)[3])
	reject(state, 1, 999, "Scout", spawn_cell(state))
	reject(state, 1, 100, "Unknown", spawn_cell(state))
	reject(state, 1, 100, "Scout", -1)
	reject(state, 1, 100, "Scout", state.grid.breadth_first(0).order[-2])
	reject(state, 1, 100, "Scout", state.units[1].cell_id)
	reject(state, 1, 100, "Scout", state.structures[100].cell_id)
	state.materials[1] = 0
	reject(state, 1, 100, "Scout", spawn_cell(state))
	rules.restart_match()
	state.structures[100].hp = 0
	reject(state, 1, 100, "Scout", spawn_cell(state))
	rules.restart_match()
	state.structures[100].structure_type = "Depot"
	reject(state, 1, 100, "Scout", spawn_cell(state))
	rules.restart_match()
	for hex: int in rules.recruit_destinations(1, 100, "Scout"):
		var id: int = state.allocate_id()
		state.units[id] = GameState.Unit.new(id, 1, "Infantry", hex)
	check(rules.recruit_destinations(1, 100, "Scout").is_empty(), "Blocked HQ has no placements")
	for destination: int in state.grid.get_neighbors(state.structures[100].cell_id):
		reject(state, 1, 100, "Scout", destination)
	rules.restart_match()
	state.next_id = 100
	check(rules.try_recruit(1, 100, "Scout", spawn_cell(state)).success and state.units.has(102), "ID allocation skips existing structure IDs")
	rules.restart_match()
	check(not rules.reachable(1, 1).has(state.structures[100].cell_id), "HQ blocks movement")
	check(not rules.try_move(1, 1, state.structures[100].cell_id).success, "HQ cannot be occupied by movement")
	check(not rules.try_move(1, 100, spawn_cell(state)).success and not rules.try_attack(1, 100, 3).success, "HQ cannot move or attack")

	for winner: int in [1, 2]:
		rules.restart_match()
		state.active_player = winner
		state.units.clear()
		var enemy_hq: int = 101 if winner == 1 else 100
		var target_hex: int = state.structures[enemy_hq].cell_id
		var source_hex: int = state.grid.get_neighbors(target_hex)[0]
		state.units[1] = GameState.Unit.new(1, winner, "Gunner", source_hex)
		state.units[2] = GameState.Unit.new(2, 3 - winner, "Scout", state.grid.breadth_first(target_hex).order[-1])
		state.units[4] = GameState.Unit.new(4, winner, "Scout", state.grid.breadth_first(0).order[-2])
		state.structures[enemy_hq].hp = 1
		var before: String = Snapshot.snapshot(state)
		var preview: GameRules.Result = rules.preview_attack(winner, 1, enemy_hq)
		check(preview.killed and preview.winner_id == winner and Snapshot.snapshot(state) == before, "HQ lethal preview is pure")
		check(rules.try_attack(winner, 1, enemy_hq).winner_id == winner and state.units.has(2), "HQ death wins with enemy troops surviving")
		before = Snapshot.snapshot(state)
		check(not rules.try_move(winner, 4, state.grid.get_neighbors(state.units[4].cell_id)[0]).success, "No moves after victory")
		check(not rules.try_attack(winner, 4, 2).success, "No attacks after victory")
		check(not rules.try_end_turn(winner).success, "No turns after victory")
		reject(state, winner, 100 if winner == 1 else 101, "Scout", spawn_cell(state))
		check(Snapshot.snapshot(state) == before, "Victory rejects all mutation")
		for repetition in range(3):
			rules.restart_match()
			check(Snapshot.snapshot(state) == initial, "Repeated restart restores exact economy and IDs")
	print("Economy checks: income, recruitment, blockers, HQ victory, immutable rejection, restart; failures=", failures)
	quit(0 if failures == 0 else 1)
