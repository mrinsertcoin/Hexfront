class_name ResearchRules
extends RefCounted

var state: GameState
func _init(game_state: GameState) -> void: state=game_state

func available_technologies(player_id: int) -> PackedStringArray:
	var player:=state.player_for_controller(player_id)
	if player==null: return PackedStringArray()
	var faction:=state.registry.faction(player.faction_id)
	return player.research.available_technologies(state.registry,faction.technology_ids)

func can_start_research(player_id: int,technology_id: String) -> String:
	var player:=state.player_for_controller(player_id)
	if player==null: return "Unknown player."
	var authority_error:=RuleAuthority.actor_error(state,player_id)
	if not authority_error.is_empty(): return authority_error
	if not player.research.current_technology_id.is_empty(): return "Research is already in progress."
	var faction:=state.registry.faction(player.faction_id)
	if technology_id not in faction.technology_ids: return "Technology does not belong to this faction."
	var definition:=state.registry.technology(technology_id)
	if definition==null: return "Unknown technology."
	if player.research.is_completed(technology_id): return "Research already completed."
	var missing:=PackedStringArray()
	for prerequisite: String in definition.prerequisite_ids:
		if not player.research.is_completed(prerequisite): missing.append(state.registry.technology(prerequisite).display_name)
	if not missing.is_empty(): return "Requires: "+", ".join(missing)
	return ""

func start_research(player_id: int,technology_id: String) -> RuleResult:
	var error:=can_start_research(player_id,technology_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var research:=state.players[player_id].research
	research.current_technology_id=technology_id; research.accumulated_progress=0
	return RuleResult.new(true,"Research started.")

func add_research_progress(player_id: int,amount: int) -> RuleResult:
	var player:=state.player_for_controller(player_id)
	if player==null or player.research.current_technology_id.is_empty(): return RuleResult.new(false,"No research is active.")
	if amount<0: return RuleResult.new(false,"Research progress cannot be negative.")
	player.research.accumulated_progress+=amount
	var definition:=state.registry.technology(player.research.current_technology_id)
	if player.research.accumulated_progress>=definition.research_cost: return complete_research(player_id)
	return RuleResult.new(true,"Research progress added.")

func complete_research(player_id: int) -> RuleResult:
	var player:=state.player_for_controller(player_id)
	if player==null or player.research.current_technology_id.is_empty(): return RuleResult.new(false,"No research is active.")
	var id:=player.research.current_technology_id
	if id not in player.research.completed_ids: player.research.completed_ids.append(id); player.research.completed_ids.sort()
	player.research.current_technology_id=""; player.research.accumulated_progress=0
	return RuleResult.new(true,"Research completed: "+id)

func is_unit_unlocked(player_id: int,unit_id: String) -> bool:
	var player:=state.player_for_controller(player_id)
	if player==null: return false
	var faction:=state.registry.faction(player.faction_id)
	if unit_id not in faction.unit_roster_ids: return false
	for technology_id: String in faction.technology_ids:
		var technology:=state.registry.technology(technology_id)
		if technology!=null and unit_id in technology.unlock_unit_ids:
			return player.research.is_completed(technology_id)
	return true

func is_structure_unlocked(player_id: int,structure_id: String) -> bool:
	var player:=state.player_for_controller(player_id)
	if player==null: return false
	var faction:=state.registry.faction(player.faction_id)
	if structure_id not in faction.structure_roster_ids: return false
	for technology_id: String in faction.technology_ids:
		var technology:=state.registry.technology(technology_id)
		if technology!=null and structure_id in technology.unlock_structure_ids:
			return player.research.is_completed(technology_id)
	return true

func has_unlock_tag(player_id: int,tag: String) -> bool:
	var player:=state.player_for_controller(player_id)
	if player==null: return false
	for technology_id: String in player.research.completed_ids:
		var technology:=state.registry.technology(technology_id)
		if technology!=null and tag in technology.unlock_tags: return true
	return false
