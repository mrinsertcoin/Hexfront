extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<30: push_error(message)

func cell_at_distance(grid: PlanetGrid,start: int,distance: int) -> int:
	var search:=grid.breadth_first(start)
	for id: int in search.order:
		if int(search.costs[id])==distance: return id
	return -1

func empty_state(grid: PlanetGrid=PlanetGrid.new(2),registry: ContentRegistry=null,setup: Dictionary={}) -> GameState:
	var state:=GameState.new(grid,setup,registry)
	state.units.clear(); state.structures.clear(); state.world_sites.clear(); state.visibility_system.reset(); state.refresh_visibility()
	return state

func add_unit(state: GameState,id: int,controller: int,definition: String,cell: int) -> GameState.Unit:
	var unit:=GameState.Unit.new(id,controller,definition,cell,-1,state.registry); state.units[id]=unit; return unit

func test_cell_states_and_team_sharing() -> void:
	for level in [1,2,4]:
		var grid:=PlanetGrid.new(level)
		var setup:={"faction_ids":["blue","red","blue"],"controller_kinds":[ControllerState.HUMAN,ControllerState.PLAYER_AI,ControllerState.HUMAN],"team_ids":[7,9,7]}
		var state:=empty_state(grid,null,setup)
		var source:=add_unit(state,10,1,"prototype_infantry",0)
		var allied_source:=add_unit(state,11,3,"prototype_scout",cell_at_distance(grid,0,5))
		state.refresh_visibility()
		var observation:=state.visibility_system.observation_for_controller(1)
		check(observation.team_id==7 and state.relationships.between(1,3)==RelationshipState.Kind.ALLIED,"Teams are explicit and independent of faction identity")
		check(observation.is_visible(source.cell_id) and observation.is_visible(allied_source.cell_id),"Allied controllers share both vision sources")
		for id: int in grid.get_cells_within_distance(source.cell_id,state.registry.unit(source.definition_id).vision_range):
			check(observation.is_visible(id),"Graph-range vision covers pentagons, poles, and configured topology sizes")
		var remote:=cell_at_distance(grid,source.cell_id,5)
		if remote>=0 and not observation.is_visible(remote): check(not observation.is_explored(remote),"Cells begin unexplored outside team vision")
		var old_cell:=source.cell_id; source.cell_id=cell_at_distance(grid,old_cell,4); state.refresh_visibility()
		var moved:=state.visibility_system.observation_for_controller(1)
		check(moved.is_explored(old_cell),"Previously visible cells remain explored after a source moves")
		source.cell_id=old_cell; state.refresh_visibility()
		check(state.visibility_system.observation_for_controller(1).is_visible(old_cell),"Explored cells become visible again when a source returns")
		state.units.erase(source.id); state.refresh_visibility()
		check(state.visibility_system.observation_for_controller(1).is_explored(old_cell),"Removing a vision source removes current vision but preserves exploration")

func test_information_boundary_and_contacts() -> void:
	var state:=empty_state()
	var source:=add_unit(state,10,1,"prototype_infantry",0)
	var seen_cell:=cell_at_distance(state.grid,0,2)
	var enemy:=add_unit(state,20,2,"prototype_infantry",seen_cell)
	var hidden_cell:=cell_at_distance(state.grid,0,7)
	var site:=state.add_world_site("trade_post",hidden_cell)
	state.refresh_visibility()
	var observed:=state.visibility_system.observation_for_controller(1)
	check(observed.visible_entities.has(enemy.id) and not observed.observed_sites.has(site.id),"Observation exposes current enemies but omits hidden sites")
	check(not observed.visible_entities[enemy.id].has("resources") and not observed.visible_entities[enemy.id].has("production") and not observed.visible_entities[enemy.id].has("movement_destination"),
		"Entity observations omit private resources, production, and movement plans")
	source.cell_id=cell_at_distance(state.grid,seen_cell,7); state.refresh_visibility()
	var contact_view:=state.visibility_system.observation_for_controller(1)
	check(not contact_view.visible_entities.has(enemy.id) and contact_view.known_contacts.has(enemy.id),"A lost enemy becomes a last-known contact")
	var remembered: Dictionary=contact_view.known_contacts[enemy.id]
	var hidden_destination:=-1
	for id: int in range(state.grid.get_cell_count()):
		if not contact_view.is_visible(id) and id!=seen_cell: hidden_destination=id; break
	enemy.hp=1; enemy.cell_id=hidden_destination; state.refresh_visibility()
	var detached:=state.visibility_system.observation_for_controller(1)
	check(detached.known_contacts[enemy.id].observed_snapshot.hp==remembered.observed_snapshot.hp and detached.known_contacts[enemy.id].last_known_cell_id==seen_cell,
		"Hidden movement and damage cannot mutate detached contact intelligence")
	state.remove_unit(enemy.id,false); state.refresh_visibility()
	check(state.visibility_system.observation_for_controller(1).known_contacts.has(enemy.id),"A hidden death does not update the opposing team")
	source.cell_id=seen_cell; state.refresh_visibility()
	check(not state.visibility_system.observation_for_controller(1).known_contacts.has(enemy.id),"Observing an empty last-known cell invalidates the contact")
	# Returned snapshots never retain live state references.
	observed.visible_entities[10].hp=-999
	check(state.units[10].hp>0,"Mutating an observation snapshot cannot mutate GameState")
	var rediscovery:=empty_state()
	var observer:=add_unit(rediscovery,30,1,"prototype_infantry",0)
	var rediscovered_enemy:=add_unit(rediscovery,31,2,"prototype_infantry",cell_at_distance(rediscovery.grid,0,2)); rediscovery.refresh_visibility()
	observer.cell_id=cell_at_distance(rediscovery.grid,0,8); rediscovery.refresh_visibility()
	check(rediscovery.visibility_system.observation_for_controller(1).known_contacts.has(rediscovered_enemy.id),"Rediscovery fixture retains a historical contact")
	rediscovered_enemy.cell_id=cell_at_distance(rediscovery.grid,rediscovered_enemy.cell_id,3)
	observer.cell_id=cell_at_distance(rediscovery.grid,rediscovered_enemy.cell_id,1); rediscovery.refresh_visibility()
	var rediscovered:=rediscovery.visibility_system.observation_for_controller(1)
	check(rediscovered.visible_entities[rediscovered_enemy.id].cell_id==rediscovered_enemy.cell_id and not rediscovered.known_contacts.has(rediscovered_enemy.id),"Rediscovery replaces historical position with a fresh current snapshot")

