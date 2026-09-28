class_name SimpleAI
extends RefCounted

var _pref_seq: Array[String] = ["Infantry", "Infantry", "Gunner", "Scout"]
var _pref_index: int = 0

func reset() -> void:
	_pref_index = 0

func record_result(action: Dictionary, success: bool) -> void:
	if success and action.get("type") == "recruit":
		_pref_index += 1

# Count enemy units that could attack a given tile (exposure heuristic)
func exposure(grid: PlanetGrid, enemy_units: Array[GameState.Unit], pos: int) -> int:
	var count := 0
	for eu in enemy_units:
		var dist := grid.distance(eu.cell_id, pos)
		if dist <= eu.attack_range:
			count += 1
	return count

# Choose a single action given current state. Returns a Dictionary describing the action.
func choose_action(state: GameState, rules: GameRules, player_id: int) -> Dictionary:
	var grid: PlanetGrid = state.grid
	if state.winner_id != 0 or state.active_player != player_id:
		return {"type": "end"}
	# Gather friendly units and enemy units
	var my_units: Array[GameState.Unit] = []
	var enemy_units: Array[GameState.Unit] = []
	for u in state.units.values():
		if u.owner_id == player_id:
			my_units.append(u)
		else:
			enemy_units.append(u)

	# 1) Recruitment preference: try once per turn by caller; choose preferred affordable unit
	# Caller must ensure HQ recruit availability; here we only choose candidate and placement
	# Find HQs owned by player
	var hqs: Array[GameState.Structure] = []
	for s in state.structures.values():
		if s.owner_id == player_id and s.hp > 0 and s.structure_type == "Headquarters":
			hqs.append(s)

	# Attempt to recruit if any HQ can and we can afford preferred
	for pref_try in range(0, _pref_seq.size()):
		var kind: String = String(_pref_seq[( _pref_index + pref_try) % _pref_seq.size()])
		var cost: int = int(UnitTypes.COSTS.get(kind, 999))
		if state.materials.get(player_id, 0) < cost:
			continue
		# Find a HQ with space and pick spawn tile preferring low exposure and closer to enemy HQ
		for h in hqs:
			if not h.recruit_available:
				continue
			var candidates: Array[int] = rules.recruit_destinations(player_id, h.id, kind)
			if candidates.is_empty():
				continue
			# Evaluate candidates: exposure then distance to first enemy HQ
			var enemy_hq: GameState.Structure = null
			for s2 in state.structures.values():
				if s2.structure_type == "Headquarters" and s2.owner_id != player_id:
					enemy_hq = s2
			# pick best
			var best: int = -1
			var best_score: int = 999999
			for c in candidates:
				var exp: int = exposure(state.grid, enemy_units, c)
				var dist: int = 0
				if enemy_hq != null:
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
		if u.attacked:
			continue
		for tid in rules.attack_targets(player_id, u.id):
			var preview: GameRules.Result = rules.preview_attack(player_id, u.id, tid)
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
		if u.moved or u.attacked:
			continue
		var reach: Array[int] = rules.reachable(player_id, u.id)
		for dest in reach:
			var dest_pos: int = dest
			# Would moving to dest allow an attack?
			for enemy in enemy_units:
				if grid.distance(dest_pos, enemy.cell_id) <= u.attack_range:
					# pick move that attacks highest priority target
					var path: Array[int] = rules.path_to(player_id, u.id, dest_pos)
					if not path.is_empty():
						return {"type":"move","unit":u.id,"dest":dest_pos}

	# 4) Advance toward enemy HQ if no attacks
	# Find enemy HQ
	var enemy_hq: GameState.Structure
	for s in state.structures.values():
		if s.structure_type == "Headquarters" and s.owner_id != player_id:
			enemy_hq = s
	if enemy_hq != null:
		# For each unit find a reachable tile that minimizes distance to enemy HQ
		var best_move: Dictionary = {}
		var best_dist: int = 9999
		for u in my_units:
			if u.hp <= 0 or u.moved:
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

	# 5) Nothing useful: end turn
	return {"type":"end"}
