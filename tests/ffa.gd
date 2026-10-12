extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(message)

func _run() -> void:
	test_player_counts_identity_and_starts()
	test_turn_order_elimination_and_victory()
	test_same_faction_and_cross_faction_combat()
	test_authoritative_ownership_security()
	test_complete_match_combat()
	test_independent_observations()
	await test_lobby_capacity_ready_and_disconnect()
	print("Four-player FFA checks complete; checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func _setup(factions: Array[String],ids: Array[int]=[]) -> Dictionary:
	var player_ids: Array[int]=ids.duplicate()
	if player_ids.is_empty():
		for index in range(factions.size()): player_ids.append(index+1)
	var names: Array[String]=[]; var colors: Array[String]=[]; var teams: Array[int]=[]; var kinds: Array[String]=[]
	for index in range(player_ids.size()):
		names.append("FFA %d" % player_ids[index]); colors.append(PlayerIdentity.color_hex_for_slot(index))
		teams.append(player_ids[index]); kinds.append(ControllerState.HUMAN)
	return {"player_ids":player_ids,"player_names":names,"player_colors":colors,"faction_ids":factions,
		"team_ids":teams,"controller_kinds":kinds,"start_seed":191919,"simultaneous_combat":false}

func _with_uniform_suitability(setup: Dictionary,cell_count: int) -> Dictionary:
	var result:=setup.duplicate(true); var values:={}
	for player_id: int in result.player_ids:
		var row: Array[float]=[]; row.resize(cell_count); row.fill(0.5); values[player_id]=row
	result.start_suitability=values
	return result

func test_player_counts_identity_and_starts() -> void:
	for count in range(2,5):
		var factions: Array[String]=[]
		for index in range(count): factions.append("living_migration" if index%2==0 else "baumeister")
		var grid:=PlanetGrid.new(3,12.0)
		var state:=GameState.new(grid,_with_uniform_suitability(_setup(factions),grid.get_cell_count()))
		check(state.players.size()==count and state.turn_state.order.size()==count,"State creates exactly %d FFA participants" % count)
		check(state.starting_cells.size()==count,"State creates exactly %d globally distributed starts" % count)
		var starts: Array[int]=[]; starts.assign(state.starting_cells.values())
		var minimum:=2147483647
		for a in range(starts.size()):
			for b in range(a+1,starts.size()): minimum=mini(minimum,grid.distance(starts[a],starts[b]))
		var diameter:=grid.breadth_first(0).costs[grid.breadth_first(0).order[-1]]
		check(minimum>=maxi(2,int(diameter/3)),"%d-player starts use graph-distance maximin spacing" % count)
	var duplicate:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","living_migration","living_migration","living_migration"]))
	var colors:={}
	for player_id: int in duplicate.players:
		colors[duplicate.players[player_id].ownership_color]=true
		for opponent_id: int in duplicate.players:
			if player_id<opponent_id: check(duplicate.relationships.is_hostile(player_id,opponent_id),"Same-faction FFA players remain hostile")
	check(colors.size()==4,"Four ownership colors remain distinct from duplicated faction identity")
	var p1_food:=duplicate.players[1].resource_amount("food"); var p2_food:=duplicate.players[2].resource_amount("food")
	duplicate.players[1].resources.food=p1_food+50; duplicate.players[1].research.completed_ids.append("lm_symbiotic_foundations")
	check(duplicate.players[2].resource_amount("food")==p2_food and duplicate.players[2].research.completed_ids.is_empty(),"Duplicate factions never share economy or research state")
	var sparse:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","baumeister"],[1,3]))
	check(sparse.players.has(1) and sparse.players.has(3) and not sparse.players.has(2) and sparse.turn_state.order==[1,3],"Explicit non-contiguous lobby player IDs survive match creation")

func test_turn_order_elimination_and_victory() -> void:
	var state:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","baumeister","living_migration","baumeister"]))
	state.turn_state.neutral_phase_enabled=true
	var sequence: Array[int]=[state.active_player]
	for _step in range(4): sequence.append(state.advance_turn())
	check(sequence==[1,2,3,4,state.turn_state.neutral_controller_id] and state.turn_state.neutral_phase,"Four human turns lead to one neutral phase")
	sequence.append(state.advance_turn())
	check(sequence[-1]==1 and state.round_number==2 and not state.turn_state.neutral_phase,"Neutral phase advances exactly once into the next round")
	state.eliminate_player(2,"test")
	state.turn_state.index=0; state.turn_state.neutral_phase=false
	check(state.advance_turn()==3,"Eliminated P2 is skipped between P1 and P3")
	check(not state.units.values().any(func(unit: GameState.Unit)->bool: return unit.controller_id==2)
		and not state.structures.values().any(func(structure: GameState.Structure)->bool: return structure.controller_id==2),"Elimination removes remaining faction entities")
	state.eliminate_player(3,"test")
	check(state.winner_id==0,"Match continues while two players remain")
	state.eliminate_player(4,"test")
	check(state.winner_id==1 and state.public_events.any(func(event: Dictionary)->bool: return event.type=="match_won"),"Exactly one surviving player wins and emits a public event")
	var dispatcher:=CommandDispatcher.new(state,GameRules.new(state)); dispatcher.register_peer(404,2)
	var rejected:=dispatcher.dispatch(404,GameplayCommand.create(1,CommandDispatcher.END_TURN,{}))
	check(not rejected.accepted,"Eliminated players cannot issue commands")

func _combat_fixture(factions: Array[String]) -> Dictionary:
	var state:=GameState.new(PlanetGrid.new(2),_setup(factions))
	var attacker: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1 and unit.attack_damage>0: attacker=unit; break
	var target: RefCounted
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==2 and "headquarters" in state.registry.unit(unit.definition_id).tags: target=unit; break
	if target==null:
		for structure: GameState.Structure in state.structures.values():
			if structure.controller_id==2 and "headquarters" in state.registry.structure(structure.definition_id).tags: target=structure; break
	var destination:=-1
	for cell_id: int in state.grid.get_neighbors(attacker.cell_id):
		if not state.is_cell_blocked(cell_id,target.id): destination=cell_id; break
	target.cell_id=destination; target.hp=1; state.refresh_visibility()
	return {"state":state,"attacker":attacker,"target":target}

func test_same_faction_and_cross_faction_combat() -> void:
	var cases: Array=[
		["living_migration","living_migration","baumeister","baumeister"],
		["baumeister","baumeister","living_migration","living_migration"],
		["living_migration","baumeister","living_migration","baumeister"]]
	for raw_factions: Array in cases:
		var factions: Array[String]=[]; factions.assign(raw_factions)
		var fixture:=_combat_fixture(factions); var state: GameState=fixture.state
		var result:=GameRules.new(state).try_attack(1,fixture.attacker.id,fixture.target.id)
		check(result.success and state.players[2].eliminated and state.winner_id==0,"Ownership-driven combat eliminates one opponent without ending a four-player match")

func test_authoritative_ownership_security() -> void:
	var state:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","baumeister","living_migration","baumeister"]))
	var dispatcher:=CommandDispatcher.new(state,GameRules.new(state))
	for player_id in range(1,5): dispatcher.register_peer(9000+player_id,player_id)
	var units:={}
	for unit: GameState.Unit in state.units.values():
		if not units.has(unit.controller_id): units[unit.controller_id]=unit
	var snapshot:=TestState.snapshot(state)
	var responses: Array[Dictionary]=[
		dispatcher.dispatch(9001,GameplayCommand.create(1,CommandDispatcher.MOVE,{"unit_id":units[2].id,"destination":units[2].cell_id})),
		dispatcher.dispatch(9002,GameplayCommand.create(1,CommandDispatcher.BUILD_DISTRICT,{"pillar_id":units[3].id,"cell_id":units[3].cell_id,"district_id":"mine"})),
		dispatcher.dispatch(9003,GameplayCommand.create(1,CommandDispatcher.END_TURN,{})),
		dispatcher.dispatch(9004,GameplayCommand.create(1,CommandDispatcher.START_RESEARCH,{"technology_id":"lm_symbiotic_foundations"}))]
	check(responses.all(func(response: Dictionary)->bool: return not bool(response.accepted)) and TestState.snapshot(state)==snapshot,
		"P1/P2/P3/P4 cannot move, build, end turns, or research through another player's authority")

func test_complete_match_combat() -> void:
	var state:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","baumeister","living_migration","baumeister"]))
	var attackers: Array[GameState.Unit]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==1 and unit.attack_damage>0: attackers.append(unit)
	for victim_id in [2,3,4]:
		var target: RefCounted
		for unit: GameState.Unit in state.units.values():
			if unit.controller_id==victim_id and "headquarters" in state.registry.unit(unit.definition_id).tags: target=unit; break
		if target==null:
			for structure: GameState.Structure in state.structures.values():
				if structure.controller_id==victim_id and "headquarters" in state.registry.structure(structure.definition_id).tags: target=structure; break
		var attacker:=attackers[0]
		attacker.moved=false; attacker.attacked=false
		var destination:=-1
		for cell_id: int in state.grid.get_neighbors(attacker.cell_id):
			if not state.is_cell_blocked(cell_id,target.id): destination=cell_id; break
		target.cell_id=destination; target.hp=1; state.refresh_visibility()
		check(GameRules.new(state).try_attack(1,attacker.id,target.id).success,"Authoritative combat eliminates P%d in complete-match soak" % victim_id)
	check(state.winner_id==1 and state.alive_player_ids()==[1],"Four-player combat soak terminates with exactly one winner")

func test_independent_observations() -> void:
	var state:=GameState.new(PlanetGrid.new(3),_setup(["living_migration","living_migration","baumeister","baumeister"]))
	var signatures:={}
	for player_id: int in state.players:
		var snapshot:=ObservationCodec.encode(state,player_id,1)
		check(int(snapshot.recipient_player_id)==player_id and int(snapshot.recipient_team_id)==player_id,"Each FFA snapshot is assigned to its own player/team")
		check(snapshot.players.size()==4 and snapshot.players.all(func(row: Dictionary)->bool: return row.has("player_name") and row.has("player_color") and not row.has("resources")),"Only public identity/alive fields are shared globally")
		check(int(snapshot.own_player.player_id)==player_id and snapshot.own_player.has("resources"),"Only the recipient receives private economy and research")
		signatures[JSON.stringify(snapshot.visible_cells)]=true
	check(signatures.size()==4,"Four separated starts produce four independent visibility regions")

func test_lobby_capacity_ready_and_disconnect() -> void:
	var two_player_session:=NetworkSession.new(); root.add_child(two_player_session); await process_frame
	var port:=27500+int(Time.get_ticks_msec()%1000)
	var config:={"planet_size":MatchConfig.PlanetSize.SMALL,"world_seed":777,"world_population_preset":WorldPopulationConfig.STANDARD}
	check(two_player_session.host_game(port,"Host","living_migration",2,config)==OK and two_player_session.lobby_capacity==2,"Host can select a two-player lobby")
	two_player_session.shutdown("capacity test"); two_player_session.queue_free(); await process_frame
	var session:=NetworkSession.new(); root.add_child(session); await process_frame
	check(session.host_game(port+1,"Host","living_migration",3,config)==OK and session.lobby_capacity==3,"Host selects a synchronized three-player lobby capacity")
	session._register_player(8002,2,"Second","living_migration",false,false)
	session._register_player(8003,3,"Third","baumeister",false,false)
	check(session._next_player_id()==-1,"A full lobby exposes no replacement slot")
	session._update_player(1,"living_migration",true); session._update_player(2,"living_migration",true); session._update_player(3,"baumeister",true)
	check(session.can_host_start(),"All occupied connected slots ready-enable match start")
	session._update_player(2,"baumeister",true)
	check(not bool(session.lobby_players[2].ready) and not session.can_host_start(),"Changing faction authoritatively resets Ready")
	session._update_player(2,"baumeister",true)
	var changed:=config.duplicate(); changed.world_seed=778; session.set_host_lobby_configuration(changed)
	check(session.lobby_players.values().all(func(record: Dictionary)->bool: return not bool(record.ready)),"Host configuration changes reset all ready states")
	# Active disconnect is authoritatively eliminated so it cannot block a round.
	var state:=GameState.new(PlanetGrid.new(2),_setup(["living_migration","baumeister","living_migration"]))
	session.authoritative_state=state; session.authoritative_rules=GameRules.new(state)
	session.command_dispatcher=CommandDispatcher.new(state,session.authoritative_rules); session.command_dispatcher.register_peer(1,1); session.command_dispatcher.register_peer(8002,2); session.command_dispatcher.register_peer(8003,3)
	session.match_has_started=true; session.status=NetworkSession.Status.ACTIVE; session.authoritative_sync_revision=1
	session.peer_to_player.erase(8003); session.player_to_peer.erase(3)
	session._on_peer_disconnected(8002)
	check(session.status==NetworkSession.Status.ACTIVE and not paused and session.lobby_players.has(2) and state.players[2].eliminated,"Mid-match disconnect eliminates the player and authoritative progression continues")
	session.shutdown("done"); session.queue_free(); await process_frame
