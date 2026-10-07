class_name CombatPlanningRules
extends RefCounted

var state: GameState
var resolver: CombatResolver

func _init(game_state: GameState) -> void:
	state=game_state; resolver=CombatResolver.new(state)

func eligible_unit_ids(controller_id: int) -> Array[int]:
	var result: Array[int]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id and unit.hp>0 and unit.attack_damage>0: result.append(unit.id)
	result.sort(); return result

func attack_targets(controller_id: int,unit_id: int) -> Array[int]:
	var result: Array[int]=[]
	if not state.units.has(unit_id) or state.units[unit_id].controller_id!=controller_id: return result
	for id: int in state.units:
		if _attack_intent_error(controller_id,unit_id,id).is_empty(): result.append(id)
	for id: int in state.structures:
		if _attack_intent_error(controller_id,unit_id,id).is_empty(): result.append(id)
	result.sort(); return result

func submit_intent(controller_id: int,unit_id: int,option_id: String,target_id: int=-1) -> RuleResult:
	if state.turn_state.phase!=TurnState.COMBAT_PLANNING: return RuleResult.new(false,"Combat planning is not active.")
	if not state.players.has(controller_id) or state.players[controller_id].eliminated: return RuleResult.new(false,"Player is not eligible.")
	if state.combat_planning.is_locked(controller_id): return RuleResult.new(false,"Combat choices are locked.")
	if not state.units.has(unit_id) or state.units[unit_id].controller_id!=controller_id or unit_id not in eligible_unit_ids(controller_id): return RuleResult.new(false,"Choose an eligible owned unit.")
	var option:=state.registry.combat_option(option_id)
	if option==null: return RuleResult.new(false,"Unknown combat option.")
	if option_id=="counter" and state.units[unit_id].counter_cooldown_remaining>0: return RuleResult.new(false,"Counter is on cooldown.")
	if option.requires_target:
		var error:=_attack_intent_error(controller_id,unit_id,target_id)
		if not error.is_empty(): return RuleResult.new(false,error)
	elif target_id!=-1: return RuleResult.new(false,"This combat option does not take a target.")
	state.combat_planning.intents[unit_id]=CombatIntent.new(controller_id,unit_id,option_id,target_id,state.round_number)
	return RuleResult.new(true,"%s planned for %s." % [state.units[unit_id].unit_type,option.display_name])

func _attack_intent_error(controller_id: int,attacker_id: int,target_id: int) -> String:
	if not state.units.has(target_id) and not state.structures.has(target_id): return "Target does not exist."
	var attacker: GameState.Unit=state.units[attacker_id]
	var target: RefCounted=state.units[target_id] if state.units.has(target_id) else state.structures[target_id]
	if target.hp<=0 or not state.relationships.is_hostile(controller_id,target.controller_id): return "Choose a living hostile target."
	var team:=state.visibility_system.team_id_for_controller(controller_id)
	if not state.visibility_system.can_observe_entity(team,target_id): return "Target is not currently observed."
	if state.grid.distance(attacker.cell_id,target.cell_id)>attacker.attack_range: return "Target is out of range."
	return ""

func lock_player(controller_id: int) -> RuleResult:
	if state.turn_state.phase!=TurnState.COMBAT_PLANNING: return RuleResult.new(false,"Combat planning is not active.")
	if not state.players.has(controller_id) or state.players[controller_id].eliminated: return RuleResult.new(false,"Player is not eligible.")
	if state.combat_planning.is_locked(controller_id): return RuleResult.new(false,"Combat is already locked.")
	# Units without an explicit choice safely default to Dodge, guaranteeing one
	# intent per eligible unit without leaking whether hidden targets exist.
	for unit_id: int in eligible_unit_ids(controller_id):
		if not state.combat_planning.intents.has(unit_id): state.combat_planning.intents[unit_id]=CombatIntent.new(controller_id,unit_id,"dodge",-1,state.round_number)
	state.combat_planning.locked_players[controller_id]=true
	if all_alive_locked(): resolve_locked_combat()
	return RuleResult.new(true,"Combat choices locked.")

func all_alive_locked() -> bool:
	for player_id: int in state.alive_player_ids():
		if not state.combat_planning.is_locked(player_id): return false
	return true

func resolve_locked_combat() -> Array[Dictionary]:
	var outcomes:=resolver.resolve(state.combat_planning.intents)
	state.combat_planning.last_outcomes=outcomes.duplicate(true)
	state.combat_planning.resolution_serial+=1
	state.combat_planning.intents.clear(); state.combat_planning.locked_players.clear()
	state.turn_state.finish_combat()
	state.start_turn(); state.refresh_visibility()
	return outcomes
