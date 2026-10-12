class_name SimpleAI
extends RefCounted

var _pref_seq: Array[String] = ["prototype_infantry", "prototype_infantry", "prototype_gunner", "prototype_scout"]
var _pref_index: int = 0

func recruitment_preferences(rules: GameRules,player_id: int) -> PackedStringArray:
	var available:=rules.available_units(player_id)
	var result:=PackedStringArray()
	# Retain prototype behavior, then fall back to every authored roster entry so
	# additional factions do not require a parallel AI implementation.
	for unit_id: String in _pref_seq:
		if unit_id in available: result.append(unit_id)
	for unit_id: String in available:
		if unit_id not in result: result.append(unit_id)
	return result

func reset() -> void:
	_pref_index = 0

func record_result(action: Dictionary, success: bool) -> void:
	if success and action.get("type") == "recruit":
		_pref_index += 1

# Count enemy units that could attack a given tile (exposure heuristic)
func exposure(grid: PlanetGrid, enemy_units: Array[Dictionary], pos: int) -> int:
	var count := 0
	for eu: Dictionary in enemy_units:
		var dist := grid.distance(eu.cell_id, pos)
		if dist <= int(eu.get("attack_range",1)):
			count += 1
	return count

# Choose a single action given current state. Returns a Dictionary describing the action.
func choose_action(state: GameState, rules: GameRules, player_id: int) -> Dictionary:
	var grid: PlanetGrid = state.grid
	if state.winner_id != 0 or state.active_player != player_id:
		return {"type": "end"}
	if rules.living_migration_rules.is_living_migration(player_id):
		var living_action:=_living_migration_action(state,rules,player_id)
		if not living_action.is_empty(): return living_action
	if rules.baumeister_rules.is_baumeister(player_id):
		var builder_action:=_baumeister_action(state,rules,player_id)
		if not builder_action.is_empty(): return builder_action
	# Gather friendly units and enemy units
	var observation:=state.visibility_system.observation_for_controller(player_id)
	var my_units: Array[GameState.Unit] = []
	var enemy_units: Array[Dictionary] = []
	for u in state.units.values():
		if u.controller_id == player_id:
			my_units.append(u)
	for snapshot: Dictionary in observation.visible_entities.values():
		if snapshot.kind=="unit" and state.relationships.is_hostile(player_id,snapshot.controller_id):
			var definition:=state.registry.unit(snapshot.definition_id)
			snapshot.attack_range=definition.attack_range
			enemy_units.append(snapshot)

	# World interactions are explicit actions and only considered when already
	# adjacent; the tactical AI does not detour or spend scarce resources blindly.
	for site: WorldSiteState in rules.interactable_sites(player_id):
		for interaction: Dictionary in rules.available_site_interactions(player_id,site.id):
			if interaction.error.is_empty():
				return {"type":"site","site":site.id,"interaction":interaction.id,"unit":interaction.unit_id}

	# 1) Recruitment preference: try once per turn by caller; choose preferred affordable unit
	# Caller must ensure HQ recruit availability; here we only choose candidate and placement
	# Find HQs owned by player
	var hqs: Array[GameState.Structure] = []
	for s in state.structures.values():
		if s.controller_id == player_id and s.hp > 0 and "headquarters" in state.registry.structure(s.definition_id).tags:
			hqs.append(s)

	# Attempt to recruit if any HQ can and we can afford preferred
	var recruitment_ids:=recruitment_preferences(rules,player_id)
	for pref_try in range(0,recruitment_ids.size()):
		var kind: String=recruitment_ids[(_pref_index+pref_try)%recruitment_ids.size()]
		var definition:=state.registry.unit(kind)
		if definition==null or not state.players[player_id].can_afford(definition.costs):
			continue
		# Find a HQ with space and pick spawn tile preferring low exposure and closer to enemy HQ
		for h in hqs:
			if not h.recruit_available:
				continue
			var candidates: Array[int] = rules.recruit_destinations(player_id, h.id, kind)
			if candidates.is_empty():
				continue
			# Evaluate candidates: exposure then distance to first enemy HQ
			var enemy_hq: Dictionary=_enemy_headquarters(state,observation,player_id)
			# pick best
			var best: int = -1
			var best_score: int = 999999
			for c in candidates:
				var exp: int = exposure(state.grid, enemy_units, c)
				var dist: int = 0
				if not enemy_hq.is_empty():
					dist = grid.distance(c, enemy_hq.cell_id)
				var score: int = exp * 100 + dist
				if score < best_score:
					best_score = score
					best = c
			return {"type":"recruit","hq_id":h.id,"kind":kind,"dest":best}

	# 2) Combat: pick best immediate attack (prefer HQ kill, then kills, then damage)
	var best_attack: Dictionary = {}
	var best_attack_score: int = -999999
	for u in my_units:
		# Skip dead/disabled
		if u.hp <= 0:
			continue
		if u.attacked or state.combat_orders.intents.has(u.id):
			continue
		for tid in rules.attack_targets(player_id, u.id):
			var preview: GameRules.Result = rules.preview_attack(player_id, u.id, tid)
			if _peaceful_village_target(state,player_id,tid) and not _should_raid_village(state,player_id,tid,preview): continue
			var score: int = 0
			if preview.winner_id != 0:
				score = 1000000
			elif preview.killed:
				score = 10000 + preview.damage
			else:
				# useful damage gets base score equal to damage
				score = preview.damage
			# penalize exposing the attacker (simple exposure heuristic)
			var expos: int = exposure(state.grid, enemy_units, u.cell_id)
			score -= expos * 2
			if score > best_attack_score and preview.damage > 0:
				best_attack_score = score
				best_attack = {"type":"attack","attacker":u.id,"target":tid}
	if not best_attack.is_empty():
		return best_attack

	# 3) Consider moves that allow attack
	for u in my_units:
		if u.hp <= 0:
			continue
		if u.moved or u.attacked or state.combat_orders.intents.has(u.id):
			continue
		var reach: Array[int] = rules.reachable(player_id, u.id)
		for dest in reach:
			var dest_pos: int = dest
			# Would moving to dest allow an attack?
			for enemy: Dictionary in enemy_units:
				if grid.distance(dest_pos, enemy.cell_id) <= u.attack_range:
					# pick move that attacks highest priority target
					var path: Array[int] = rules.path_to(player_id, u.id, dest_pos)
					if not path.is_empty():
						return {"type":"move","unit":u.id,"dest":dest_pos}

	# Peaceful discovered villages are useful destinations when no immediate
	# combat or trade action is available.
	var village_move:=_village_approach(state,rules,player_id,my_units)
	if not village_move.is_empty(): return village_move

	# 4) Advance toward enemy HQ if no attacks
	# Find enemy HQ
	var enemy_hq: Dictionary=_enemy_headquarters(state,observation,player_id)
	if not enemy_hq.is_empty():
		# For each unit find a reachable tile that minimizes distance to enemy HQ
		var best_move: Dictionary = {}
		var best_dist: int = 9999
		for u in my_units:
			if u.hp <= 0 or u.moved or state.combat_orders.intents.has(u.id):
				continue
			var reach2: Array[int] = rules.reachable(player_id, u.id)
			for dest2 in reach2:
				var dest_pos2: int = dest2
				var d: int = grid.distance(dest_pos2, enemy_hq.cell_id)
				if d < best_dist:
					best_dist = d
					best_move = {"type":"move","unit":u.id,"dest":dest_pos2}
		if not best_move.is_empty():
			return best_move

	# Explore only from the permitted map observation. Hidden entity changes do
	# not affect this deterministic frontier choice.
	var frontier_move:={}
	var frontier_score:=2147483647
	var frontier_distances:=_unexplored_distances(grid,observation)
	for u: GameState.Unit in my_units:
		if u.hp<=0 or u.moved or state.combat_orders.intents.has(u.id): continue
		var reachable_cells:=rules.reachable(player_id,u.id); reachable_cells.sort()
		for destination: int in reachable_cells:
			var frontier_distance:=int(frontier_distances.get(destination,-1))
			if frontier_distance<0: continue
			var score:=frontier_distance*100000+destination
			if score<frontier_score: frontier_score=score; frontier_move={"type":"move","unit":u.id,"dest":destination}
	if not frontier_move.is_empty(): return frontier_move

	# 5) Nothing useful: end turn
	return {"type":"end"}

