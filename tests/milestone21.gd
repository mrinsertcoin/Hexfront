extends SceneTree

var failures:=0
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(message)

func make_state(setup: Dictionary={}) -> GameState:
	var config:={"faction_ids":["living_migration","baumeister"],"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_combat":true,"start_seed":77}
	config.merge(setup,true)
	return GameState.new(PlanetGrid.new(2),config)

func test_roads_larvae_squads() -> void:
	var state:=make_state(); var rules:=GameRules.new(state); var worker: GameState.Unit=state.units[2]
	var destination:=-1
	for id: int in rules.reachable(1,worker.id):
		if id not in state.living_migration.roads.get(1,{}): destination=id; break
	var result:=rules.try_move(1,worker.id,destination)
	check(result.success and result.path.all(func(id: int)->bool: return state.living_migration.roads[1].has(id)),"Accepted Worker path lays roads on every traversed cell")
	var untouched: int=state.grid.breadth_first(worker.cell_id).order.back()
	check(not state.living_migration.roads[1].has(untouched),"Untraversed cells do not receive roads")
	check(EntityView.visible_member_count(5,5,5)==5 and EntityView.visible_member_count(5,1,5)==1 and EntityView.visible_member_count(5,0,5)==0,"Squad member count follows ceil HP percentage")

	var water: int=state.grid.get_neighbors(worker.cell_id)[0]; state.water_cells[water]=true
	var dragon:=GameState.Unit.new(state.allocate_id(),1,"dragonfly",worker.cell_id,-1,state.registry); state.units[dragon.id]=dragon
	var laid:=rules.lay_larva(1,dragon.id,water)
	check(laid.success and state.living_migration.larvae.size()==1,"Dragonfly lays authoritative water larva")
	var larva: LarvaState=state.living_migration.larvae.values()[0]
	check(larva.maturation_round-larva.created_round==5,"Larva maturation is five rounds")
	var stable_outcome:=larva.successful_outcome
	var mirror:=make_state({"water_cells":[water]}); var mirror_rules:=GameRules.new(mirror)
	var mirror_dragon:=GameState.Unit.new(mirror.allocate_id(),1,"dragonfly",mirror.units[2].cell_id,-1,mirror.registry); mirror.units[mirror_dragon.id]=mirror_dragon
	mirror_rules.lay_larva(1,mirror_dragon.id,water)
	check((mirror.living_migration.larvae.values()[0] as LarvaState).successful_outcome==stable_outcome,"Larva outcome is stable for match/larva identity")
	larva.successful_outcome=true; state.round_number=larva.maturation_round; rules.living_migration_rules.process_round_start()
	check(state.unit_at(water)!=null and state.unit_at(water).definition_id=="dragonfly","Successful larva emerges as its source species")

func combat_pair() -> Array:
	var state:=make_state(); var rules:=GameRules.new(state)
	var a: GameState.Unit=state.units[2]; var b: GameState.Unit=state.units[4]
	b.cell_id=state.grid.get_neighbors(a.cell_id)[0]; state.refresh_visibility()
	return [state,rules,a,b]

func test_simultaneous_combat() -> void:
	var setup:=combat_pair(); var state: GameState=setup[0]; var rules: GameRules=setup[1]; var a: GameState.Unit=setup[2]; var b: GameState.Unit=setup[3]
	a.hp=b.attack_damage; b.hp=a.attack_damage
	check(rules.submit_combat_intent(1,a.id,"attack",b.id).success and rules.try_end_turn(1).success,"P1 queues attack during movement")
	check(rules.submit_combat_intent(2,b.id,"attack",a.id).success,"P2 queues attack during movement")
	check(rules.try_end_turn(2).success and not state.units.has(a.id) and not state.units.has(b.id),"Ending final movement phase automatically permits mutual kill")

	setup=combat_pair(); state=setup[0]; rules=setup[1]; a=setup[2]; b=setup[3]
	var before:=b.hp; rules.submit_combat_intent(1,a.id,"attack",b.id); rules.try_end_turn(1); rules.submit_combat_intent(2,b.id,"dodge")
	rules.try_end_turn(2)
	check(b.hp==before-maxi(0,a.attack_damage-state.registry.combat_option("dodge").damage_reduction),"Dodge applies data-defined reduction")

	setup=combat_pair(); state=setup[0]; rules=setup[1]; a=setup[2]; b=setup[3]
	var a_before:=a.hp; var b_before:=b.hp; rules.submit_combat_intent(1,a.id,"attack",b.id); rules.try_end_turn(1); rules.submit_combat_intent(2,b.id,"counter")
	rules.try_end_turn(2)
	check(b.hp==b_before-maxi(0,a.attack_damage-2) and a.hp==a_before-2 and b.counter_cooldown_remaining==2,"Counter blocks, retaliates, and starts cooldown")

func _init() -> void:
	test_roads_larvae_squads(); test_simultaneous_combat()
	print("Milestone 21 checks: %d; failures=%d" % [checks,failures])
	quit(1 if failures else 0)
