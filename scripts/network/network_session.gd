class_name NetworkSession
extends Node
## ENet lifecycle, authenticated peer/player registry, lobby, and observation transport.

signal status_changed(status: int,message: String)
signal lobby_changed(players: Array)
signal lobby_configuration_changed(configuration: Dictionary,capacity: int)
signal match_announced(config: Dictionary)
signal command_completed(result: Dictionary)
signal observation_received(snapshot: Dictionary)
signal participant_disconnected(player_id: int,player_name: String)
signal session_ended(reason: String)
signal resynchronization_requested(expected_revision: int,received_revision: int)

enum Role { OFFLINE, HOST, CLIENT }
enum Status { DISCONNECTED, CONNECTING, LOBBY, LOADING, ACTIVE, INTERRUPTED, ERROR }

var role: Role=Role.OFFLINE
var status: Status=Status.DISCONNECTED
var status_message: String="Offline"
var local_player_id: int=0
var local_player_name: String=""
var local_faction_id: String="living_migration"
var port: int=NetworkProtocol.DEFAULT_PORT
var peer: ENetMultiplayerPeer
var peer_to_player: Dictionary[int,int]={}
var player_to_peer: Dictionary[int,int]={}
var lobby_players: Dictionary[int,Dictionary]={}
var command_dispatcher: CommandDispatcher
var authoritative_state: GameState
var authoritative_rules: GameRules
var latest_observation: Dictionary={}
var sync_revision: int=0
var authoritative_sync_revision: int=0
var next_client_sequence: int=1
var last_command_result: Dictionary={}
var connection_deadline_ms: int=0
var loading_deadline_ms: int=0
var match_has_started: bool=false
var loaded_players: Dictionary[int,bool]={}
var client_loaded_sent: bool=false
var awaiting_resynchronization: bool=false
var lobby_capacity: int=NetworkProtocol.MAX_PLAYERS
var lobby_match_config: Dictionary={
	"planet_size":MatchConfig.PlanetSize.SMALL,
	"world_seed":48293617,
	"world_population_preset":WorldPopulationConfig.STANDARD,
	"villages_per_player":2,
}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	var now:=Time.get_ticks_msec()
	if status==Status.CONNECTING and connection_deadline_ms>0 and now>connection_deadline_ms:
		_fail("Connection timed out.")
	if status==Status.LOADING and loading_deadline_ms>0 and now>loading_deadline_ms:
		_fail("Match synchronization timed out.")

func host_game(listen_port: int,player_name: String,faction_id: String="living_migration",capacity: int=NetworkProtocol.MAX_PLAYERS,
		configuration: Dictionary={}) -> Error:
	shutdown("Starting host")
	if not NetworkProtocol.valid_port(listen_port): return _set_error(ERR_INVALID_PARAMETER,"Choose a valid UDP port.")
	var name:=NetworkProtocol.clean_player_name(player_name)
	if name.is_empty(): return _set_error(ERR_INVALID_PARAMETER,"Enter a player name.")
	if not _valid_faction(faction_id): return _set_error(ERR_INVALID_PARAMETER,"Choose a playable faction.")
	if capacity<NetworkProtocol.MIN_PLAYERS or capacity>NetworkProtocol.MAX_PLAYERS:
		return _set_error(ERR_INVALID_PARAMETER,"Choose two to four player slots.")
	var config_error:=_lobby_configuration_error(configuration)
	if not config_error.is_empty(): return _set_error(ERR_INVALID_PARAMETER,config_error)
	peer=ENetMultiplayerPeer.new()
	var error:=peer.create_server(listen_port,capacity-1)
	if error!=OK:
		peer=null
		return _set_error(error,"Could not host on UDP port %d." % listen_port)
	multiplayer.multiplayer_peer=peer
	role=Role.HOST; port=listen_port; local_player_id=1; local_player_name=name; local_faction_id=faction_id
	lobby_capacity=capacity
	if not configuration.is_empty(): lobby_match_config=_sanitized_lobby_configuration(configuration)
	_register_player(1,1,name,faction_id,true,false)
	_set_status(Status.LOBBY,"Hosting on UDP port %d." % port)
	_emit_lobby()
	return OK

