class_name TurnState
extends RefCounted

const MANAGEMENT:="management"
const COMBAT_PLANNING:="combat_planning"
const NEUTRAL:="neutral"

var order: Array[int]=[1,2]
var index: int=0
var round_number: int=1
var serial: int=0
var neutral_phase_enabled: bool=false
var phase: String=MANAGEMENT
var neutral_phase: bool:
	get: return phase==NEUTRAL
	set(value):
		if value: phase=NEUTRAL
		elif phase==NEUTRAL: phase=MANAGEMENT
var neutral_controller_id: int=50
var eliminated: Dictionary[int,bool]={}
var combat_planning_enabled: bool=true

var active_controller_id: int:
	get: return neutral_controller_id if phase==NEUTRAL else (order[index] if not order.is_empty() else 0)

func reset(sequence: Array[int]) -> void:
	order=sequence.duplicate(); index=0; round_number=1; serial=0; phase=MANAGEMENT; eliminated.clear()
	_skip_eliminated_at_current_index()

func set_eliminated(controller_id: int,value: bool=true) -> void:
	if value: eliminated[controller_id]=true
	else: eliminated.erase(controller_id)

func is_eliminated(controller_id: int) -> bool:
	return bool(eliminated.get(controller_id,false))

func advance() -> int:
	if order.is_empty(): return 0
	if phase==NEUTRAL:
		phase=MANAGEMENT; index=0; round_number+=1; serial+=1
		_skip_eliminated_at_current_index()
		return active_controller_id
	if phase==COMBAT_PLANNING: return active_controller_id
	var scanned:=0
	while scanned<order.size():
		index+=1; scanned+=1
		if index>=order.size(): break
		if not is_eliminated(order[index]):
			serial+=1
			return active_controller_id
	if index>=order.size():
		if combat_planning_enabled: index=maxi(0,order.size()-1); phase=COMBAT_PLANNING
		elif neutral_phase_enabled: index=maxi(0,order.size()-1); phase=NEUTRAL
		else: index=0; round_number+=1; _skip_eliminated_at_current_index()
	serial+=1
	return active_controller_id

func finish_combat() -> void:
	if phase!=COMBAT_PLANNING: return
	serial+=1
	if neutral_phase_enabled: phase=NEUTRAL
	else:
		phase=MANAGEMENT; index=0; round_number+=1; _skip_eliminated_at_current_index()

func _skip_eliminated_at_current_index() -> void:
	if order.is_empty(): return
	var scanned:=0
	while scanned<order.size() and is_eliminated(order[index]):
		index=(index+1)%order.size(); scanned+=1
