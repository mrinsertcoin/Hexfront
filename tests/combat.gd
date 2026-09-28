extends SceneTree

var failures: int = 0
var grid := PlanetGrid.new(3)
var route: Array[int] = grid.find_path(0, grid.breadth_first(0).order[-1])

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func snapshot(state: GameState) -> String:
	return preload("res://tests/test_state.gd").snapshot(state)

func fixture(kind: String = "Infantry", destination: int = -1) -> GameState:
	var state := GameState.new(grid)
	state.units.clear()
	state.units[1] = GameState.Unit.new(1, 1, kind, 0)
	state.units[2] = GameState.Unit.new(2, 2, "Scout", route[1] if destination == -1 else destination)
	state.units[3] = GameState.Unit.new(3, 2, "Infantry", route[-1])
	state.units[4] = GameState.Unit.new(4, 1, "Scout", grid.get_neighbors(0)[1])
	return state

func reject_attack(state: GameState, actor: int, attacker: int, target: int, context: String) -> void:
	var rules := GameRules.new(state)
	var before: String = snapshot(state)
	var preview: GameRules.Result = rules.preview_attack(actor, attacker, target)
	var result: GameRules.Result = rules.try_attack(actor, attacker, target)
	check(not preview.success and not result.success, context + ": rejected by preview and command")
	check(not result.reason.is_empty(), context + ": useful feedback")
	check(snapshot(state) == before, context + ": complete state unchanged")

func compare_preview(rules: GameRules, actor: int, attacker: int, target: int) -> GameRules.Result:
	var before: String = snapshot(rules.state)
	var preview: GameRules.Result = rules.preview_attack(actor, attacker, target)
	check(snapshot(rules.state) == before, "Preview changes no state")
	var result: GameRules.Result = rules.try_attack(actor, attacker, target)
	check(result.success == preview.success and result.damage == preview.damage and result.target_hp == preview.target_hp and result.killed == preview.killed and result.winner_id == preview.winner_id, "Preview matches authoritative result")
	return result

func test_ranges() -> void:
	for start: int in [0, 12, 100]:
		for kind: String in UnitTypes.STATS:
			var range_limit: int = int(UnitTypes.STATS[kind]["range"])
			for cell: int in grid.get_cells_within_distance(start, range_limit + 1):
				if cell == start:
					continue
				var state: GameState = fixture(kind)
				state.units[1].cell_id = start
				state.units[2].cell_id = cell
				var rules := GameRules.new(state)
				if grid.distance(start, cell) <= range_limit:
					check(compare_preview(rules, 1, 1, 2).success, "All cells within graph range accepted, including pentagons")
					check(state.units[2].hp == state.units[2].max_hp - state.units[1].attack_damage, "Fixed damage preserved")
				else:
					reject_attack(state, 1, 1, 2, "One beyond graph range")
	for owner in [1, 2]:
		var state: GameState = fixture("Gunner", route[2])
		state.units[4].cell_id = route[1]
		state.units[4].owner_id = owner
		check(GameRules.new(state).try_attack(1, 1, 2).success, "Ranged attack ignores intervening units")

func test_actions_and_turns() -> void:
	var state: GameState = fixture("Infantry", route[2])
	var rules := GameRules.new(state)
	check(rules.try_move(1, 1, route[1]).success, "Move before attack")
	check(compare_preview(rules, 1, 1, 2).success, "Attack after moving succeeds")
	check(state.units[1].hp == state.units[1].max_hp, "No retaliation")
	reject_attack(state, 1, 1, 2, "Second attack")
	state = fixture()
	rules = GameRules.new(state)
	check(rules.try_attack(1, 1, 2).success, "Attack before movement succeeds")
	check(state.units[1].attacked and state.units[1].moved, "Attacking spends attack and forfeits movement")
	var before: String = snapshot(state)
	check(not rules.try_move(1, 1, grid.get_neighbors(0)[2]).success, "Attack then move rejected")
	check(snapshot(state) == before and rules.reachable(1, 1).is_empty(), "No movement mutation or highlights after attack")
	check(rules.try_end_turn(1).success, "Switch to Player 2")
	check(state.units[1].attacked and not state.units[2].attacked, "Only incoming player's actions reset")
	check(rules.try_attack(2, 2, 1).success, "Player 2 attacks")
	var damaged_hp: int = state.units[1].hp
	check(rules.try_end_turn(2).success, "Switch back to Player 1")
	check(not state.units[1].moved and not state.units[1].attacked and state.round_number == 2, "Both P1 actions restored")
	check(state.units[2].attacked and state.units[2].moved and state.units[1].hp == damaged_hp, "Outgoing actions stay spent and damage persists")
	check(rules.try_end_turn(1).success and not state.units[2].attacked and not state.units[2].moved, "Both P2 actions restored")

