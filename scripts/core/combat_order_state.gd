class_name CombatOrderState
extends RefCounted

var intents: Dictionary[int,CombatIntent]={}
var resolution_serial: int=0
var last_outcomes: Array[Dictionary]=[]

func reset() -> void:
	intents.clear(); last_outcomes.clear()

func snapshot_for(controller_id: int) -> Dictionary:
	var own: Array[Dictionary]=[]
	for unit_id: int in intents:
		if intents[unit_id].controller_id==controller_id: own.append(intents[unit_id].snapshot())
	return {"own_intents":own,"resolution_serial":resolution_serial,"last_outcomes":last_outcomes.duplicate(true)}
