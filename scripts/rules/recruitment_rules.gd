class_name RecruitmentRules
extends RefCounted

var state: GameState
var research: ResearchRules
var capability_rules: BaumeisterRules
func _init(game_state: GameState,research_rules: ResearchRules) -> void:
	state=game_state; research=research_rules

func recruit_error(actor: int,headquarters_id: int,unit_value: String) -> String:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return error
	if not state.structures.has(headquarters_id): return "That headquarters does not exist."
	var headquarters: GameState.Structure=state.structures[headquarters_id]
	var structure_definition:=state.registry.structure(headquarters.definition_id)
	if structure_definition==null or not structure_definition.can_recruit or headquarters.hp<=0: return "Choose a living headquarters."
	if headquarters.controller_id!=actor: return "You do not control that headquarters."
	if not headquarters.recruit_available: return "This headquarters has already recruited this turn."
	var unit_id:=UnitTypes.definition_id(unit_value)
	if unit_id.is_empty() or state.registry.unit(unit_id)==null: return "Unknown unit type."
	if not research.is_unit_unlocked(actor,unit_id): return "Unit is not unlocked."
	if capability_rules!=null:
		var capability_error:=capability_rules.recruitment_error(actor,headquarters_id,unit_id)
		if not capability_error.is_empty(): return capability_error
	if not state.players[actor].can_afford(state.registry.unit(unit_id).costs): return "Insufficient materials."
	return ""

func recruit_destinations(actor: int,headquarters_id: int,unit_value: String) -> Array[int]:
	var result: Array[int]=[]
	if not recruit_error(actor,headquarters_id,unit_value).is_empty(): return result
	for cell_id: int in state.grid.get_neighbors(state.structures[headquarters_id].cell_id):
		if state.grid.contains(cell_id) and not state.is_cell_blocked(cell_id): result.append(cell_id)
	return result

func try_recruit(actor: int,headquarters_id: int,unit_value: String,destination: int) -> RuleResult:
	var error:=recruit_error(actor,headquarters_id,unit_value)
	if not error.is_empty(): return RuleResult.new(false,error)
	var headquarters: GameState.Structure=state.structures[headquarters_id]
	if not state.grid.contains(destination): return RuleResult.new(false,"Choose a tile on the board.")
	if state.grid.distance(headquarters.cell_id,destination)!=1: return RuleResult.new(false,"Destination must be adjacent to the headquarters.")
	if state.is_cell_blocked(destination): return RuleResult.new(false,"Destination is occupied.")
	var unit_id:=UnitTypes.definition_id(unit_value)
	var unit:=GameState.Unit.new(state.allocate_id(),actor,unit_id,destination,-1,state.registry)
	unit.moved=true; unit.attacked=true; unit.ready_next_turn=true
	state.units[unit.id]=unit
	state.players[actor].apply_cost(state.registry.unit(unit_id).costs)
	headquarters.recruit_available=false
	return RuleResult.new(true,"%s recruited. Ready next turn." % state.registry.unit(unit_id).display_name)
