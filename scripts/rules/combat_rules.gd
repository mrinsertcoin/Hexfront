class_name CombatRules
extends RefCounted

var state: GameState
func _init(game_state: GameState) -> void: state=game_state

func attack_error(actor: int,attacker_id: int,target_id: int) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not state.units.has(attacker_id) or state.units[attacker_id].hp<=0: return "The attacker does not exist or is no longer alive."
	var target_is_unit:=state.units.has(target_id)
	var target_is_structure:=state.structures.has(target_id)
	var target_is_site:=state.world_sites.has(target_id)
	if not target_is_unit and not target_is_structure and not target_is_site: return "The target does not exist or is no longer alive."
	var attacker: GameState.Unit=state.units[attacker_id]
	var target: RefCounted=state.combat_target(target_id)
	if target.hp<=0: return "The target does not exist or is no longer alive."
	if attacker.controller_id!=actor: return "You can only attack with your own units."
	if attacker_id==target_id: return "A unit cannot attack itself."
	if not state.entities_are_hostile(attacker,target) and not state.player_can_attack_target(actor,target): return "Choose a non-allied target."
	var controller: ControllerState=state.controllers.get(actor) as ControllerState
	if controller!=null and controller.kind==ControllerState.NEUTRAL_AI:
		if attacker.neutral_awareness_range>0 and state.grid.distance(attacker.cell_id,target.cell_id)>attacker.neutral_awareness_range:
			return "Target is outside this neutral unit's awareness."
	else:
		var observer_team:=state.visibility_system.team_id_for_controller(actor)
		if target_is_site:
			if not state.visibility_system.has_discovered_site(observer_team,target_id) or not state.visibility_system.is_visible(observer_team,target.cell_id): return "Target is not currently observed."
		elif not state.visibility_system.can_observe_entity(observer_team,target_id): return "Target is not currently observed."
	if attacker.attacked: return "This unit has already attacked this turn."
	if attacker.disconnected_turns>=2: return "This disconnected unit cannot accept offensive orders."
	if state.grid.distance(attacker.cell_id,target.cell_id)>UnitStatResolver.attack_range(attacker,state.registry):
		return "Target is out of range (range %d)." % UnitStatResolver.attack_range(attacker,state.registry)
	return ""

func preview_attack(actor: int,attacker_id: int,target_id: int) -> RuleResult:
	var error:=attack_error(actor,attacker_id,target_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var attacker: GameState.Unit=state.units[attacker_id]
	var target: RefCounted=state.combat_target(target_id)
	var damage:=UnitStatResolver.attack_damage_against(attacker,target,state.registry)
	var result:=RuleResult.new(true,"%s dealt %d damage to %s." % [attacker.unit_type,damage,
		_target_name(target)])
	result.damage=damage; result.target_hp=maxi(0,target.hp-damage); result.killed=result.target_hp==0
	if result.killed:
		result.reason+=" %s destroyed." % _target_name(target)
		if _is_headquarters(target) and not _has_other_headquarters(target.controller_id,target.id):
			var survivors:=state.alive_player_ids()
			survivors.erase(target.controller_id)
			if survivors.size()==1: result.winner_id=survivors[0]
	return result

func attack_targets(actor: int,attacker_id: int) -> Array[int]:
	var result: Array[int]=[]
	for id: int in state.units:
		if preview_attack(actor,attacker_id,id).success: result.append(id)
	for id: int in state.structures:
		if preview_attack(actor,attacker_id,id).success: result.append(id)
	for id: int in state.world_sites:
		if preview_attack(actor,attacker_id,id).success: result.append(id)
	return result

func try_attack(actor: int,attacker_id: int,target_id: int) -> RuleResult:
	var result:=preview_attack(actor,attacker_id,target_id)
	if not result.success: return result
	var attacker: GameState.Unit=state.units[attacker_id]
	attacker.attacked=true; attacker.moved=true
	var target: RefCounted=state.combat_target(target_id)
	if state.players.has(actor): state.provoke_attack_target(actor,target)
	if state.players.has(target.controller_id):
		attacker.revealed_to_teams[state.controllers[target.controller_id].team_id]=state.turn_state.serial+1
	target.hp=result.target_hp
	if target is GameState.Structure and target.pillar_state!=null and result.damage>0:
		var faction:=state.registry.faction(state.players[target.controller_id].faction_id)
		var divisor: int=(faction.gameplay_config as BaumeisterConfig).integrity_damage_divisor if faction.gameplay_config is BaumeisterConfig else 1
		target.pillar_state.integrity=maxi(0,target.pillar_state.integrity-int(ceil(float(result.damage)/float(divisor))))
	if result.killed:
		if target is GameState.Unit: state.remove_unit(target_id)
		elif target is GameState.Structure: state.remove_structure(target_id)
		else: state.destroy_world_site(target_id,actor)
	if state.players.has(target.controller_id):
		var eliminated:=state.evaluate_player_survival(target.controller_id,"Last survival headquarters destroyed")
		if eliminated: result.reason+=" Player %d has been eliminated." % target.controller_id
	result.winner_id=state.winner_id
	if result.winner_id!=0: result.reason+=" Player %d wins!" % result.winner_id
	return result

func _is_headquarters(entity: RefCounted) -> bool:
	if entity is WorldSiteState: return false
	var definition: Resource=state.registry.unit(entity.definition_id) if entity is GameState.Unit else state.registry.structure(entity.definition_id)
	return definition!=null and "headquarters" in definition.tags

func _has_other_headquarters(controller_id: int,excluded_id: int) -> bool:
	for unit: GameState.Unit in state.units.values():
		if unit.id!=excluded_id and unit.controller_id==controller_id and unit.hp>0 and _is_headquarters(unit): return true
	for structure: GameState.Structure in state.structures.values():
		if structure.id!=excluded_id and structure.controller_id==controller_id and structure.hp>0 and _is_headquarters(structure): return true
	return false

func _is_deliberate_village_attack(attacker: GameState.Unit,target: RefCounted) -> bool:
	if not state.players.has(attacker.controller_id): return false
	if target is WorldSiteState:
		var site_definition:=state.registry.world_site(target.definition_id)
		return site_definition!=null and site_definition.category=="village" and not target.runtime_state.get("destroyed",false)
	if target is GameState.Unit:
		return target.home_site_id>=0 and "village_guard" in state.registry.unit(target.definition_id).tags
	return false

func _target_name(target: RefCounted) -> String:
	if target is GameState.Unit: return target.unit_type
	if target is GameState.Structure: return target.structure_type
	var definition:=state.registry.world_site(target.definition_id)
	return definition.display_name if definition!=null else "site"
