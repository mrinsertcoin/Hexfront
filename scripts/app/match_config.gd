class_name MatchConfig
extends Resource
## Immutable-in-practice setup. Factions are stable content IDs.

enum PlanetSize { DEV_TINY, SMALL, MEDIUM }
const SIZE_DEFINITIONS := {
	PlanetSize.DEV_TINY: {"name":"Dev / Tiny","subdivision":3,"radius":12.0,"cells":642},
	PlanetSize.SMALL: {"name":"Small","subdivision":4,"radius":24.0,"cells":2562},
	PlanetSize.MEDIUM: {"name":"Medium","subdivision":5,"radius":48.0,"cells":10242},
}

@export var world_seed: int=48293617
@export var planet_size: PlanetSize=PlanetSize.SMALL
@export var player_faction_id: String="blue"
@export var opponent_faction_id: String="red"
@export_enum("Human","AI") var opponent_controller: String="AI"
@export var ai_difficulty: String="Standard"
@export_enum("Off","Sparse","Standard","Dense") var world_population_preset: String=WorldPopulationConfig.STANDARD
@export var player_team_id: int=1
@export var opponent_team_id: int=2
## Multiplayer assignments are primitive records and may grow to four players.
## Empty preserves the existing two-player setup fields.
var player_assignments: Array[Dictionary]=[]
var network_match: bool=false
var private_population_seed: int=0

# Temporary source compatibility while callers migrate to explicit ID names.
var player_faction: String:
	get: return player_faction_id
	set(value): player_faction_id=_normalize_faction(value)
var opponent_faction: String:
	get: return opponent_faction_id
	set(value): opponent_faction_id=_normalize_faction(value)

static func normal_planet_sizes() -> Array[PlanetSize]:
	return [PlanetSize.SMALL,PlanetSize.MEDIUM]

func size_definition() -> Dictionary:
	return SIZE_DEFINITIONS.get(planet_size,SIZE_DEFINITIONS[PlanetSize.SMALL])

func validate(registry: ContentRegistry=ContentRegistry.default()) -> PackedStringArray:
	var errors:=PackedStringArray()
	if not SIZE_DEFINITIONS.has(planet_size): errors.append("Choose a valid planet size.")
	var player:=registry.faction(player_faction_id)
	var opponent:=registry.faction(opponent_faction_id)
	if player==null or not player.playable: errors.append("Choose a valid player faction.")
	if opponent==null or not opponent.playable: errors.append("Choose a valid opponent faction.")
	if player_faction_id==opponent_faction_id and player_assignments.is_empty(): errors.append("Player and opponent must use different factions.")
	if opponent_controller not in ["Human","AI"]: errors.append("Choose a valid opponent controller.")
	if ai_difficulty!="Standard": errors.append("Choose a supported AI difficulty.")
	if world_population_preset not in WorldPopulationConfig.PRESETS: errors.append("Choose a valid world population density.")
	if player_team_id<=0 or opponent_team_id<=0: errors.append("Team IDs must be positive.")
	if not player_assignments.is_empty():
		if player_assignments.size()<2 or player_assignments.size()>NetworkProtocol.MAX_PLAYERS: errors.append("Multiplayer requires two to four players.")
		var player_ids:={}
		for assignment: Dictionary in player_assignments:
			var id:=int(assignment.get("player_id",0)); var faction_id:=String(assignment.get("faction_id",""))
			var faction:=registry.faction(faction_id)
			if id<=0 or player_ids.has(id): errors.append("Multiplayer player IDs must be unique and positive.")
			player_ids[id]=true
			if faction==null or not faction.playable: errors.append("Multiplayer assignment has an invalid faction.")
	return errors

func copy() -> MatchConfig:
	var result:=MatchConfig.new()
	result.world_seed=world_seed; result.planet_size=planet_size
	result.player_faction_id=player_faction_id; result.opponent_faction_id=opponent_faction_id
	result.opponent_controller=opponent_controller; result.ai_difficulty=ai_difficulty
	result.world_population_preset=world_population_preset
	result.player_team_id=player_team_id; result.opponent_team_id=opponent_team_id
	result.player_assignments=player_assignments.duplicate(true); result.network_match=network_match
	result.private_population_seed=private_population_seed
	return result

func faction_ids() -> Array[String]:
	if player_assignments.is_empty(): return [player_faction_id,opponent_faction_id]
	var result: Array[String]=[]
	for assignment: Dictionary in _sorted_assignments(): result.append(String(assignment.faction_id))
	return result

func team_ids() -> Array[int]:
	if player_assignments.is_empty(): return [player_team_id,opponent_team_id]
	var result: Array[int]=[]
	for assignment: Dictionary in _sorted_assignments(): result.append(int(assignment.get("team_id",assignment.player_id)))
	return result

func controller_kinds() -> Array[String]:
	if player_assignments.is_empty(): return [ControllerState.HUMAN,ControllerState.HUMAN if opponent_controller=="Human" else ControllerState.PLAYER_AI]
	var result: Array[String]=[]
	for assignment: Dictionary in _sorted_assignments(): result.append(String(assignment.get("controller_kind",ControllerState.HUMAN)))
	return result

func public_network_dictionary() -> Dictionary:
	return {"world_seed":world_seed,"planet_size":planet_size,"world_population_preset":world_population_preset,
		"player_assignments":player_assignments.duplicate(true)}

static func from_network_dictionary(data: Dictionary) -> MatchConfig:
	var result:=MatchConfig.new(); result.network_match=true
	result.world_seed=int(data.get("world_seed",result.world_seed)); result.planet_size=int(data.get("planet_size",PlanetSize.SMALL))
	result.world_population_preset=String(data.get("world_population_preset",WorldPopulationConfig.STANDARD))
	for value: Variant in data.get("player_assignments",[]):
		if value is Dictionary: result.player_assignments.append((value as Dictionary).duplicate(true))
	if not result.player_assignments.is_empty():
		result.player_faction_id=String(result.player_assignments[0].get("faction_id",result.player_faction_id))
		if result.player_assignments.size()>1: result.opponent_faction_id=String(result.player_assignments[1].get("faction_id",result.opponent_faction_id))
	return result

func _sorted_assignments() -> Array[Dictionary]:
	var result:=player_assignments.duplicate(true)
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return int(a.player_id)<int(b.player_id))
	return result

static func _normalize_faction(value: String) -> String:
	var normalized:=value.to_lower()
	return normalized if ContentRegistry.default().factions.has(normalized) else value