func test_detection_tracking_and_reveal() -> void:
	var registry:=ContentRegistry.new(true,true)
	var state:=empty_state(PlanetGrid.new(2),registry)
	add_unit(state,10,1,"prototype_infantry",0)
	var concealed_cell:=cell_at_distance(state.grid,0,2)
	var concealed:=add_unit(state,20,2,"concealed_test_unit",concealed_cell)
	state.refresh_visibility()
	check(not state.visibility_system.observation_for_controller(1).visible_entities.has(concealed.id),"Concealed units inside vision remain hidden outside detection")
	state.units.erase(10); add_unit(state,11,1,"scout_trike",0); state.refresh_visibility()
	check(state.visibility_system.observation_for_controller(1).visible_entities.has(concealed.id),"Recon detection reveals concealed units")

	var tracking_state:=empty_state(PlanetGrid.new(2),registry)
	add_unit(tracking_state,30,1,"prototype_infantry",0)
	var tracked:=add_unit(tracking_state,31,2,"prototype_infantry",cell_at_distance(tracking_state.grid,0,7))
	tracked.active_disease=DiseaseState.new("tracking",2,1)
	tracking_state.refresh_visibility()
	var tracking:=tracking_state.visibility_system.observation_for_controller(1)
	check(tracking.visible_entities.has(tracked.id),"Tracking forces current target observation")
	for id: int in tracking_state.grid.get_cells_within_distance(tracked.cell_id,1): check(tracking.is_visible(id),"Tracking reveals the target neighborhood")
	tracked.cell_id=cell_at_distance(tracking_state.grid,tracked.cell_id,3); tracking_state.refresh_visibility()
	check(tracking_state.visibility_system.observation_for_controller(1).visible_entities.has(tracked.id),"Tracking follows target movement")
	tracked.active_disease=null; tracking_state.refresh_visibility()
	check(not tracking_state.visibility_system.observation_for_controller(1).visible_entities.has(tracked.id),"Tracking reveal expires with its disease state")

	var reveal_state:=empty_state(PlanetGrid.new(2),registry)
	var victim:=add_unit(reveal_state,40,1,"prototype_infantry",0)
	var attacker:=add_unit(reveal_state,41,2,"long_range_tank",cell_at_distance(reveal_state.grid,0,4)); attacker.deployed=true
	add_unit(reveal_state,42,2,"prototype_scout",cell_at_distance(reveal_state.grid,0,2))
	reveal_state.refresh_visibility()
	check(not reveal_state.visibility_system.observation_for_controller(1).visible_entities.has(attacker.id),"A distant attacker starts hidden")
	reveal_state.active_player=2
	var result:=GameRules.new(reveal_state).try_attack(2,attacker.id,victim.id)
	check(result.success and reveal_state.visibility_system.observation_for_controller(1).visible_entities.has(attacker.id),"Attacking reveals the attacker to the target team")

	var allied_setup:={"faction_ids":["blue","red","baumeister"],"controller_kinds":[ControllerState.HUMAN,ControllerState.PLAYER_AI,ControllerState.HUMAN],"team_ids":[1,2,1]}
	var allied_state:=empty_state(PlanetGrid.new(2),registry,allied_setup)
	var artillery:=add_unit(allied_state,60,1,"long_range_tank",0); artillery.deployed=true
	var allied_target:=add_unit(allied_state,61,2,"prototype_infantry",cell_at_distance(allied_state.grid,0,4))
	add_unit(allied_state,62,3,"scout_trike",cell_at_distance(allied_state.grid,allied_target.cell_id,2))
	allied_state.refresh_visibility()
	check(GameRules.new(allied_state).preview_attack(1,artillery.id,allied_target.id).success,"Allied reconnaissance enables legitimate long-range artillery targeting")

