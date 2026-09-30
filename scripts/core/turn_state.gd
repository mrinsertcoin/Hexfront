class_name TurnState
extends RefCounted

var order: Array[int]=[1,2]
var index: int=0
var round_number: int=1
var serial: int=0
var neutral_phase_enabled: bool=false
var neutral_phase: bool=false
var neutral_controller_id: int=50

var active_controller_id: int:
	get: return neutral_controller_id if neutral_phase else (order[index] if not order.is_empty() else 0)

func reset(sequence: Array[int]) -> void:
	order=sequence.duplicate(); index=0; round_number=1; serial=0; neutral_phase=false

func advance() -> int:
	if order.is_empty(): return 0
	if neutral_phase:
		neutral_phase=false; index=0; round_number+=1; serial+=1
		return active_controller_id
	index+=1
	if index>=order.size():
		if neutral_phase_enabled:
			index=order.size()-1; neutral_phase=true
		else:
			index=0; round_number+=1
	serial+=1
	return active_controller_id
