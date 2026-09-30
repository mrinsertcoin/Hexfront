class_name PillarState
extends RefCounted

var integrity: int
var max_integrity: int
var maintenance_paid: bool=true
var supplied: bool=false
var origin: bool=false

func _init(maximum: int=1,is_origin: bool=false) -> void:
	max_integrity=maximum; integrity=maximum; origin=is_origin; supplied=is_origin

func snapshot() -> Dictionary:
	return {"integrity":integrity,"max_integrity":max_integrity,"maintenance_paid":maintenance_paid,
		"supplied":supplied,"origin":origin}
