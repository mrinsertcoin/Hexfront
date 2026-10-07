class_name CommandDispatcher
extends RefCounted
## Sole gateway from authenticated intentions to authoritative GameRules.

const MOVE:="move"
const ATTACK:="attack"
const END_TURN:="end_turn"
const RECRUIT:="recruit"
const START_RESEARCH:="start_research"
const SITE_INTERACTION:="site_interaction"
const CHOOSE_NURSERY:="choose_nursery"
const START_INTERNAL_CONSTRUCTION:="start_internal_construction"
const QUEUE_BIOLOGICAL_PRODUCTION:="queue_biological_production"
const DEPLOY_BIOLOGICAL:="deploy_biological"
const TRANSFORM_CATERPILLAR:="transform_caterpillar"
const START_SPIDER_CONSTRUCTION:="start_spider_construction"
const DEPLOY_SPIDER:="deploy_spider"
const DEPLOY_MITE:="deploy_mite"
const BUILD_ROAD:="build_road"
const CONSUME_CORPSE:="consume_corpse"
const SELECT_DISEASE:="select_disease"
const BUILD_DISTRICT:="build_district"
const START_BRIDGE_EXTENSION:="start_bridge_extension"
const TOGGLE_DEPLOYMENT:="toggle_deployment"
const HEAL_UNIT:="heal_unit"
const REPAIR_UNIT:="repair_unit"
const REPAIR_STRUCTURE:="repair_structure"
const DAMAGE_BRIDGE:="damage_bridge"
const REPAIR_BRIDGE:="repair_bridge"
const DESIGNATE_TARGET:="designate_target"
const DISTRICT_SUPPORT:="district_support"
const LAY_LARVA:="lay_larva"
const CONSUME:="consume"
const COMBAT_INTENT:="combat_intent"
const LOCK_COMBAT:="lock_combat"

const COMMAND_TYPES:=[MOVE,ATTACK,END_TURN,RECRUIT,START_RESEARCH,SITE_INTERACTION,
	CHOOSE_NURSERY,START_INTERNAL_CONSTRUCTION,QUEUE_BIOLOGICAL_PRODUCTION,DEPLOY_BIOLOGICAL,
	TRANSFORM_CATERPILLAR,START_SPIDER_CONSTRUCTION,DEPLOY_SPIDER,DEPLOY_MITE,BUILD_ROAD,
	CONSUME_CORPSE,SELECT_DISEASE,BUILD_DISTRICT,START_BRIDGE_EXTENSION,TOGGLE_DEPLOYMENT,
	HEAL_UNIT,REPAIR_UNIT,REPAIR_STRUCTURE,DAMAGE_BRIDGE,REPAIR_BRIDGE,DESIGNATE_TARGET,DISTRICT_SUPPORT,
	LAY_LARVA,CONSUME,COMBAT_INTENT,LOCK_COMBAT]

var state: GameState
var rules: GameRules
var peer_to_player: Dictionary[int,int]={}
var last_sequence: Dictionary[int,int]={}
var authoritative_revision: int=0

func _init(game_state: GameState,game_rules: GameRules) -> void:
	state=game_state; rules=game_rules

func register_peer(peer_id: int,player_id: int) -> void:
	peer_to_player[peer_id]=player_id
	if not last_sequence.has(peer_id): last_sequence[peer_id]=0

func unregister_peer(peer_id: int) -> void:
	peer_to_player.erase(peer_id); last_sequence.erase(peer_id)

func dispatch(peer_id: int,raw_command: Variant) -> Dictionary:
	if not peer_to_player.has(peer_id): return _response(0,false,"Player is not registered.")
	var format_error:=GameplayCommand.validation_error(raw_command)
	if not format_error.is_empty(): return _response(_sequence_of(raw_command),false,format_error)
	var command:=raw_command as Dictionary
	var sequence:=int(command.client_sequence)
	var previous: int=int(last_sequence.get(peer_id,0))
	if sequence<=previous: return _response(sequence,false,"Command already processed.",true)
	if sequence!=previous+1: return _response(sequence,false,"Command sequence is out of order.")
	last_sequence[peer_id]=sequence
	var type:=String(command.command_type)
	if type not in COMMAND_TYPES: return _response(sequence,false,"Unsupported command.")
	var actor: int=peer_to_player[peer_id]
	if not state.players.has(actor): return _response(sequence,false,"Player is not active in this match.")
	if state.winner_id!=0: return _response(sequence,false,"The match has ended.")
	var combat_command:=type in [COMBAT_INTENT,LOCK_COMBAT]
	if state.turn_state.phase==TurnState.COMBAT_PLANNING:
		if not combat_command: return _response(sequence,false,"Combat planning is in progress.")
	elif state.turn_state.neutral_phase or actor!=state.active_player or combat_command:
		return _response(sequence,false,"It is not your turn.")
	if _is_defeated(actor): return _response(sequence,false,"Defeated players cannot issue commands.")
	var params:=command.parameters as Dictionary
	var result:=_execute(actor,type,params)
	if result==null: return _response(sequence,false,"Invalid command parameters.")
	if not result.success: return _response(sequence,false,_public_failure(result.reason))
	authoritative_revision+=1
	var response:=_response(sequence,true,result.reason)
	response.authoritative_revision=authoritative_revision
	response.path=Array(result.path)
	response.outcome={"damage":result.damage,"target_hp":result.target_hp,"killed":result.killed,"winner_id":result.winner_id}
	return response

