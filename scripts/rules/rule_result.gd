class_name RuleResult
extends RefCounted

var success: bool
var reason: String
var path: Array[int]=[]
var damage: int=0
var target_hp: int=0
var killed: bool=false
var winner_id: int=0

func _init(accepted: bool,message: String,route: Array[int]=[]) -> void:
	success=accepted; reason=message; path=route
