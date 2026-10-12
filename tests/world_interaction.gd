extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<25: push_error(message)

func test_relationships_and_neutrals() -> void:
	var grid:=PlanetGrid.new(1)
	var state:=GameState.new(grid,{"simultaneous_combat":false})
	var rules:=GameRules.new(state)
	check(state.relationships.between(1,1)==RelationshipState.Kind.SELF,"Same controller relationship is SELF")
	check(state.relationships.between(1,2)==RelationshipState.Kind.HOSTILE,"Prototype players are hostile")
	check(state.relationships.between(1,0)==RelationshipState.Kind.NEUTRAL,"World controller is neutral")
	state.controllers[50]=ControllerState.new(50,ControllerState.NEUTRAL_AI,"")
	var attacker: GameState.Unit=state.units[1]
	var neutral_cell:=grid.get_neighbors(attacker.cell_id)[0]
	if state.is_cell_blocked(neutral_cell): neutral_cell=grid.get_neighbors(attacker.cell_id)[1]
	var neutral:=GameState.Unit.new(500,50,"prototype_infantry",neutral_cell,-1,state.registry)
	state.units[neutral.id]=neutral
	state.refresh_visibility()
	check(rules.preview_attack(1,attacker.id,neutral.id).success,"A player may deliberately target a visible non-allied neutral unit")
	var neutral_hp:=neutral.hp
	check(rules.try_attack(1,attacker.id,neutral.id).success and neutral.hp<neutral_hp and state.relationships.between(1,50)==RelationshipState.Kind.HOSTILE,"Attacking a neutral unit deals damage and establishes hostility")
	check(NeutralAI.new().choose_actions(state,50).is_empty(),"Neutral AI seam defaults to no actions")
	check(state.turn_state.order==[1,2],"Neutral controllers do not enter the player turn order")
	var first_serial:=state.turn_state.serial
	rules.try_end_turn(1)
	check(state.active_player==2 and state.turn_state.serial==first_serial+1,"Turn sequence advances through its ordered abstraction")
	rules.try_end_turn(2)
	check(state.active_player==1 and state.round_number==2,"Default P1 to P2 round behavior is preserved")

func test_sites_and_occupancy() -> void:
	var registry:=ContentRegistry.new()
	var blocking:=WorldSiteDefinition.new()
	blocking.id="sealed_ruin"; blocking.display_name="Sealed Ruin"; blocking.blocks_movement=true
	registry.add_definition(blocking)
	var state:=GameState.new(PlanetGrid.new(1),{"simultaneous_combat":false},registry)
	var free_cell:=state.grid.get_neighbors(state.units[1].cell_id)[0]
	while state.is_cell_blocked(free_cell): free_cell=state.grid.get_neighbors(state.units[1].cell_id)[1]
	var trade:=state.add_world_site("trade_post",free_cell)
	state.refresh_visibility()
	check(not state.is_cell_blocked(free_cell),"Nonblocking trade post shares a traversable cell")
	check(GameRules.new(state).interactable_sites(1)==[trade],"Interactable sites are exposed through the rules facade")
	var blocked_cell:=free_cell+1
	while state.is_cell_blocked(blocked_cell): blocked_cell+=1
	state.add_world_site("sealed_ruin",blocked_cell)
	check(state.is_cell_blocked(blocked_cell),"Blocking site participates in central occupancy")
	check(state.site_at(blocked_cell).definition_id=="sealed_ruin","World-site state stores a stable definition ID")

func test_population() -> void:
	var registry:=ContentRegistry.new()
	var recipe:=PlanetGenerationConfig.new(); recipe.world_seed=76123; recipe.region_count=4; recipe.minimum_region_size=2
	var world:=GeneratedPlanet.generate(PlanetGrid.new(1),recipe,false)
	var disabled:=WorldPopulationConfig.new()
	var empty:=WorldPopulationGenerator.generate(world,registry,disabled)
	check(empty.site_records.is_empty(),"World population is disabled by default")
	var config:=WorldPopulationConfig.new()
	config.enabled=true
	config.site_definition_ids=PackedStringArray(["trade_post"])
	config.site_counts={"trade_post":3}
	var first:=WorldPopulationGenerator.generate(world,registry,config)
	var second:=WorldPopulationGenerator.generate(world,registry,config)
	check(first.fingerprint==second.fingerprint and first.site_records==second.site_records,"World population is deterministic for a seed and config")
	check(first.site_records.size()==3,"Authored world-site count is produced")
	for record: Dictionary in first.site_records:
		check(record.has("biome_weights") and record.has("height") and record.has("region_id"),"Population record retains future placement inputs")
	var changed_recipe:=recipe.duplicate(true); changed_recipe.world_seed+=1
	var changed_world:=GeneratedPlanet.generate(PlanetGrid.new(1),changed_recipe,false)
	var changed:=WorldPopulationGenerator.generate(changed_world,registry,config)
	check(changed.fingerprint!=first.fingerprint,"World population fingerprint changes with world seed")
	var state:=GameState.new(world.grid_reference,{"simultaneous_combat":false})
	state.apply_population(first)
	check(state.world_sites.size()==3,"Logical population result applies to GameState")

func _run() -> void:
	test_relationships_and_neutrals()
	test_sites_and_occupancy()
	test_population()
	print("World interaction checks: ",checks,"; failures=",failures)
	quit(1 if failures else 0)