func join_game(address: String,server_port: int,player_name: String,faction_id: String="living_migration") -> Error:
	shutdown("Starting connection")
	var host:=address.strip_edges()
	var name:=NetworkProtocol.clean_player_name(player_name)
	if host.is_empty(): return _set_error(ERR_INVALID_PARAMETER,"Enter a host address.")
	if not NetworkProtocol.valid_port(server_port): return _set_error(ERR_INVALID_PARAMETER,"Choose a valid UDP port.")
	if name.is_empty(): return _set_error(ERR_INVALID_PARAMETER,"Enter a player name.")
	if not _valid_faction(faction_id): return _set_error(ERR_INVALID_PARAMETER,"Choose a playable faction.")
	peer=ENetMultiplayerPeer.new()
	var error:=peer.create_client(host,server_port)
	if error!=OK:
		peer=null
		return _set_error(error,"Could not begin the connection.")
	multiplayer.multiplayer_peer=peer
	role=Role.CLIENT; port=server_port; local_player_name=name; local_faction_id=faction_id
	connection_deadline_ms=Time.get_ticks_msec()+int(NetworkProtocol.CONNECTION_TIMEOUT_SECONDS*1000.0)
	_set_status(Status.CONNECTING,"Connecting to %s:%d..." % [host,server_port])
	return OK

func shutdown(reason: String="Disconnected") -> void:
	get_tree().paused=false
	if peer!=null: peer.close()
	if multiplayer.multiplayer_peer!=null: multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	peer=null; role=Role.OFFLINE; local_player_id=0; match_has_started=false
	lobby_capacity=NetworkProtocol.MAX_PLAYERS
	lobby_match_config={"planet_size":MatchConfig.PlanetSize.SMALL,"world_seed":48293617,
		"world_population_preset":WorldPopulationConfig.STANDARD,"villages_per_player":2}
	peer_to_player.clear(); player_to_peer.clear(); lobby_players.clear(); loaded_players.clear(); client_loaded_sent=false; awaiting_resynchronization=false
	command_dispatcher=null; authoritative_state=null; authoritative_rules=null
	latest_observation.clear(); sync_revision=0; authoritative_sync_revision=0; next_client_sequence=1; last_command_result.clear()
	connection_deadline_ms=0; loading_deadline_ms=0
	_set_status(Status.DISCONNECTED,reason)

func set_local_lobby_choice(faction_id: String,ready: bool) -> void:
	if not _valid_faction(faction_id) or status!=Status.LOBBY: return
	local_faction_id=faction_id
	if role==Role.HOST:
		_update_player(1,faction_id,ready); _broadcast_lobby()
	elif role==Role.CLIENT:
		_rpc_update_lobby.rpc_id(1,faction_id,ready)

func set_host_lobby_configuration(configuration: Dictionary) -> String:
	if role!=Role.HOST or status!=Status.LOBBY: return "Only the lobby host may configure the match."
	var error:=_lobby_configuration_error(configuration)
	if not error.is_empty(): return error
	lobby_match_config=_sanitized_lobby_configuration(configuration)
	for player_id: int in lobby_players:
		var record: Dictionary=lobby_players[player_id]; record.ready=false; lobby_players[player_id]=record
	_broadcast_lobby()
	return ""

func can_host_start() -> bool:
	if role!=Role.HOST or status!=Status.LOBBY or lobby_players.size()<NetworkProtocol.MIN_PLAYERS or lobby_players.size()>lobby_capacity: return false
	for record: Dictionary in lobby_players.values():
		if not bool(record.ready) or not bool(record.get("connected",true)): return false
	return true

func announce_match(config: Dictionary) -> String:
	if not can_host_start(): return "Every connected player must be ready."
	match_has_started=true; loading_deadline_ms=Time.get_ticks_msec()+int(NetworkProtocol.LOADING_TIMEOUT_SECONDS*1000.0)
	_set_status(Status.LOADING,"Loading authoritative match...")
	_rpc_match_announced.rpc(config.duplicate(true))
	match_announced.emit(config.duplicate(true))
	return ""

func attach_authority(state: GameState,rules: GameRules) -> void:
	if role!=Role.HOST: return
	authoritative_state=state; authoritative_rules=rules
	command_dispatcher=CommandDispatcher.new(state,rules)
	loaded_players.clear()
	for peer_id: int in peer_to_player:
		command_dispatcher.register_peer(peer_id,peer_to_player[peer_id]); loaded_players[peer_to_player[peer_id]]=peer_id==1
	authoritative_sync_revision=1; sync_revision=0; loading_deadline_ms=0
	loading_deadline_ms=Time.get_ticks_msec()+int(NetworkProtocol.LOADING_TIMEOUT_SECONDS*1000.0)
	_set_status(Status.LOADING,"Waiting for players to finish loading...")
	_publish_observations()
	_finish_loading_if_ready()

