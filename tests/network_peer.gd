extends SceneTree

var session: NetworkSession
var role: String=""
var result_path: String=""
var port:=24567
var deadline:=0
var state: GameState
var sent_host_end:=false
var sent_move:=false
var received_duplicate:=false
var sent_client_end:=false
var finishing:=false
var host_turn_restored:=false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role=arg.trim_prefix("--role=")
		elif arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		elif arg.begins_with("--result="): result_path=arg.trim_prefix("--result=")
	deadline=Time.get_ticks_msec()+25000
	session=NetworkSession.new(); session.name="NetworkSession"; root.add_child(session); await process_frame
	session.lobby_changed.connect(_lobby_changed)
	session.match_announced.connect(_match_announced)
	session.observation_received.connect(_observation)
	session.command_completed.connect(_command_result)
	session.status_changed.connect(_status_changed)
	session.participant_disconnected.connect(_participant_disconnected)
	if role=="host":
		if session.host_game(port,"Integration Host","living_migration")!=OK: return _finish(false,session.status_message)
		session.set_local_lobby_choice("living_migration",true)
	else:
		if session.join_game("127.0.0.1",port,"Integration Client","living_migration")!=OK: return _finish(false,session.status_message)
	while Time.get_ticks_msec()<deadline:
		await process_frame
	_finish(false,"Timed out")

func _lobby_changed(_records: Array) -> void:
	if role=="client" and session.status==NetworkSession.Status.LOBBY:
		session.set_local_lobby_choice("living_migration",true)
	elif role=="host" and session.can_host_start() and not session.match_has_started:
		var config:=MatchConfig.new(); config.network_match=true; config.planet_size=MatchConfig.PlanetSize.DEV_TINY
		config.world_population_preset=WorldPopulationConfig.OFF; config.world_seed=818181; config.private_population_seed=919191
		for record: Dictionary in session.lobby_records(): config.player_assignments.append({"player_id":record.player_id,"player_name":record.player_name,"faction_id":record.faction_id,"team_id":record.player_id,"controller_kind":ControllerState.HUMAN})
		var error:=session.announce_match(config.public_network_dictionary())
		if not error.is_empty(): return _finish(false,error)
		state=GameState.new(PlanetGrid.new(3,12.0),{"faction_ids":config.faction_ids(),"controller_kinds":config.controller_kinds(),"team_ids":config.team_ids()})
		session.attach_authority(state,GameRules.new(state))

func _match_announced(_config: Dictionary) -> void: pass

func _status_changed(value: int,_message: String) -> void:
	if role=="host" and value==NetworkSession.Status.ACTIVE and not session.latest_observation.is_empty():
		_observation(session.latest_observation)

func _observation(snapshot: Dictionary) -> void:
	if role=="host":
		if session.status!=NetworkSession.Status.ACTIVE: return
		if not sent_host_end and int(snapshot.turn.active_player)==1:
			sent_host_end=true; session.submit_command(CommandDispatcher.END_TURN,{})
		elif sent_host_end and int(snapshot.turn.active_player)==1:
			host_turn_restored=true
		return
	if int(snapshot.turn.active_player)!=session.local_player_id or sent_move: return
	var own: Array=snapshot.get("owned_entities",[])
	var unit: Dictionary={}
	for entity: Dictionary in own:
		if entity.kind=="unit": unit=entity; break
	if unit.is_empty(): return _finish(false,"No owned unit in observation")
	var occupied:={}
	for entity: Dictionary in own: occupied[int(entity.cell_id)]=true
	var grid:=PlanetGrid.new(3,12.0); var destination:=-1
	for cell_id: int in grid.get_neighbors(int(unit.cell_id)):
		if not occupied.has(cell_id): destination=cell_id; break
	if destination<0: return _finish(false,"No movement destination")
	sent_move=true; session.submit_command(CommandDispatcher.MOVE,{"unit_id":int(unit.id),"destination":destination})

func _command_result(result: Dictionary) -> void:
	if role!="client": return
	if sent_move and not received_duplicate and int(result.client_sequence)==1 and bool(result.accepted):
		# Replay the exact envelope to exercise server-side idempotency over ENet.
		session._rpc_submit_command.rpc_id(1,GameplayCommand.create(1,CommandDispatcher.MOVE,{"unit_id":-1,"destination":-1}))
	elif sent_move and bool(result.get("duplicate",false)):
		received_duplicate=true; sent_client_end=true; session.submit_command(CommandDispatcher.END_TURN,{})
	elif sent_client_end and int(result.client_sequence)==2:
		if bool(result.accepted): _finish(true,"Client moved, duplicate was rejected, and turn ended")
		else: _finish(false,"Client end-turn rejected")

func _participant_disconnected(_player_id: int,_player_name: String) -> void:
	if role=="host" and host_turn_restored:
		_finish(true,"Host observed remote move, completed turn, and clean disconnect")

func _finish(ok: bool,message: String) -> void:
	if finishing: return
	finishing=true
	if result_path.is_empty(): quit(0 if ok else 1); return
	var file:=FileAccess.open(result_path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"ok":ok,"message":message,"role":role}))
	if session!=null: session.shutdown("integration complete")
	await process_frame
	quit(0 if ok else 1)
