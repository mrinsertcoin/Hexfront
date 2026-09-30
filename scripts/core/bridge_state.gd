class_name BridgeState
extends RefCounted

var id: int
var controller_id: int
var endpoint_a: int
var endpoint_b: int
var path: Array[int]=[]
var construction_progress: int=0
var required_turns: int=1
var hp: int=1
var max_hp: int=1
var maintenance_paid: bool=true

var completed: bool:
	get: return construction_progress>=required_turns
var operational: bool:
	get: return completed and hp>0

func _init(bridge_id: int=0,controller: int=0,a: int=0,b: int=0,cells: Array[int]=[],turns: int=1,maximum_hp: int=1) -> void:
	id=bridge_id; controller_id=controller; endpoint_a=a; endpoint_b=b; path=cells.duplicate()
	required_turns=turns; max_hp=maximum_hp; hp=maximum_hp

func snapshot() -> Dictionary:
	return {"id":id,"controller_id":controller_id,"endpoint_a":endpoint_a,"endpoint_b":endpoint_b,
		"path":path.duplicate(),"construction_progress":construction_progress,"required_turns":required_turns,
		"hp":hp,"max_hp":max_hp,"maintenance_paid":maintenance_paid}