func submit_command(type: String,parameters: Dictionary={}) -> int:
	if status!=Status.ACTIVE: return -1
	var sequence:=next_client_sequence; next_client_sequence+=1
	var command:=GameplayCommand.create(sequence,type,parameters)
	if role==Role.HOST: _server_process_command(1,command)
	elif role==Role.CLIENT: _rpc_submit_command.rpc_id(1,command)
	return sequence

func submit_host_command(type: String,parameters: Dictionary={}) -> Dictionary:
	if role!=Role.HOST or status!=Status.ACTIVE: return {"accepted":false,"public_reason":"Network match is not active."}
	var sequence:=next_client_sequence; next_client_sequence+=1
	last_command_result.clear()
	_server_process_command(1,GameplayCommand.create(sequence,type,parameters))
	return last_command_result.duplicate(true)

func submit_authoritative_command(controller_id: int,type: String,parameters: Dictionary={}) -> Dictionary:
	if role!=Role.HOST or status!=Status.ACTIVE or command_dispatcher==null:
		return {"accepted":false,"public_reason":"Network match is not active."}
	var result:=command_dispatcher.dispatch_authoritative_controller(controller_id,type,parameters)
	if bool(result.accepted):
		authoritative_sync_revision+=1; _publish_observations()
	return result

func publish_authoritative_update() -> void:
	if role!=Role.HOST or status!=Status.ACTIVE or authoritative_state==null: return
	authoritative_sync_revision+=1; _publish_observations()

func request_resynchronization() -> void:
	if status not in [Status.ACTIVE,Status.LOADING]: return
	awaiting_resynchronization=true
	if role==Role.HOST: _send_observation_to_peer(1)
	elif role==Role.CLIENT: _rpc_request_resynchronization.rpc_id(1,sync_revision)

func abort_match_to_lobby(reason: String="Match aborted.") -> void:
	if role==Role.HOST:
		get_tree().paused=false
		match_has_started=false; command_dispatcher=null; authoritative_state=null; authoritative_rules=null
		var departed: Array[int]=[]
		for player_id: int in lobby_players:
			if not bool(lobby_players[player_id].get("connected",true)): departed.append(player_id)
		for player_id: int in departed: lobby_players.erase(player_id)
		for player_id: int in lobby_players:
			var record: Dictionary=lobby_players[player_id]; record.ready=false; lobby_players[player_id]=record
		_rpc_match_aborted.rpc(reason)
		_set_status(Status.LOBBY,reason); _broadcast_lobby()
	elif role==Role.CLIENT:
		_set_status(Status.LOBBY,reason)

func lobby_records() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var ids: Array[int]=[]; ids.assign(lobby_players.keys()); ids.sort()
	for player_id: int in ids: result.append(lobby_players[player_id].duplicate(true))
	return result

func remove_disconnected_player(player_id: int) -> bool:
	if role!=Role.HOST or status!=Status.INTERRUPTED or authoritative_state==null or not lobby_players.has(player_id): return false
	var record: Dictionary=lobby_players[player_id]
	if bool(record.get("connected",true)): return false
	authoritative_state.set_player_connected(player_id,false)
	authoritative_state.eliminate_player(player_id,"Disconnected player removed by host")
	record.eliminated=true; lobby_players[player_id]=record
	get_tree().paused=false
	_set_status(Status.ACTIVE,"%s was removed and eliminated." % String(record.player_name))
	authoritative_sync_revision+=1; _publish_observations(); _broadcast_lobby()
	_rpc_match_resumed.rpc("%s was removed and eliminated." % String(record.player_name))
	return true

@rpc("any_peer","call_remote","reliable")
func _rpc_request_join(payload: Dictionary) -> void:
	if role!=Role.HOST: return
	var sender:=multiplayer.get_remote_sender_id()
	if peer_to_player.has(sender):
		_rpc_join_accepted.rpc_id(sender,peer_to_player[sender],lobby_records(),lobby_match_config.duplicate(true),lobby_capacity); return
	if match_has_started:
		_rpc_join_rejected.rpc_id(sender,"Match already started."); return
	if lobby_players.size()>=lobby_capacity:
		_rpc_join_rejected.rpc_id(sender,"Lobby is full."); return
	var error:=NetworkProtocol.compatibility_error(payload.get("compatibility",{}))
	if not error.is_empty(): _rpc_join_rejected.rpc_id(sender,error); return
	var name:=NetworkProtocol.clean_player_name(String(payload.get("player_name","")))
	var faction:=String(payload.get("faction_id",""))
	if name.is_empty() or not _valid_faction(faction): _rpc_join_rejected.rpc_id(sender,"Invalid player registration."); return
	var player_id:=_next_player_id()
	_register_player(sender,player_id,name,faction,false,false)
	_rpc_join_accepted.rpc_id(sender,player_id,lobby_records(),lobby_match_config.duplicate(true),lobby_capacity)
	_broadcast_lobby()