func dispatch_internal(player_id: int,sequence: int,type: String,parameters: Dictionary={}) -> Dictionary:
	var peer_id:=-100000-player_id
	if not peer_to_player.has(peer_id): register_peer(peer_id,player_id)
	return dispatch(peer_id,GameplayCommand.create(sequence,type,parameters))

func dispatch_authoritative_controller(controller_id: int,type: String,parameters: Dictionary={}) -> Dictionary:
	if not state.controllers.has(controller_id) or type not in COMMAND_TYPES:
		return _response(0,false,"Invalid authoritative command.")
	var result:=_execute(controller_id,type,parameters)
	if result==null: return _response(0,false,"Invalid command parameters.")
	if not result.success: return _response(0,false,_public_failure(result.reason))
	authoritative_revision+=1
	var response:=_response(0,true,result.reason)
	response.authoritative_revision=authoritative_revision; response.path=Array(result.path)
	response.outcome={"damage":result.damage,"target_hp":result.target_hp,"killed":result.killed,"winner_id":result.winner_id}
	return response

func _execute(actor: int,type: String,p: Dictionary) -> RuleResult:
	match type:
		MOVE: return rules.try_move(actor,_int(p,"unit_id"),_int(p,"destination")) if _has(p,["unit_id","destination"]) else null
		ATTACK: return rules.try_attack(actor,_int(p,"attacker_id"),_int(p,"target_id")) if _has(p,["attacker_id","target_id"]) else null
		END_TURN: return rules.try_end_turn(actor) if p.is_empty() else null
		RECRUIT: return rules.try_recruit(actor,_int(p,"headquarters_id"),String(p.get("unit_id","")),_int(p,"destination")) if _has(p,["headquarters_id","unit_id","destination"]) else null
		START_RESEARCH: return rules.start_research(actor,String(p.get("technology_id",""))) if _has(p,["technology_id"]) else null
		SITE_INTERACTION: return rules.try_site_interaction(actor,_int(p,"site_id"),String(p.get("interaction_id","")),_int(p,"unit_id",-1)) if _has(p,["site_id","interaction_id"]) else null
		CHOOSE_NURSERY: return rules.choose_nursery(actor,_int(p,"spider_id"),String(p.get("branch_id",""))) if _has(p,["spider_id","branch_id"]) else null
		START_INTERNAL_CONSTRUCTION: return rules.start_internal_construction(actor,_int(p,"spider_id"),String(p.get("building_id",""))) if _has(p,["spider_id","building_id"]) else null
		QUEUE_BIOLOGICAL_PRODUCTION: return rules.queue_biological_production(actor,_int(p,"spider_id"),String(p.get("recipe_id",""))) if _has(p,["spider_id","recipe_id"]) else null
		DEPLOY_BIOLOGICAL: return rules.deploy_biological(actor,_int(p,"spider_id"),_int(p,"job_index"),String(p.get("outcome_id","")),_int(p,"cell_id")) if _has(p,["spider_id","job_index","outcome_id","cell_id"]) else null
		TRANSFORM_CATERPILLAR: return rules.transform_caterpillar(actor,_int(p,"unit_id"),String(p.get("outcome_id",""))) if _has(p,["unit_id","outcome_id"]) else null
		START_SPIDER_CONSTRUCTION: return rules.start_spider_construction(actor,_int(p,"spider_id")) if _has(p,["spider_id"]) else null
		DEPLOY_SPIDER: return rules.deploy_spider(actor,_int(p,"spider_id"),_int(p,"cell_id")) if _has(p,["spider_id","cell_id"]) else null
		DEPLOY_MITE: return rules.deploy_mite(actor,_int(p,"spider_id"),_int(p,"cell_id")) if _has(p,["spider_id","cell_id"]) else null
		BUILD_ROAD: return rules.try_build_road(actor,_int(p,"worker_id"),p.get("path",[])) if _has(p,["worker_id","path"]) and p.path is Array else null
		CONSUME_CORPSE: return rules.try_consume_corpse(actor,_int(p,"ant_id"),_int(p,"corpse_id")) if _has(p,["ant_id","corpse_id"]) else null
		SELECT_DISEASE: return rules.select_disease(actor,_int(p,"mite_id"),String(p.get("disease_id",""))) if _has(p,["mite_id","disease_id"]) else null
		BUILD_DISTRICT: return rules.build_district(actor,_int(p,"pillar_id"),_int(p,"cell_id"),String(p.get("district_id",""))) if _has(p,["pillar_id","cell_id","district_id"]) else null
		START_BRIDGE_EXTENSION: return rules.start_bridge_extension(actor,_int(p,"engineer_id"),_int(p,"pillar_id"),_int(p,"cell_id")) if _has(p,["engineer_id","pillar_id","cell_id"]) else null
		TOGGLE_DEPLOYMENT: return rules.toggle_deployment(actor,_int(p,"unit_id")) if _has(p,["unit_id"]) else null
		HEAL_UNIT: return rules.heal_unit(actor,_int(p,"healer_id"),_int(p,"target_id")) if _has(p,["healer_id","target_id"]) else null
		REPAIR_UNIT: return rules.repair_unit(actor,_int(p,"engineer_id"),_int(p,"target_id")) if _has(p,["engineer_id","target_id"]) else null
		REPAIR_STRUCTURE: return rules.repair_structure(actor,_int(p,"engineer_id"),_int(p,"structure_id")) if _has(p,["engineer_id","structure_id"]) else null
		DAMAGE_BRIDGE: return rules.damage_bridge(actor,_int(p,"attacker_id"),_int(p,"bridge_id")) if _has(p,["attacker_id","bridge_id"]) else null
		REPAIR_BRIDGE: return rules.repair_bridge(actor,_int(p,"engineer_id"),_int(p,"bridge_id")) if _has(p,["engineer_id","bridge_id"]) else null
		DESIGNATE_TARGET: return rules.designate_target(actor,_int(p,"commander_id"),_int(p,"target_id")) if _has(p,["commander_id","target_id"]) else null
		DISTRICT_SUPPORT: return rules.district_support(actor,_int(p,"district_id"),_int(p,"target_id")) if _has(p,["district_id","target_id"]) else null
		LAY_LARVA: return rules.lay_larva(actor,_int(p,"unit_id"),_int(p,"cell_id")) if _has(p,["unit_id","cell_id"]) else null
		CONSUME: return rules.consume(actor,_int(p,"unit_id"),String(p.get("source_kind","")),_int(p,"source_id")) if _has(p,["unit_id","source_kind","source_id"]) else null
		COMBAT_INTENT: return rules.submit_combat_intent(actor,_int(p,"unit_id"),String(p.get("option_id","")),_int(p,"target_id",-1)) if _has(p,["unit_id","option_id"]) else null
		LOCK_COMBAT: return rules.lock_combat(actor) if p.is_empty() else null
	return null

func _response(sequence: int,accepted: bool,reason: String,duplicate: bool=false) -> Dictionary:
	return {"protocol_version":NetworkProtocol.NETWORK_PROTOCOL_VERSION,"client_sequence":sequence,"accepted":accepted,"public_reason":reason,"duplicate":duplicate,
		"authoritative_revision":authoritative_revision}

func _public_failure(_reason: String) -> String:
	# Rule diagnostics may depend on hidden authoritative state. Keep rejection
	# messages deliberately generic at the network boundary.
	return "Action could not be completed."

func _sequence_of(value: Variant) -> int:
	return int(value.get("client_sequence",0)) if value is Dictionary else 0

func _has(values: Dictionary,keys: Array[String]) -> bool:
	for key: String in keys:
		if not values.has(key): return false
	return true

func _int(values: Dictionary,key: String,fallback: int=-1) -> int: return int(values.get(key,fallback))

func _is_defeated(controller_id: int) -> bool:
	if state.players.has(controller_id): return state.players[controller_id].eliminated
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==controller_id and "headquarters" in state.registry.unit(unit.definition_id).tags: return false
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==controller_id and "headquarters" in state.registry.structure(structure.definition_id).tags: return false
	return true