func _peaceful_village_target(state: GameState,player_id: int,target_id: int) -> bool:
	var target:=state.combat_target(target_id)
	if target is WorldSiteState:
		var definition:=state.registry.world_site(target.definition_id)
		return definition!=null and definition.category=="village" and state.relationship_for_site(player_id,target)!=RelationshipState.Kind.HOSTILE
	if target is GameState.Unit and target.home_site_id>=0:
		var site: WorldSiteState=state.world_sites.get(target.home_site_id)
		return site!=null and state.relationship_for_site(player_id,site)!=RelationshipState.Kind.HOSTILE
	return false

func _should_raid_village(state: GameState,player_id: int,target_id: int,preview: RuleResult) -> bool:
	if not state.world_sites.has(target_id) or not preview.killed: return false
	var total:=0
	for amount: int in state.players[player_id].resources.values(): total+=amount
	return total<=4

func _village_approach(state: GameState,rules: GameRules,player_id: int,units: Array[GameState.Unit]) -> Dictionary:
	var best:={}; var best_score:=2147483647
	for site: WorldSiteState in rules.interactable_sites(player_id):
		var definition:=state.registry.world_site(site.definition_id)
		if definition==null or definition.category!="village" or site.runtime_state.get("destroyed",false): continue
		if state.relationship_for_site(player_id,site)==RelationshipState.Kind.HOSTILE: continue
		for unit: GameState.Unit in units:
			if unit.moved or unit.attacked: continue
			var current:=state.grid.distance(unit.cell_id,site.cell_id)
			for destination: int in rules.reachable(player_id,unit.id):
				var distance:=state.grid.distance(destination,site.cell_id)
				var score:=distance*100000+destination
				if distance<current and score<best_score: best_score=score; best={"type":"move","unit":unit.id,"dest":destination}
	return best