@rpc("authority","call_remote","reliable")
func _rpc_join_accepted(player_id: int,records: Array,configuration: Dictionary={},capacity: int=NetworkProtocol.MAX_PLAYERS) -> void:
	if role!=Role.CLIENT: return
	local_player_id=player_id; connection_deadline_ms=0; lobby_capacity=capacity; lobby_match_config=_sanitized_lobby_configuration(configuration)
	_apply_lobby(records); _set_status(Status.LOBBY,"Connected to lobby.")

@rpc("authority","call_remote","reliable")
func _rpc_join_rejected(reason: String) -> void:
	if role==Role.CLIENT: _fail(reason)

@rpc("any_peer","call_remote","reliable")
func _rpc_update_lobby(faction_id: String,ready: bool) -> void:
	if role!=Role.HOST or match_has_started: return
	var sender:=multiplayer.get_remote_sender_id()
	if not peer_to_player.has(sender) or not _valid_faction(faction_id): return
	_update_player(peer_to_player[sender],faction_id,ready); _broadcast_lobby()

@rpc("authority","call_remote","reliable")
func _rpc_lobby_state(records: Array,configuration: Dictionary={},capacity: int=NetworkProtocol.MAX_PLAYERS) -> void:
	if role==Role.CLIENT:
		lobby_capacity=capacity; lobby_match_config=_sanitized_lobby_configuration(configuration); _apply_lobby(records)

@rpc("authority","call_remote","reliable")
func _rpc_match_announced(config: Dictionary) -> void:
	if role!=Role.CLIENT: return
	match_has_started=true; loading_deadline_ms=Time.get_ticks_msec()+int(NetworkProtocol.LOADING_TIMEOUT_SECONDS*1000.0)
	_set_status(Status.LOADING,"Loading match..."); match_announced.emit(config.duplicate(true))

@rpc("any_peer","call_remote","reliable")
func _rpc_submit_command(command: Dictionary) -> void:
	if role==Role.HOST: _server_process_command(multiplayer.get_remote_sender_id(),command)

@rpc("authority","call_remote","reliable")
func _rpc_command_result(result: Dictionary) -> void:
	if role==Role.CLIENT: command_completed.emit(result.duplicate(true))

@rpc("authority","call_remote","reliable")
func _rpc_observation(snapshot: Dictionary) -> void:
	if role==Role.CLIENT: _receive_observation(snapshot)

@rpc("any_peer","call_remote","reliable")
func _rpc_request_resynchronization(_client_revision: int) -> void:
	if role==Role.HOST: _send_observation_to_peer(multiplayer.get_remote_sender_id())

@rpc("any_peer","call_remote","reliable")
func _rpc_client_loaded(sync_value: int) -> void:
	if role!=Role.HOST or sync_value!=authoritative_sync_revision: return
	var sender:=multiplayer.get_remote_sender_id()
	if peer_to_player.has(sender): loaded_players[peer_to_player[sender]]=true; _finish_loading_if_ready()

@rpc("authority","call_remote","reliable")
func _rpc_match_aborted(reason: String) -> void:
	if role==Role.CLIENT:
		match_has_started=false; latest_observation.clear(); sync_revision=0
		_set_status(Status.LOBBY,reason); session_ended.emit(reason)

@rpc("authority","call_remote","reliable")
func _rpc_match_interrupted(player_id: int,player_name: String) -> void:
	if role!=Role.CLIENT: return
	_set_status(Status.INTERRUPTED,"%s disconnected. Match paused." % player_name)
	participant_disconnected.emit(player_id,player_name)

@rpc("authority","call_remote","reliable")
func _rpc_match_resumed(message: String) -> void:
	if role==Role.CLIENT:
		_set_status(Status.ACTIVE,message)
		if not latest_observation.is_empty(): observation_received.emit(latest_observation.duplicate(true))

