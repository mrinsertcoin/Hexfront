extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func _run() -> void:
	test_protocol_and_config()
	test_dispatch_authority_and_idempotency()
	test_representative_command_coverage()
	test_observation_security_and_serialization()
	await test_session_lifecycle()
	print("Multiplayer foundation checks complete; checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func test_protocol_and_config() -> void:
	var handshake:=NetworkProtocol.handshake()
	check(NetworkProtocol.compatibility_error(handshake).is_empty(),"Matching protocol/content handshake is accepted")
	var mismatch:=handshake.duplicate(); mismatch.protocol_version=999
	check(NetworkProtocol.compatibility_error(mismatch).contains("protocol"),"Protocol mismatch is rejected clearly")
	mismatch=handshake.duplicate(); mismatch.content_fingerprint="wrong"
	check(NetworkProtocol.compatibility_error(mismatch).contains("content"),"Content fingerprint mismatch is rejected clearly")
	check(GameplayCommand.validation_error(GameplayCommand.create(1,CommandDispatcher.END_TURN,{})).is_empty(),"Primitive command envelope validates")
	check(not GameplayCommand.validation_error({"protocol_version":1,"client_sequence":1,"command_type":"x","parameters":{"node":Node.new()}}).is_empty(),"Object payloads are rejected")
	var config:=MatchConfig.new(); config.network_match=true
	for id in range(1,5): config.player_assignments.append({"player_id":id,"faction_id":"living_migration","team_id":id,"controller_kind":ControllerState.HUMAN})
	check(config.validate().is_empty() and config.faction_ids().size()==4,"Four-player-ready config permits duplicate faction selections")
	config.private_population_seed=123456
	check(not config.public_network_dictionary().has("private_population_seed"),"Private population seed is never included in public match config")
	check(CommandDispatcher.COMMAND_TYPES.size()==31 and CommandDispatcher.LAY_LARVA in CommandDispatcher.COMMAND_TYPES and CommandDispatcher.CONSUME in CommandDispatcher.COMMAND_TYPES and CommandDispatcher.COMBAT_INTENT in CommandDispatcher.COMMAND_TYPES and CommandDispatcher.LOCK_COMBAT in CommandDispatcher.COMMAND_TYPES,"Command inventory covers every current mutating player action")

func test_dispatch_authority_and_idempotency() -> void:
	var state:=GameState.new(PlanetGrid.new(2))
	var rules:=GameRules.new(state)
	var dispatcher:=CommandDispatcher.new(state,rules)
	dispatcher.register_peer(1,1); dispatcher.register_peer(683241,2)
	var unit: GameState.Unit
	for candidate: GameState.Unit in state.units.values():
		if candidate.controller_id==1: unit=candidate; break
	var destinations:=rules.reachable(1,unit.id)
	check(not destinations.is_empty(),"Fixture has a legal authoritative movement")
	var before_cell:=unit.cell_id
	var denied:=dispatcher.dispatch(683241,GameplayCommand.create(1,CommandDispatcher.MOVE,{"unit_id":unit.id,"destination":destinations[0]}))
	check(not denied.accepted and unit.cell_id==before_cell,"Mapped remote peer cannot act for another player")
	var accepted:=dispatcher.dispatch(1,GameplayCommand.create(1,CommandDispatcher.MOVE,{"unit_id":unit.id,"destination":destinations[0]}))
	check(accepted.accepted and unit.cell_id==destinations[0] and not accepted.path.is_empty(),"Authenticated host command executes through GameRules")
	var once_snapshot:=TestState.snapshot(state)
	var duplicate:=dispatcher.dispatch(1,GameplayCommand.create(1,CommandDispatcher.MOVE,{"unit_id":unit.id,"destination":before_cell}))
	check(not duplicate.accepted and duplicate.duplicate and TestState.snapshot(state)==once_snapshot,"Duplicate sequence cannot mutate state twice")
	var skipped:=dispatcher.dispatch(1,GameplayCommand.create(3,CommandDispatcher.END_TURN,{}))
	check(not skipped.accepted and skipped.public_reason.contains("out of order"),"Missing command sequence is detected")
	var unsupported:=dispatcher.dispatch(1,GameplayCommand.create(2,"cheat_resources",{"materials":9999}))
	check(not unsupported.accepted and unsupported.public_reason=="Unsupported command.","Unsupported command is rejected without mutation")
	var ended:=dispatcher.dispatch(1,GameplayCommand.create(3,CommandDispatcher.END_TURN,{}))
	check(ended.accepted and state.active_player==2,"Host-owned turn sequencing advances only through dispatcher")
	var remote_unit: GameState.Unit
	for candidate: GameState.Unit in state.units.values():
		if candidate.controller_id==2: remote_unit=candidate; break
	var remote_destinations:=rules.reachable(2,remote_unit.id)
	var remote_move:=dispatcher.dispatch(683241,GameplayCommand.create(2,CommandDispatcher.MOVE,{"unit_id":remote_unit.id,"destination":remote_destinations[0]}))
	check(remote_move.accepted,"Explicit peer-to-player mapping works when peer ID differs from player ID")
	var board:=PlanetBoard.new(); board.match_mode="Network"; board.game_state=state; board.network_session=NetworkSession.new(); board.network_session.local_player_id=1
	check(state.active_player==2 and board._view_controller_id()==1,"Host presentation remains on its local observation during the remote turn")
	board.network_session.free(); board.free()
	for required: String in [CommandDispatcher.MOVE,CommandDispatcher.ATTACK,CommandDispatcher.END_TURN,
		CommandDispatcher.RECRUIT,CommandDispatcher.START_RESEARCH,CommandDispatcher.SITE_INTERACTION,
		CommandDispatcher.QUEUE_BIOLOGICAL_PRODUCTION,CommandDispatcher.BUILD_DISTRICT,
		CommandDispatcher.START_BRIDGE_EXTENSION,CommandDispatcher.DESIGNATE_TARGET]:
		check(required in CommandDispatcher.COMMAND_TYPES,"Command inventory exposes "+required)

func test_representative_command_coverage() -> void:
	# Core recruitment.
	var state:=GameState.new(PlanetGrid.new(2))
	var rules:=GameRules.new(state); var dispatcher:=CommandDispatcher.new(state,rules); dispatcher.register_peer(501,1)
	var headquarters: GameState.Structure
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==1: headquarters=structure; break
	var unit_id:=rules.available_units(1)[0]; var cells:=rules.recruit_destinations(1,headquarters.id,unit_id)
	var recruited:=dispatcher.dispatch(501,GameplayCommand.create(1,CommandDispatcher.RECRUIT,{"headquarters_id":headquarters.id,"unit_id":unit_id,"destination":cells[0]}))
	check(recruited.accepted,"Recruitment executes through the network dispatcher")
	# Living Migration production and research.
	state=GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","baumeister"]})
	rules=GameRules.new(state); dispatcher=CommandDispatcher.new(state,rules); dispatcher.register_peer(7001,1)
	var spider: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1 and unit.spider_state!=null: spider=unit; break
	state.players[1].resources={"food":999,"silk":999,"synapse":999}
	var production:=dispatcher.dispatch(7001,GameplayCommand.create(1,CommandDispatcher.QUEUE_BIOLOGICAL_PRODUCTION,{"spider_id":spider.id,"recipe_id":"worker_ant_brood"}))
	check(production.accepted,"Living Migration biological production executes through dispatcher")
	spider.spider_state.slots.append("research_building")
	var research:=dispatcher.dispatch(7001,GameplayCommand.create(2,CommandDispatcher.START_RESEARCH,{"technology_id":"lm_symbiotic_foundations"}))
	check(research.accepted,"Research executes through dispatcher")
	# Baumeister district construction.
	state=GameState.new(PlanetGrid.new(2),{"faction_ids":["baumeister","living_migration"]})
	rules=GameRules.new(state); dispatcher=CommandDispatcher.new(state,rules); dispatcher.register_peer(8119,1)
	var pillar: GameState.Structure
	for structure: GameState.Structure in state.structures.values():
		if structure.controller_id==1 and structure.pillar_state!=null: pillar=structure; break
	state.players[1].resources={"food":999,"materials":999,"energy":999,"unity":999}
	var district_cell:=state.grid.get_neighbors(pillar.cell_id)[3]
	var built:=dispatcher.dispatch(8119,GameplayCommand.create(1,CommandDispatcher.BUILD_DISTRICT,{"pillar_id":pillar.id,"cell_id":district_cell,"district_id":"mine"}))
	check(built.accepted,"Baumeister district construction executes through dispatcher")
	# World-site interaction.
	state=GameState.new(PlanetGrid.new(2),{"faction_ids":["living_migration","baumeister"]}); rules=GameRules.new(state); dispatcher=CommandDispatcher.new(state,rules); dispatcher.register_peer(9555,1)
	var actor: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1: actor=unit; break
	var site:=state.add_world_site("food_source",actor.cell_id); state.refresh_visibility()
	var interaction:=dispatcher.dispatch(9555,GameplayCommand.create(1,CommandDispatcher.SITE_INTERACTION,{"site_id":site.id,"interaction_id":"gather","unit_id":actor.id}))
	check(interaction.accepted,"World-site interaction executes through dispatcher")

func test_observation_security_and_serialization() -> void:
	var grid:=PlanetGrid.new(2)
	var state:=GameState.new(grid)
	var hidden: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==2: hidden=unit; break
	var hidden_site:=state.add_world_site("ancient_ruin",hidden.cell_id)
	var hidden_corpse:=state.living_migration.add_corpse(hidden.definition_id,hidden.cell_id,3)
	state.refresh_visibility()
	var snapshot:=ObservationCodec.encode(state,1,1)
	check(not ObservationCodec.contains_forbidden_hidden_id(snapshot,hidden.id),"Serialized recipient snapshot omits an unseen enemy")
	var visible_world: Dictionary=snapshot.visible_world_state
	check(not snapshot.observed_sites.any(func(site: Dictionary)->bool: return int(site.id)==hidden_site.id)
		and not visible_world.corpses.any(func(corpse: Dictionary)->bool: return int(corpse.id)==hidden_corpse.id),"Undiscovered sites and hidden corpses are absent from the wire snapshot")
	check(not snapshot.has("game_state") and not snapshot.has("world_sites") and not snapshot.has("units"),"Snapshot never embeds unrestricted authoritative dictionaries")
	check(not snapshot.own_player.has("enemy_resources"),"Recipient receives only its own economy and research state")
	var encoded:=JSON.stringify(snapshot)
	var round_trip: Variant=JSON.parse_string(encoded)
	check(round_trip is Dictionary and ObservationCodec.validation_error(round_trip).is_empty(),"Permitted snapshot is primitive and JSON round-trippable")
	var decoded:=ObservationCodec.decode_observation(snapshot)
	check(decoded!=null and decoded.team_id==state.controllers[1].team_id,"Snapshot restores presentation observation without GameState")
	var receiver:=NetworkSession.new()
	receiver.status=NetworkSession.Status.ACTIVE
	var first_snapshot:=ObservationCodec.encode(state,1,1); receiver._receive_observation(first_snapshot)
	var gap_signals: Array[Vector2i]=[]; receiver.resynchronization_requested.connect(func(expected: int,received: int)->void: gap_signals.append(Vector2i(expected,received)))
	var late_snapshot:=ObservationCodec.encode(state,1,3); receiver._receive_observation(late_snapshot)
	check(gap_signals==[Vector2i(2,3)] and receiver.sync_revision==1 and receiver.awaiting_resynchronization,"Missing snapshot revision triggers explicit resynchronization")
	receiver._receive_observation(late_snapshot)
	check(receiver.sync_revision==3 and not receiver.awaiting_resynchronization,"Full resynchronization accepts the current authoritative revision")
	receiver.free()
	var observer: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1: observer=unit; break
	for id: int in state.units.keys():
		if state.units[id].controller_id==1 and id!=observer.id: state.units.erase(id)
	for id: int in state.structures.keys():
		if state.structures[id].controller_id==1: state.structures.erase(id)
	hidden.cell_id=grid.get_neighbors(observer.cell_id)[0]; state.refresh_visibility()
	snapshot=ObservationCodec.encode(state,1,2)
	check(ObservationCodec.contains_forbidden_hidden_id(snapshot,hidden.id),"Observed enemy is present in its recipient snapshot")
	var observed_hp:=hidden.hp
	observer.cell_id=grid.breadth_first(hidden.cell_id).order[-1]; state.refresh_visibility()
	hidden.hp=maxi(1,hidden.hp-2); state.refresh_visibility()
	snapshot=ObservationCodec.encode(state,1,3)
	var contact_hp:=-1
	for contact: Dictionary in snapshot.known_contacts:
		if int(contact.contact_id)==hidden.id: contact_hp=int(contact.observed_snapshot.hp)
	check(contact_hp==observed_hp,"Historical contact does not receive hidden live HP updates")

func test_session_lifecycle() -> void:
	var session:=NetworkSession.new(); root.add_child(session); await process_frame
	var port:=26000+int(Time.get_ticks_msec()%2000)
	var first:=session.host_game(port,"Host","living_migration")
	check(first==OK and session.role==NetworkSession.Role.HOST and session.peer_to_player.get(1)==1,"ENet server starts with explicit host peer/player registration")
	session.shutdown("test")
	var second:=session.host_game(port,"Host Again","baumeister")
	check(second==OK and session.lobby_players.size()==1,"Hosting can be repeated without stale session state")
	session._register_player(88421,2,"Remote","living_migration",false,true)
	session._on_peer_disconnected(88421)
	check(session.status==NetworkSession.Status.LOBBY and not session.lobby_players.has(2),"Lobby disconnection removes peer/player mapping cleanly")
	session._register_player(88422,2,"Remote","living_migration",false,true); session.match_has_started=true
	session._on_peer_disconnected(88422)
	check(session.status==NetworkSession.Status.INTERRUPTED and paused,"Active-match disconnection pauses authoritative progression")
	paused=false
	session.shutdown("done"); session.queue_free(); await process_frame
	var client:=NetworkSession.new(); root.add_child(client); await process_frame
	client.role=NetworkSession.Role.CLIENT
	client._on_server_disconnected()
	check(client.status==NetworkSession.Status.INTERRUPTED and client.status_message.contains("Host disconnected"),"Host loss produces an explicit session-ended state")
	client.role=NetworkSession.Role.OFFLINE; client.status=NetworkSession.Status.LOADING; client.loading_deadline_ms=Time.get_ticks_msec()-1
	client._process(0.0)
	check(client.status==NetworkSession.Status.ERROR and client.status_message.contains("timed out"),"Loading timeout terminates predictably")
	client.queue_free(); await process_frame
