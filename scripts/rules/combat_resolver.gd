class_name CombatResolver
extends RefCounted
## Resolves all intents from one immutable HP/position snapshot, then commits.

var state: GameState

func _init(game_state: GameState) -> void: state=game_state

func resolve(intents: Dictionary[int,CombatIntent]) -> Array[Dictionary]:
	var snapshot: Dictionary[int,Dictionary]={}
	for unit: GameState.Unit in state.units.values():
		snapshot[unit.id]={"hp":unit.hp,"cell_id":unit.cell_id,"controller_id":unit.controller_id,"definition_id":unit.definition_id}
	for structure: GameState.Structure in state.structures.values():
		snapshot[structure.id]={"hp":structure.hp,"cell_id":structure.cell_id,"controller_id":structure.controller_id,"definition_id":structure.definition_id,"structure":true}
	for site: WorldSiteState in state.world_sites.values():
		if site.max_hp>0 and not site.runtime_state.get("destroyed",false): snapshot[site.id]={"hp":site.hp,"cell_id":site.cell_id,"controller_id":site.controller_id,"definition_id":site.definition_id,"site":true}
	var damage_totals: Dictionary[int,int]={}; var outcomes: Array[Dictionary]=[]
	var counter_triggers: Dictionary[int,int]={}
	var attacker_ids: Array[int]=[]
	for unit_id: int in intents:
		if intents[unit_id].option_id=="attack": attacker_ids.append(unit_id)
	attacker_ids.sort()
	for attacker_id: int in attacker_ids:
		var intent: CombatIntent=intents[attacker_id]; var target_id:=intent.target_id
		if not snapshot.has(attacker_id) or not snapshot.has(target_id): continue
		var attacker_row: Dictionary=snapshot[attacker_id]; var target_row: Dictionary=snapshot[target_id]
		if int(attacker_row.hp)<=0 or int(target_row.hp)<=0: continue
		var attacker: GameState.Unit=state.units.get(attacker_id) as GameState.Unit
		if attacker==null or attacker.attacked: continue
		var target: RefCounted=state.combat_target(target_id)
		# Orders are revalidated against the final movement positions and current
		# ownership. Invalid orders are discarded and never hold up the round.
		if target==null or intent.controller_id!=attacker.controller_id: continue
		if state.players.has(attacker.controller_id) and state.players[attacker.controller_id].eliminated: continue
		if not state.entities_are_hostile(attacker,target): continue
		if attacker.disconnected_turns>=2: continue
		if state.grid.distance(int(attacker_row.cell_id),int(target_row.cell_id))>UnitStatResolver.attack_range(attacker,state.registry): continue
		var raw:=UnitStatResolver.attack_damage_against(attacker,target,state.registry)
		var reduction:=0; var defense: CombatIntent=intents.get(target_id) as CombatIntent
		var countered:=false
		if defense!=null and defense.option_id=="dodge": reduction=state.registry.combat_option("dodge").damage_reduction
		elif defense!=null and defense.option_id=="counter":
			var option:=state.registry.combat_option("counter")
			var used:=int(counter_triggers.get(target_id,0))
			if used<option.trigger_limit:
				reduction=option.damage_reduction; countered=true; counter_triggers[target_id]=used+1
				damage_totals[attacker_id]=int(damage_totals.get(attacker_id,0))+option.retaliation_damage
				outcomes.append({"kind":"counter","source_id":target_id,"target_id":attacker_id,"damage":option.retaliation_damage})
		var dealt:=maxi(0,raw-reduction)
		damage_totals[target_id]=int(damage_totals.get(target_id,0))+dealt
		outcomes.append({"kind":"attack","source_id":attacker_id,"target_id":target_id,"raw_damage":raw,"damage":dealt,"reduction":reduction,"countered":countered})
	for unit_id: int in counter_triggers:
		# The immediate round-boundary tick follows this batch, so seed one above
		# the authored value to display the full configured cooldown next round.
		if state.units.has(unit_id): state.units[unit_id].counter_cooldown_remaining=state.registry.combat_option("counter").cooldown_rounds+1
	var target_ids: Array[int]=[]
	for id: int in damage_totals: target_ids.append(id)
	target_ids.sort()
	var killed_units: Array[int]=[]; var killed_structures: Array[int]=[]; var killed_sites: Array[int]=[]
	for target_id: int in target_ids:
		if state.units.has(target_id):
			var unit: GameState.Unit=state.units[target_id]; unit.hp=maxi(0,int(snapshot[target_id].hp)-int(damage_totals[target_id]))
			if unit.hp==0: killed_units.append(target_id)
		elif state.structures.has(target_id):
			var structure: GameState.Structure=state.structures[target_id]; structure.hp=maxi(0,int(snapshot[target_id].hp)-int(damage_totals[target_id]))
			if structure.hp==0: killed_structures.append(target_id)
		elif state.world_sites.has(target_id):
			var site: WorldSiteState=state.world_sites[target_id]; site.hp=maxi(0,int(snapshot[target_id].hp)-int(damage_totals[target_id]))
			if site.hp==0: killed_sites.append(target_id)
	for id: int in killed_units: state.remove_unit(id)
	for id: int in killed_structures: state.remove_structure(id)
	for id: int in killed_sites: state.destroy_world_site(id)
	for controller_id: int in state.players: state.evaluate_player_survival(controller_id,"Last survival headquarters destroyed")
	return outcomes