func _server_process_command(peer_id: int,command: Dictionary) -> void:
	if role!=Role.HOST or status!=Status.ACTIVE or command_dispatcher==null: return
	var result:=command_dispatcher.dispatch(peer_id,command)
	if peer_id==1:
		last_command_result=result.duplicate(true); command_completed.emit(result.duplicate(true))
	else: _rpc_command_result.rpc_id(peer_id,result)
	if bool(result.accepted):
		authoritative_sync_revision+=1
		_publish_observations()

func _publish_observations() -> void:
	for peer_id: int in peer_to_player: _send_observation_to_peer(peer_id)

func _send_observation_to_peer(peer_id: int) -> void:
	if authoritative_state==null or not peer_to_player.has(peer_id): return
	var snapshot:=ObservationCodec.encode(authoritative_state,peer_to_player[peer_id],authoritative_sync_revision)
	if peer_id==1: _receive_observation(snapshot)
	else: _rpc_observation.rpc_id(peer_id,snapshot)

func _receive_observation(snapshot: Dictionary) -> void:
	var error:=ObservationCodec.validation_error(snapshot)
	if not error.is_empty(): _fail("Synchronization failed."); return
	var incoming:=int(snapshot.sync_revision)
	if incoming<=sync_revision and not latest_observation.is_empty(): return
	if sync_revision>0 and incoming>sync_revision+1 and not awaiting_resynchronization:
		resynchronization_requested.emit(sync_revision+1,incoming)
		request_resynchronization(); return
	sync_revision=incoming; awaiting_resynchronization=false; latest_observation=snapshot.duplicate(true); loading_deadline_ms=0
	if role==Role.CLIENT and not client_loaded_sent:
		client_loaded_sent=true; _rpc_client_loaded.rpc_id(1,incoming)
	# A snapshot acknowledges this client's load, but does not make the client
	# actionable yet: other players may still be loading. The host broadcasts
	# the readiness barrier only after every acknowledgement has arrived.
	observation_received.emit(latest_observation.duplicate(true))

func _on_connected_to_server() -> void:
	if role!=Role.CLIENT: return
	_rpc_request_join.rpc_id(1,{"compatibility":NetworkProtocol.handshake(),"player_name":local_player_name,"faction_id":local_faction_id})

func _on_connection_failed() -> void:
	if role==Role.CLIENT: _fail("Connection failed. Check the address and UDP port.")

func _on_server_disconnected() -> void:
	if role!=Role.CLIENT: return
	peer=null; match_has_started=false; latest_observation.clear()
	_set_status(Status.INTERRUPTED,"Host disconnected. Session ended.")
	session_ended.emit(status_message)

func _on_peer_connected(_peer_id: int) -> void: pass

func _on_peer_disconnected(peer_id: int) -> void:
	if role!=Role.HOST or not peer_to_player.has(peer_id): return
	var player_id:=peer_to_player[peer_id]
	var record: Dictionary=lobby_players.get(player_id,{})
	peer_to_player.erase(peer_id); player_to_peer.erase(player_id)
	if command_dispatcher!=null: command_dispatcher.unregister_peer(peer_id)
	if match_has_started:
		record.connected=false; record.ready=false; lobby_players[player_id]=record
		if authoritative_state!=null:
			var was_active:=authoritative_state.active_player==player_id
			authoritative_state.set_player_connected(player_id,false)
			authoritative_state.eliminate_player(player_id,"Disconnected")
			if authoritative_state.turn_state.phase==TurnState.COMBAT_RESOLUTION and authoritative_rules!=null: authoritative_rules.resolve_combat_phase()
			elif was_active and authoritative_rules!=null and authoritative_state.turn_state.phase==TurnState.MANAGEMENT:
				authoritative_rules.living_migration_rules.start_turn(authoritative_state.active_player)
				authoritative_rules.baumeister_rules.start_turn(authoritative_state.active_player)
		record.eliminated=true; lobby_players[player_id]=record
		get_tree().paused=false
		_set_status(Status.ACTIVE,"%s disconnected and was eliminated." % String(record.get("player_name","Player")))
		authoritative_sync_revision+=1; _publish_observations(); _broadcast_lobby()
		_rpc_match_resumed.rpc("%s disconnected and was eliminated." % String(record.get("player_name","Player")))
		participant_disconnected.emit(player_id,String(record.get("player_name","Player")))
	else:
		lobby_players.erase(player_id)
		for remaining_id: int in lobby_players:
			var remaining: Dictionary=lobby_players[remaining_id]; remaining.ready=false; lobby_players[remaining_id]=remaining
		_broadcast_lobby()