func test_rules_sites_and_ai_security() -> void:
	var state:=empty_state()
	var mover:=GameState.Unit.new(10,1,"prototype_scout",0,5,state.registry); state.units[mover.id]=mover
	var destination:=cell_at_distance(state.grid,0,4)
	add_unit(state,20,2,"prototype_infantry",destination)
	state.refresh_visibility()
	var rules:=GameRules.new(state)
	check(not state.visibility_system.observation_for_controller(1).is_explored(destination),"Movement into unexplored territory is allowed by knowledge rules")
	check(not rules.path_to(1,mover.id,destination).is_empty(),"Path preview does not reveal a hidden blocker")
	var blocked:=rules.try_move(1,mover.id,destination)
	check(not blocked.success and "obstruction" in blocked.reason.to_lower(),"Authoritative movement rejects a hidden obstruction with a generic result")

	var site_cell:=cell_at_distance(state.grid,0,7)
	var site:=state.add_world_site("trade_post",site_cell); state.refresh_visibility()
	check(site not in rules.interactable_sites(1),"Undiscovered sites are absent from interaction queries")
	mover.cell_id=cell_at_distance(state.grid,site_cell,1); state.refresh_visibility()
	check(site in rules.interactable_sites(1),"Visible sites become discovered and interactable")
	mover.cell_id=0; state.refresh_visibility(); site.runtime_state.remaining_charges=1
	var memory:=state.visibility_system.observation_for_controller(1).observed_sites[site.id]
	check(memory.runtime_state.remaining_charges!=site.runtime_state.remaining_charges,"Hidden site runtime changes do not update remembered intelligence")
	check(not rules.try_site_interaction(1,site.id,"trade_food_for_materials",mover.id).success,"Remembered but currently hidden sites cannot be used")

	state.controllers[70]=ControllerState.new(70,ControllerState.NEUTRAL_AI,"")
	state.relationships.set_relationship(1,70,RelationshipState.Kind.NEUTRAL)
	var neutral:=add_unit(state,70,70,"wild_grazer",cell_at_distance(state.grid,0,8)); neutral.neutral_home_cell=neutral.cell_id; neutral.neutral_awareness_range=2; neutral.neutral_leash_distance=2
	state.refresh_visibility()
	check(not state.visibility_system.observation_for_controller(1).visible_entities.has(neutral.id),"Deterministically spawned neutral groups remain hidden until observed")
	mover.cell_id=cell_at_distance(state.grid,neutral.cell_id,2); state.refresh_visibility()
	check(state.visibility_system.observation_for_controller(1).visible_entities.has(neutral.id),"Neutral creatures use the common discovery path")

	var ai_state:=empty_state()
	add_unit(ai_state,50,1,"prototype_scout",0)
	var hidden:=add_unit(ai_state,51,2,"prototype_infantry",cell_at_distance(ai_state.grid,0,8))
	ai_state.refresh_visibility(); var ai:=SimpleAI.new(); var ai_rules:=GameRules.new(ai_state)
	var first:=ai.choose_action(ai_state,ai_rules,1)
	hidden.cell_id=cell_at_distance(ai_state.grid,0,10); hidden.hp=1; ai_state.refresh_visibility()
	var second:=SimpleAI.new().choose_action(ai_state,ai_rules,1)
	check(first==second and first.get("type") in ["move","end"],"Player AI decisions are invariant under hidden enemy position and HP changes")

func test_refresh_performance() -> void:
	for level in [4,5]:
		var state:=empty_state(PlanetGrid.new(level))
		for index in range(48):
			add_unit(state,1000+index,1 if index%2==0 else 2,"prototype_scout" if index%5==0 else "prototype_infantry",(index*211)%state.grid.get_cell_count())
		var started:=Time.get_ticks_usec(); state.refresh_visibility(); var elapsed:=(Time.get_ticks_usec()-started)/1000.0
		check(elapsed<2000.0,"Visibility refresh stays practical on %s topology (%.1f ms)" % ["Small" if level==4 else "Medium",elapsed])
		check(state.visibility_system.observation_for_controller(1).visible_cells.size()==state.grid.get_cell_count(),"Visibility masks match topology size")
		print("Visibility benchmark level=",level," cells=",state.grid.get_cell_count()," refresh_ms=",elapsed)

func _run() -> void:
	test_cell_states_and_team_sharing()
	test_information_boundary_and_contacts()
	test_detection_tracking_and_reveal()
	test_rules_sites_and_ai_security()
	test_refresh_performance()
	print("Visibility checks complete: ",checks,"; failures=",failures)
	quit(1 if failures else 0)
