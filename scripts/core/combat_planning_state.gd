class_name CombatPlanningState
extends RefCounted

var intents: Dictionary[int,CombatIntent]={}
var locked_players: Dictionary[int,bool]={}
var resolution_serial: int=0
var last_outcomes: Array[Dictionary]=[]

func reset() -> void:
	intents.clear(); locked_players.clear(); last_outcomes.clear()

func is_locked(controller_id: int) -> bool: return bool(locked_players.get(controller_id,false))

func snapshot_for(controller_id: int) -> Dictionary:
	var own: Array[Dictionary]=[]
	for unit_id: int in intents:
		if intents[unit_id].controller_id==controller_id: own.append(intents[unit_id].snapshot())
	return {"own_intents":own,"locked_players":locked_players.duplicate(true),
		"resolution_serial":resolution_serial,"last_outcomes":last_outcomes.duplicate(true)}