func test_invalid_attacks() -> void:
	var state: GameState = fixture()
	reject_attack(state, 2, 1, 2, "Out of turn")
	reject_attack(state, 1, 2, 1, "Wrong owner")
	reject_attack(state, 0, 1, 2, "Unknown player")
	reject_attack(state, 1, 1, 4, "Friendly target")
	reject_attack(state, 1, 1, 1, "Self target")
	reject_attack(state, 1, 999, 2, "Missing attacker")
	reject_attack(state, 1, 1, 999, "Missing target")
	reject_attack(state, 1, 1, 3, "Out of range")
	state.units[1].moved = true
	reject_attack(state, 1, 1, 3, "Failed attack preserves previously spent movement")
	state.units[1].hp = 0
	reject_attack(state, 1, 1, 2, "Dead attacker")
	state = fixture()
	state.units[2].hp = 0
	reject_attack(state, 1, 1, 2, "Dead target")

func test_death_and_victory() -> void:
	var state: GameState = fixture()
	var rules := GameRules.new(state)
	var target: GameState.Unit = state.units[2]
	var dead_hex: int = target.cell_id
	target.hp = 1
	var result: GameRules.Result = compare_preview(rules, 1, 1, 2)
	check(result.success and result.killed and result.damage == state.units[1].attack_damage and result.target_hp == 0 and target.hp == 0, "Overkill clamps HP to zero")
	check(not state.units.has(2) and state.unit_at(dead_hex) == null, "Death removes active state and occupancy")
	check(state.winner_id == 0 and result.winner_id == 0, "One remaining enemy prevents premature victory")
	check(not rules.attack_targets(1, 4).has(2), "Dead target excluded from targeting")
	check(rules.try_move(1, 4, dead_hex).success, "Another unit can move into the vacated hex")
	reject_attack(state, 1, 4, 2, "Removed target")

	for winner: int in [1, 2]:
		state = fixture()
		state.units.erase(3)
		state.active_player = winner
		state.units[1].owner_id = winner
		state.units[4].owner_id = winner
		state.units[2].owner_id = 3 - winner
		state.units[2].hp = 1
		rules = GameRules.new(state)
		# Eliminating the final enemy unit no longer yields victory while an HQ exists
		result = compare_preview(rules, winner, 1, 2)
		check(result.killed and result.winner_id == 0 and state.winner_id == 0, "Final enemy does not declare victory without HQ destruction")
		var before: String = snapshot(state)
		# No HQ destroyed -> commands should still be allowed
		check(rules.try_move(winner, 4, rules.reachable(winner, 4)[0]).success, "Ready unit can move when no HQ destroyed")
		check(snapshot(state) != before, "State changes when no victory is declared")
		check(rules.try_end_turn(winner).success, "Turn can advance when no HQ destroyed")
		var initial: String = snapshot(GameState.new(grid))
		for repetition in range(3):
			rules.restart_match()
			check(snapshot(state) == initial, "Restart restores exact initial logical state")
			check(rules.try_move(1, 1, rules.reachable(1, 1)[0]).success, "Restarted state accepts commands")
			check(rules.try_end_turn(1).success, "Restarted state can advance turns")

	# Headquarters destruction wins immediately
	var state2: GameState = GameState.new(grid)
	# Clear default units and place an attacker and enemy HQ
	state2.units.clear()
	state2.units[1] = GameState.Unit.new(1, 1, "Infantry", 0)
	# Enemy headquarters in range and low HP
	state2.structures.clear()
	state2.structures[200] = GameState.Structure.new(200, 2, "Headquarters", route[1], 1)
	rules = GameRules.new(state2)
	var preview_hq: GameRules.Result = rules.preview_attack(1, 1, 200)
	check(preview_hq.success and preview_hq.killed and preview_hq.winner_id == 1, "Preview shows HQ death declares winner")
	var result_hq: GameRules.Result = rules.try_attack(1, 1, 200)
	check(result_hq.success and result_hq.killed and result_hq.winner_id == 1 and state2.winner_id == 1, "Attacking HQ declares correct winner")

func _run() -> void:
	test_ranges()
	test_actions_and_turns()
	test_invalid_attacks()
	test_death_and_victory()
	print("Combat checks complete: range, actions, previews, death, victory, restart; failures=", failures)
	quit(0 if failures == 0 else 1)
