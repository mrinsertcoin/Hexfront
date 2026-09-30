class_name ControllerState
extends RefCounted

const HUMAN:="human"
const PLAYER_AI:="player_ai"
const NEUTRAL_AI:="neutral_ai"
const WORLD:="world"
const KINDS: Array[String]=[HUMAN,PLAYER_AI,NEUTRAL_AI,WORLD]

var id: int
var kind: String
var faction_id: String
var team_id: int

func _init(controller_id: int=0,controller_kind: String=WORLD,faction: String="",team: int=-1) -> void:
	id=controller_id; kind=controller_kind; faction_id=faction; team_id=controller_id if team<0 else team

func validate() -> String:
	if id<0 or kind not in KINDS: return "Invalid controller %d" % id
	return ""
