extends SceneTree
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func apply_action(state: GameState, rules: GameRules, ai: SimpleAI) -> String:
	var action: Dictionary = ai.choose_action(state, rules, state.active_player)
	var result: GameRules.Result
	match action.get("type", "end"):
		"move": result = rules.try_move(state.active_player, action.unit, action.dest)
		"attack": result = rules.try_attack(state.active_player, action.attacker, action.target)
		"recruit": result = rules.try_recruit(state.active_player, action.hq_id, action.kind, action.dest)
		_: result = rules.try_end_turn(state.active_player)
	check(result.success, "AI action must be accepted: " + str(action) + " / " + result.reason)
	ai.record_result(action, result.success)
	return action.get("type", "end")

func _run() -> void:
	var state := GameState.new(null,{"simultaneous_combat":false})
	var rules := GameRules.new(state)
	var agents: Array[SimpleAI] = [SimpleAI.new(), SimpleAI.new()]
	# Two independent deterministic matches: a passive human and AI versus AI.
	for mode: int in [0, 1]:
		rules.restart_match()
		for agent: SimpleAI in agents:
			agent.reset()
		var total_actions: int = 0
		for turn in range(200):
			if state.winner_id != 0:
				break
			var actor: int = state.active_player
			if mode == 0 and actor == 1:
				rules.try_end_turn(actor)
				continue
			var budget: int = maxi(8, state.units.size() * 3)
			for action_index in range(budget):
				total_actions += 1
				if apply_action(state, rules, agents[actor - 1]) == "end" or state.winner_id != 0:
					break
			check(state.winner_id != 0 or state.active_player != actor, "AI turn terminates within bounded actions")
			if state.winner_id == 0 and state.active_player == actor:
				rules.try_end_turn(actor)
		check(state.winner_id != 0, "AI match reaches headquarters victory within 200 turns")
		print("AI simulation mode=", mode, " winner=", state.winner_id, " round=", state.round_number, " actions=", total_actions)
	# A completely blocked HQ with no movable units must yield, not retry forever.
	rules.restart_match()
	state.units.clear()
	for hex: int in rules.recruit_destinations(1, 100, "Scout"):
		var id: int = state.allocate_id()
		state.units[id] = GameState.Unit.new(id, 1, "Infantry", hex)
		state.units[id].moved = true
		state.units[id].attacked = true
	check(agents[0].choose_action(state, rules, 1).get("type") == "end", "Blocked AI ends turn")
	print("AI checks complete; failures=", failures)
	quit(0 if failures == 0 else 1)

