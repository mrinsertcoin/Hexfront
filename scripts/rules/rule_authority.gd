class_name RuleAuthority
extends RefCounted

static func actor_error(state: GameState,actor: int) -> String:
	if state.winner_id!=0: return "Match over. Player %d wins. Restart to play again." % state.winner_id
	if not state.controllers.has(actor): return "Unknown controller."
	if state.turn_state.neutral_phase:
		if state.controllers[actor].kind!=ControllerState.NEUTRAL_AI: return "Neutral activity is in progress."
		return ""
	if state.turn_state.phase==TurnState.COMBAT_RESOLUTION: return "Combat is resolving."
	if not state.players.has(actor): return "Unknown player."
	if state.players[actor].eliminated: return "This player has been eliminated."
	if not state.turn_state.can_act(actor):
		return "This player has completed movement." if state.turn_state.simultaneous_player_turns_enabled and state.turn_state.simultaneous_stage_started else "It is Player %d's turn." % state.active_player
	return ""