func _register_player(peer_id: int,player_id: int,name: String,faction_id: String,host: bool,ready: bool) -> void:
	peer_to_player[peer_id]=player_id; player_to_peer[player_id]=peer_id
	lobby_players[player_id]={"player_id":player_id,"peer_id":peer_id,"player_name":name,"faction_id":faction_id,
		"ready":ready,"host":host,"connected":true,"eliminated":false,
		"player_color":PlayerIdentity.color_hex_for_slot(maxi(0,player_id-1)),
		"color_name":PlayerIdentity.color_name_for_slot(maxi(0,player_id-1))}

func _finish_loading_if_ready() -> void:
	if role!=Role.HOST or authoritative_state==null: return
	for player_id: int in player_to_peer:
		if not bool(loaded_players.get(player_id,false)): return
	loading_deadline_ms=0; _set_status(Status.ACTIVE,"Connected")
	_rpc_match_resumed.rpc("Connected")

func _update_player(player_id: int,faction_id: String,ready: bool) -> void:
	if not lobby_players.has(player_id): return
	var record: Dictionary=lobby_players[player_id]
	var changed:=String(record.faction_id)!=faction_id
	record.faction_id=faction_id; record.ready=false if changed else ready; lobby_players[player_id]=record
	if player_id==local_player_id: local_faction_id=faction_id

func _next_player_id() -> int:
	for id in range(1,lobby_capacity+1):
		if not lobby_players.has(id): return id
	return -1

func _broadcast_lobby() -> void:
	var records:=lobby_records(); _emit_lobby()
	var connected_peers:=multiplayer.get_peers()
	for peer_id: int in peer_to_player:
		if peer_id!=1 and peer_id in connected_peers:
			_rpc_lobby_state.rpc_id(peer_id,records,lobby_match_config.duplicate(true),lobby_capacity)

func _apply_lobby(records: Array) -> void:
	lobby_players.clear(); peer_to_player.clear(); player_to_peer.clear()
	for item: Variant in records:
		if not item is Dictionary: continue
		var record: Dictionary=(item as Dictionary).duplicate(true)
		var player_id:=int(record.get("player_id",0)); var peer_id:=int(record.get("peer_id",0))
		lobby_players[player_id]=record; peer_to_player[peer_id]=player_id; player_to_peer[player_id]=peer_id
		if player_id==local_player_id: local_faction_id=String(record.get("faction_id",local_faction_id))
	_emit_lobby()

func _emit_lobby() -> void:
	lobby_changed.emit(lobby_records())
	lobby_configuration_changed.emit(lobby_match_config.duplicate(true),lobby_capacity)

func _valid_faction(faction_id: String) -> bool:
	var definition:=ContentRegistry.default().faction(faction_id)
	return definition!=null and definition.playable and faction_id in NetworkProtocol.MULTIPLAYER_FACTIONS

func _lobby_configuration_error(configuration: Dictionary) -> String:
	if configuration.is_empty(): return ""
	var size:=int(configuration.get("planet_size",MatchConfig.PlanetSize.SMALL))
	if size not in MatchConfig.normal_planet_sizes(): return "Choose Small or Medium planet size."
	if String(configuration.get("world_population_preset",WorldPopulationConfig.STANDARD)) not in WorldPopulationConfig.PRESETS:
		return "Choose a valid world population preset."
	if int(configuration.get("villages_per_player",2))<0 or int(configuration.get("villages_per_player",2))>4:
		return "Choose zero to four villages per player."
	if String(configuration.get("cliff_generation","Rare")) not in TerracedTerrain.CLIFF_PRESETS: return "Choose a valid cliff generation preset."
	return ""

func _sanitized_lobby_configuration(configuration: Dictionary) -> Dictionary:
	return {"planet_size":int(configuration.get("planet_size",MatchConfig.PlanetSize.SMALL)),
		"world_seed":int(configuration.get("world_seed",48293617)),
		"world_population_preset":String(configuration.get("world_population_preset",WorldPopulationConfig.STANDARD)),
		"villages_per_player":clampi(int(configuration.get("villages_per_player",2)),0,4),"cliff_generation":String(configuration.get("cliff_generation","Rare"))}

func _set_status(value: Status,message: String) -> void:
	status=value; status_message=message; status_changed.emit(status,message)

func _fail(message: String) -> void:
	if peer!=null: peer.close()
	peer=null; connection_deadline_ms=0; loading_deadline_ms=0
	_set_status(Status.ERROR,message)

func _set_error(code: Error,message: String) -> Error:
	_set_status(Status.ERROR,message); return code
