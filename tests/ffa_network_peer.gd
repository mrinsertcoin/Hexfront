extends SceneTree

var session: NetworkSession
var role: String=""
var result_path: String=""
var port:=24567
var deadline:=0
var state: GameState
var ready_sent:=false
var movement_submitted:=false
var movement_accepted:=false
var order_submitted:=false
var order_accepted:=false
var host_started:=false
var finishing:=false
var observed_turns: Array[int]=[]
var saw_simultaneous_stage:=false

class SlowLoadingSession extends NetworkSession:
	var delayed_first_snapshot: bool=false
	func _receive_observation(snapshot: Dictionary) -> void:
		if not delayed_first_snapshot:
			delayed_first_snapshot=true
			await get_tree().create_timer(0.25).timeout
		super._receive_observation(snapshot)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role=arg.trim_prefix("--role=")
		elif arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		elif arg.begins_with("--result="): result_path=arg.trim_prefix("--result=")
	deadline=Time.get_ticks_msec()+40000
	# A deliberately slower fourth client guards the loading barrier: fast
	# clients must not submit their first command while the host is LOADING.
	session=SlowLoadingSession.new() if role=="client4" else NetworkSession.new()
	session.name="NetworkSession"; root.add_child(session); await process_frame
	session.lobby_changed.connect(_lobby_changed)
	session.observation_received.connect(_observation)
	session.command_completed.connect(_command_result)
	session.status_changed.connect(_status_changed)
	session.session_ended.connect(_session_ended)
	var index:=_role_index(); var faction:="living_migration" if index in [1,2] else "baumeister"
	if role=="host":
		var configuration:={"planet_size":MatchConfig.PlanetSize.SMALL,"world_seed":191919,"world_population_preset":WorldPopulationConfig.OFF}
		if session.host_game(port,"FFA Host",faction,4,configuration)!=OK: return _finish(false,session.status_message)
		session.set_local_lobby_choice(faction,true); ready_sent=true
	else:
		if session.join_game("127.0.0.1",port,"FFA Client %d" % index,faction)!=OK: return _finish(false,session.status_message)
	while Time.get_ticks_msec()<deadline: await process_frame
	_finish(false,"Timed out; observed=%s status=%d round=%d active=%d" % [observed_turns,session.status,
		state.round_number if state!=null else -1,state.active_player if state!=null else -1])

func _role_index() -> int:
	if role=="host": return 1
	return int(role.trim_prefix("client"))

func _lobby_changed(records: Array) -> void:
	if role!="host" and session.local_player_id>0 and session.status==NetworkSession.Status.LOBBY and not ready_sent:
		ready_sent=true; session.set_local_lobby_choice(session.local_faction_id,true)
	if role!="host" or host_started or records.size()!=4 or not session.can_host_start(): return
	host_started=true
	var config:=MatchConfig.new(); config.network_match=true; config.planet_size=MatchConfig.PlanetSize.DEV_TINY
	config.world_population_preset=WorldPopulationConfig.OFF; config.world_seed=191919; config.private_population_seed=292929
	for record: Dictionary in records:
		config.player_assignments.append({"player_id":record.player_id,"player_name":record.player_name,
			"faction_id":record.faction_id,"team_id":record.player_id,"controller_kind":ControllerState.HUMAN,
			"player_color":record.player_color})
	var error:=session.announce_match(config.public_network_dictionary())
	if not error.is_empty(): return _finish(false,error)
	state=GameState.new(PlanetGrid.new(2,12.0),{"player_ids":config.player_ids(),"player_names":config.player_names(),
		"player_colors":config.player_colors(),"faction_ids":config.faction_ids(),"controller_kinds":config.controller_kinds(),"team_ids":config.team_ids(),
		"simultaneous_combat":true,"simultaneous_player_turns":true})
	var p1: GameState.Unit; var p2: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.attack_damage<=0: continue
		if unit.controller_id==1 and p1==null: p1=unit
		elif unit.controller_id==2 and p2==null: p2=unit
	if p1!=null and p2!=null: p2.cell_id=state.grid.get_neighbors(p1.cell_id)[0]
	state.refresh_visibility()
	session.attach_authority(state,GameRules.new(state))

func _status_changed(value: int,_message: String) -> void:
	if role=="host" and value==NetworkSession.Status.ACTIVE and not session.latest_observation.is_empty():
		_observation(session.latest_observation)

func _observation(snapshot: Dictionary) -> void:
	if session.status!=NetworkSession.Status.ACTIVE: return
	var turn: Dictionary=snapshot.turn; var active:=int(turn.active_player)
	var actionable: Array=turn.get("actionable_players",[])
	if actionable.size()==4: saw_simultaneous_stage=true
	print("FFA integration ",role," observes P",active," round ",int(turn.round_number)," revision ",int(snapshot.sync_revision))
	if observed_turns.is_empty() or observed_turns[-1]!=active: observed_turns.append(active)
	if int(turn.round_number)>=2 and role=="host":
		var valid:=saw_simultaneous_stage and movement_accepted and order_accepted
		session.abort_match_to_lobby("Four-player integration complete")
		return _finish(valid,"Observed four simultaneous players, movement-time combat orders, automatic resolution, and round-two synchronization")
	if not actionable.has(session.local_player_id) or movement_submitted: return
	if role in ["host","client3"] and not order_submitted:
		order_submitted=true
		if role=="host":
			var attacker: GameState.Unit; var target_id:=-1
			for unit: GameState.Unit in state.units.values():
				if unit.controller_id==1 and unit.attack_damage>0: attacker=unit; break
			if attacker!=null:
				var targets:=GameRules.new(state).attack_targets(1,attacker.id)
				if not targets.is_empty(): target_id=targets[0]
			session.submit_command(CommandDispatcher.COMBAT_INTENT,{"unit_id":attacker.id,"option_id":"attack","target_id":target_id})
		else:
			var own: Array=snapshot.owned_entities
			var unit_id:=-1
			for entity: Dictionary in own:
				if entity.kind=="unit": unit_id=int(entity.id); break
			session.submit_command(CommandDispatcher.COMBAT_INTENT,{"unit_id":unit_id,"option_id":"dodge"})
		return
	movement_submitted=true; session.submit_command(CommandDispatcher.END_TURN,{})

func _command_result(result: Dictionary) -> void:
	if int(result.client_sequence)==1:
		if role in ["host","client3"]:
			order_accepted=bool(result.accepted)
			if not order_accepted: _finish(false,"Movement-time combat order rejected")
		else:
			movement_accepted=bool(result.accepted)
			if not movement_accepted: _finish(false,"Movement-phase command rejected")
	elif int(result.client_sequence)==2:
		movement_accepted=bool(result.accepted)
		if not movement_accepted: _finish(false,"Movement-phase command rejected")

func _session_ended(reason: String) -> void:
	if role!="host": _finish(movement_accepted and (order_accepted if role=="client3" else true),"Movement and combat workflow accepted; "+reason)

func _finish(ok: bool,message: String) -> void:
	if finishing: return
	finishing=true
	if not result_path.is_empty():
		var file:=FileAccess.open(result_path,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify({"ok":ok,"message":message,"role":role,"player_id":session.local_player_id}))
	create_timer(0.25 if role=="host" else 1.0).timeout.connect(_complete_finish.bind(ok),CONNECT_ONE_SHOT)

func _complete_finish(ok: bool) -> void:
	if session!=null: session.shutdown("integration complete")
	quit(0 if ok else 1)