func _unexplored_distances(grid: PlanetGrid,observation: TeamObservation) -> Dictionary[int,int]:
	var distance: Dictionary[int,int]={}; var queue: Array[int]=[]
	for id in range(grid.get_cell_count()):
		if not observation.is_explored(id): distance[id]=0; queue.append(id)
	var cursor:=0
	while cursor<queue.size():
		var current:=queue[cursor]; cursor+=1
		var neighbors:=grid.get_neighbors(current); neighbors.sort()
		for neighbor: int in neighbors:
			if distance.has(neighbor): continue
			distance[neighbor]=distance[current]+1
			queue.append(neighbor)
	return distance

func _enemy_headquarters(state: GameState,observation: TeamObservation,player_id: int) -> Dictionary:
	var candidates: Array[Dictionary]=[]
	for snapshot: Dictionary in observation.visible_entities.values():
		if not state.relationships.is_hostile(player_id,snapshot.controller_id): continue
		var definition: Resource=state.registry.unit(snapshot.definition_id) if snapshot.kind=="unit" else state.registry.structure(snapshot.definition_id)
		if definition!=null and "headquarters" in definition.tags: candidates.append(snapshot.duplicate(true))
	for contact: Dictionary in observation.known_contacts.values():
		var remembered: Dictionary=contact.observed_snapshot
		if not state.relationships.is_hostile(player_id,int(remembered.get("controller_id",0))): continue
		var definition: Resource=state.registry.unit(contact.observed_definition_id) if contact.entity_kind=="unit" else state.registry.structure(contact.observed_definition_id)
		if definition!=null and "headquarters" in definition.tags:
			candidates.append({"id":contact.contact_id,"cell_id":contact.last_known_cell_id,"historical":true})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.id<b.id)
	return candidates[0] if not candidates.is_empty() else {}

func _living_migration_action(state: GameState,rules: GameRules,player_id: int) -> Dictionary:
	var spiders: Array[GameState.Unit]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id!=player_id: continue
		if unit.spider_state!=null: spiders.append(unit)
	spiders.sort_custom(func(a: GameState.Unit,b: GameState.Unit)->bool: return a.id<b.id)
	for spider: GameState.Unit in spiders:
		for index in range(spider.spider_state.nursery_jobs.size()):
			var job: BiologicalProductionState=spider.spider_state.nursery_jobs[index]
			if not job.held: continue
			for outcome_id: String in job.outcome_unit_ids:
				if not rules.research_rules.is_unit_unlocked(player_id,outcome_id): continue
				var deployed_id:="living_caterpillar" if job.recipe_id=="caterpillar_brood" else outcome_id
				var cells:=rules.living_migration_rules.deployment_cells(player_id,spider.id,deployed_id)
				if not cells.is_empty(): return {"type":"lm_deploy","spider":spider.id,"job":index,"outcome":outcome_id,"dest":cells[0]}
		if spider.spider_state.held_mites>0:
			var mite_cells:=rules.living_migration_rules.deployment_cells(player_id,spider.id,"mite")
			if not mite_cells.is_empty(): return {"type":"lm_mite","spider":spider.id,"dest":mite_cells[0]}
	var player:=state.players[player_id]
	if player.research.current_technology_id.is_empty():
		var technologies:=rules.available_technologies(player_id)
		if not technologies.is_empty(): return {"type":"research","technology":_preferred_technology(state,player_id,technologies)}
	for spider: GameState.Unit in spiders:
		if spider.spider_state.building_count("research_building")==0 and spider.spider_state.construction==null:
			var config:=rules.living_migration_rules.config_for(player_id)
			if player.resource_amount("food")>=config.internal_building_food_cost:
				return {"type":"lm_internal","spider":spider.id,"building":"research_building"}
		if spider.spider_state.nursery_jobs.size()<2:
			for recipe_id: String in ContentRegistry._sorted_keys(state.registry.biological_recipes):
				var recipe:=state.registry.biological_recipe(recipe_id)
				if recipe.branch_id==spider.spider_state.nursery_branch and player.can_afford(recipe.costs):
					var unlocked:=false
					for outcome_id: String in recipe.outcome_unit_ids:
						if rules.research_rules.is_unit_unlocked(player_id,outcome_id): unlocked=true
					if unlocked: return {"type":"lm_queue","spider":spider.id,"recipe":recipe_id}
	return {}

