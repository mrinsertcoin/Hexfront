class_name TurnState
extends RefCounted

const MANAGEMENT:="management"
const COMBAT_RESOLUTION:="combat_resolution"
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
var simultaneous_combat_enabled: bool=true
var simultaneous_player_turns_enabled: bool=false
var simultaneous_controllers: Dictionary[int,bool]={}
var completed_controllers: Dictionary[int,bool]={}
var simultaneous_stage_started: bool=false

var active_controller_id: int:
	get: return neutral_controller_id if phase==NEUTRAL else (order[index] if not order.is_empty() else 0)

func reset(sequence: Array[int],simultaneous_ids: Array[int]=[]) -> void:
	order=sequence.duplicate(); index=0; round_number=1; serial=0; phase=MANAGEMENT; eliminated.clear()
	simultaneous_controllers.clear(); completed_controllers.clear()
	for controller_id: int in simultaneous_ids: simultaneous_controllers[controller_id]=true
	simultaneous_player_turns_enabled=not simultaneous_controllers.is_empty()
	_skip_eliminated_at_current_index()
	simultaneous_stage_started=simultaneous_player_turns_enabled and not order.is_empty() and simultaneous_controllers.has(active_controller_id)

func set_eliminated(controller_id: int,value: bool=true) -> void:
	if value: eliminated[controller_id]=true
	else: eliminated.erase(controller_id)
	if simultaneous_player_turns_enabled and phase==MANAGEMENT and simultaneous_stage_started:
		if _all_simultaneous_complete(): phase=COMBAT_RESOLUTION
		elif not order.is_empty() and is_eliminated(active_controller_id): _select_next_simultaneous()

func is_eliminated(controller_id: int) -> bool:
	return bool(eliminated.get(controller_id,false))

func can_act(controller_id: int) -> bool:
	if phase!=MANAGEMENT or is_eliminated(controller_id): return false
	if not simultaneous_player_turns_enabled: return controller_id==active_controller_id
	if simultaneous_stage_started:
		return simultaneous_controllers.has(controller_id) and not completed_controllers.has(controller_id)
	return controller_id==active_controller_id and not simultaneous_controllers.has(controller_id)

func simultaneous_player_ids() -> Array[int]:
	var result: Array[int]=[]
	for controller_id: int in order:
		if simultaneous_controllers.has(controller_id) and not is_eliminated(controller_id): result.append(controller_id)
	return result

func advance() -> int:
	return advance_controller(active_controller_id)

func advance_controller(controller_id: int) -> int:
	if not simultaneous_player_turns_enabled: return _advance_legacy()
	if order.is_empty(): return 0
	if phase==NEUTRAL:
		phase=MANAGEMENT; index=0; serial+=1; completed_controllers.clear()
		_skip_eliminated_at_current_index()
		simultaneous_stage_started=not order.is_empty() and simultaneous_controllers.has(active_controller_id)
		return active_controller_id
	if phase==COMBAT_RESOLUTION: return active_controller_id
	if simultaneous_stage_started:
		if not can_act(controller_id): return active_controller_id
		completed_controllers[controller_id]=true; serial+=1
		if _all_simultaneous_complete():
			index=maxi(0,order.size()-1); phase=COMBAT_RESOLUTION
		else: _select_next_simultaneous()
		return active_controller_id
	# Ordered AI controllers form the first half of the enemy stage.
	var scanned:=0
	while scanned<order.size():
		index+=1; scanned+=1
		if index>=order.size(): break
		if is_eliminated(order[index]): continue
		serial+=1
		if simultaneous_controllers.has(order[index]): simultaneous_stage_started=true
		return active_controller_id
	if index>=order.size():
		index=maxi(0,order.size()-1); phase=COMBAT_RESOLUTION
	serial+=1
	return active_controller_id

func _advance_legacy() -> int:
	if order.is_empty(): return 0
	if phase==NEUTRAL:
		phase=MANAGEMENT; index=0; round_number+=1; serial+=1
		_skip_eliminated_at_current_index()
		return active_controller_id
	if phase==COMBAT_RESOLUTION: return active_controller_id
	var scanned:=0
	while scanned<order.size():
		index+=1; scanned+=1
		if index>=order.size(): break
		if not is_eliminated(order[index]):
			serial+=1
			return active_controller_id
	if index>=order.size():
		if simultaneous_combat_enabled: index=maxi(0,order.size()-1); phase=COMBAT_RESOLUTION
		elif neutral_phase_enabled: index=maxi(0,order.size()-1); phase=NEUTRAL
		else: index=0; round_number+=1; _skip_eliminated_at_current_index()
	serial+=1
	return active_controller_id

func finish_combat() -> void:
	if phase!=COMBAT_RESOLUTION: return
	serial+=1
	if neutral_phase_enabled:
		if simultaneous_player_turns_enabled: round_number+=1; completed_controllers.clear()
		phase=NEUTRAL
	else:
		phase=MANAGEMENT; index=0; round_number+=1; completed_controllers.clear(); _skip_eliminated_at_current_index()
		simultaneous_stage_started=simultaneous_player_turns_enabled and not order.is_empty() and simultaneous_controllers.has(active_controller_id)

func begin_initial_enemy_phase() -> void:
	if simultaneous_player_turns_enabled and neutral_phase_enabled and round_number==1 and serial==0: phase=NEUTRAL

func _skip_eliminated_at_current_index() -> void:
	if order.is_empty(): return
	var scanned:=0
	while scanned<order.size() and is_eliminated(order[index]):
		index=(index+1)%order.size(); scanned+=1

func _all_simultaneous_complete() -> bool:
	for controller_id: int in simultaneous_controllers:
		if not is_eliminated(controller_id) and not completed_controllers.has(controller_id): return false
	return true

func _select_next_simultaneous() -> void:
	for controller_id: int in order:
		if simultaneous_controllers.has(controller_id) and not is_eliminated(controller_id) and not completed_controllers.has(controller_id):
			index=order.find(controller_id); return
