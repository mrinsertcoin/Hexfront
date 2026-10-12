class_name CombatOrderRules
extends RefCounted

var state: GameState
var resolver: CombatResolver

func _init(game_state: GameState) -> void:
	state=game_state; resolver=CombatResolver.new(state)

func eligible_unit_ids(controller_id: int) -> Array[int]:
	var result: Array[int]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id and unit.hp>0 and unit.attack_damage>0 and not unit.attacked: result.append(unit.id)
	result.sort(); return result

func attack_targets(controller_id: int,unit_id: int) -> Array[int]:
	var result: Array[int]=[]
	if not state.units.has(unit_id) or state.units[unit_id].controller_id!=controller_id: return result
	for id: int in state.units:
		if _attack_intent_error(controller_id,unit_id,id).is_empty(): result.append(id)
	for id: int in state.structures:
		if _attack_intent_error(controller_id,unit_id,id).is_empty(): result.append(id)
	for id: int in state.world_sites:
		if _attack_intent_error(controller_id,unit_id,id).is_empty(): result.append(id)
	result.sort(); return result

func submit_intent(controller_id: int,unit_id: int,option_id: String,target_id: int=-1) -> RuleResult:
	var authority_error:=RuleAuthority.actor_error(state,controller_id)
	if not authority_error.is_empty(): return RuleResult.new(false,authority_error)
	if not state.units.has(unit_id) or state.units[unit_id].controller_id!=controller_id or unit_id not in eligible_unit_ids(controller_id): return RuleResult.new(false,"Choose an eligible owned unit.")
	var option:=state.registry.combat_option(option_id)
	if option==null: return RuleResult.new(false,"Unknown combat option.")
	if option_id=="counter" and state.units[unit_id].counter_cooldown_remaining>0: return RuleResult.new(false,"Counter is on cooldown.")
	if option.requires_target:
		var error:=_attack_intent_error(controller_id,unit_id,target_id)
		if not error.is_empty(): return RuleResult.new(false,error)
	elif target_id!=-1: return RuleResult.new(false,"This combat option does not take a target.")
	state.combat_orders.intents[unit_id]=CombatIntent.new(controller_id,unit_id,option_id,target_id,state.round_number)
	if option_id=="attack" and state.players.has(controller_id): state.provoke_attack_target(controller_id,state.combat_target(target_id))
	return RuleResult.new(true,"%s queued for %s. Resolves after movement phases." % [option.display_name,state.units[unit_id].unit_type])

func clear_intent(controller_id: int,unit_id: int) -> RuleResult:
	var authority_error:=RuleAuthority.actor_error(state,controller_id)
	if not authority_error.is_empty(): return RuleResult.new(false,authority_error)
	if not state.combat_orders.intents.has(unit_id) or state.combat_orders.intents[unit_id].controller_id!=controller_id:
		return RuleResult.new(false,"This unit has no queued combat order.")
	state.combat_orders.intents.erase(unit_id)
	return RuleResult.new(true,"Combat order cancelled.")

func _attack_intent_error(controller_id: int,attacker_id: int,target_id: int) -> String:
	if not state.units.has(target_id) and not state.structures.has(target_id) and not state.world_sites.has(target_id): return "Target does not exist."
	var attacker: GameState.Unit=state.units[attacker_id]
	var target: RefCounted=state.combat_target(target_id)
	if target.hp<=0 or (not state.entities_are_hostile(attacker,target) and not state.player_can_attack_target(controller_id,target)): return "Choose a living non-allied target."
	# Human/AI players are constrained by fog. Neutral AI already applies its
	# authored awareness and leash when choosing an action and has no player fog
	# observation of its own.
	if state.players.has(controller_id):
		var team:=state.visibility_system.team_id_for_controller(controller_id)
		if target is WorldSiteState:
			if not state.visibility_system.has_discovered_site(team,target_id) or not state.visibility_system.is_visible(team,target.cell_id): return "Target is not currently observed."
		elif not state.visibility_system.can_observe_entity(team,target_id): return "Target is not currently observed."
	if state.grid.distance(attacker.cell_id,target.cell_id)>UnitStatResolver.attack_range(attacker,state.registry): return "Target is out of range."
	return ""

func _is_deliberate_village_target(controller_id: int,target: RefCounted) -> bool:
	if not state.players.has(controller_id): return false
	if target is WorldSiteState:
		var definition:=state.registry.world_site(target.definition_id)
		return definition!=null and definition.category=="village" and not target.runtime_state.get("destroyed",false)
	if target is GameState.Unit:
		return target.home_site_id>=0 and "village_guard" in state.registry.unit(target.definition_id).tags
	return false

func resolve_pending_combat() -> Array[Dictionary]:
	if state.turn_state.phase!=TurnState.COMBAT_RESOLUTION: return []
	var valid_intents: Dictionary[int,CombatIntent]={}
	for unit_id: int in state.combat_orders.intents:
		var intent: CombatIntent=state.combat_orders.intents[unit_id]
		if intent.submitted_round!=state.round_number: continue
		if not state.controllers.has(intent.controller_id): continue
		if state.players.has(intent.controller_id) and state.players[intent.controller_id].eliminated: continue
		if not state.units.has(unit_id) or state.units[unit_id].controller_id!=intent.controller_id: continue
		if state.units[unit_id].attacked or state.registry.combat_option(intent.option_id)==null: continue
		if intent.option_id=="counter" and state.units[unit_id].counter_cooldown_remaining>0: continue
		valid_intents[unit_id]=intent
	var outcomes:=resolver.resolve(valid_intents)
	state.combat_orders.last_outcomes=outcomes.duplicate(true)
	state.combat_orders.resolution_serial+=1
	state.combat_orders.intents.clear()
	state.turn_state.finish_combat()
	state.refresh_visibility()
	return outcomes