func _baumeister_action(state: GameState,rules: GameRules,player_id: int) -> Dictionary:
	var engineers: Array[GameState.Unit]=[]; var pillars: Array[GameState.Structure]=[]
	var observation:=state.visibility_system.observation_for_controller(player_id)
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==player_id and "engineer" in state.registry.unit(unit.definition_id).tags: engineers.append(unit)
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==player_id and structure.pillar_state!=null: pillars.append(structure)
	engineers.sort_custom(func(a: GameState.Unit,b: GameState.Unit)->bool: return a.id<b.id)
	pillars.sort_custom(func(a: GameState.Structure,b: GameState.Structure)->bool: return a.id<b.id)
	for engineer: GameState.Unit in engineers:
		if engineer.moved or engineer.attacked: continue
		for bridge: BridgeState in rules.baumeister_rules._owned_bridges(player_id):
			if bridge.hp<bridge.max_hp:
				for cell_id: int in bridge.path:
					if state.grid.distance(engineer.cell_id,cell_id)<=1: return {"type":"bm_repair_bridge","engineer":engineer.id,"bridge":bridge.id}
		for pillar: GameState.Structure in pillars:
			if (pillar.hp<pillar.max_hp or pillar.pillar_state.integrity<pillar.pillar_state.max_integrity) and state.grid.distance(engineer.cell_id,pillar.cell_id)<=1:
				return {"type":"bm_repair_pillar","engineer":engineer.id,"pillar":pillar.id}
	var priorities:=PackedStringArray(["power_plant","mine","greenhouse","civic_monument","barracks","workshop","hospital"])
	for district_id: String in priorities:
		var already_owned:=false
		for existing: DistrictState in state.baumeister.districts.values():
			if existing.controller_id==player_id and existing.definition_id==district_id: already_owned=true; break
		if already_owned: continue
		for pillar: GameState.Structure in pillars:
			for slot: Dictionary in rules.baumeister_rules.district_cells(pillar.id):
				if slot.status=="available" and rules.baumeister_rules.district_error(player_id,pillar.id,slot.cell_id,district_id).is_empty():
					return {"type":"bm_district","pillar":pillar.id,"cell":slot.cell_id,"district":district_id}
	var player:=state.players[player_id]
	if player.research.current_technology_id.is_empty():
		var technologies:=rules.available_technologies(player_id)
		if not technologies.is_empty(): return {"type":"research","technology":_preferred_technology(state,player_id,technologies)}
	if state.baumeister.districts.size()>=3:
		for engineer: GameState.Unit in engineers:
			if engineer.moved or engineer.attacked: continue
			for pillar: GameState.Structure in pillars:
				var candidates:=rules.baumeister_rules.candidate_pillar_cells(player_id,engineer.id,pillar.id)
				if not candidates.is_empty(): return {"type":"bm_expand","engineer":engineer.id,"pillar":pillar.id,"cell":candidates[0]}
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==player_id and "deployable_artillery" in state.registry.unit(unit.definition_id).tags and not unit.deployed and not unit.moved:
			for enemy: Dictionary in observation.visible_entities.values():
				if enemy.kind=="unit" and state.relationships.is_hostile(player_id,enemy.controller_id) and state.grid.distance(unit.cell_id,enemy.cell_id)<=state.registry.unit(unit.definition_id).deployed_attack_range:
					return {"type":"bm_deploy","unit":unit.id}
	return {}

func _preferred_technology(state: GameState,player_id: int,available: PackedStringArray) -> String:
	var faction:=state.registry.faction(state.players[player_id].faction_id)
	for technology_id: String in faction.technology_ids:
		if technology_id in available: return technology_id
	return available[0]
