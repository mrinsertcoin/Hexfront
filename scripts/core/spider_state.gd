class_name SpiderState
extends RefCounted

var slot_limit: int=9
var slots: PackedStringArray=[]
var nursery_branch: String=""
var nursery_jobs: Array[BiologicalProductionState]=[]
var construction: BiologicalProductionState
var mite_progress: int=0
var held_mites: int=0

func _init(limit: int=9) -> void: slot_limit=limit

func has_slot() -> bool: return slots.size()<slot_limit
func building_count(id: String) -> int: return slots.count(id)

func snapshot() -> Dictionary:
	var jobs: Array[Dictionary]=[]
	for job: BiologicalProductionState in nursery_jobs: jobs.append(job.snapshot())
	return {"slot_limit":slot_limit,"slots":Array(slots),"nursery_branch":nursery_branch,
		"nursery_jobs":jobs,"construction":construction.snapshot() if construction!=null else {},
		"mite_progress":mite_progress,"held_mites":held_mites}
