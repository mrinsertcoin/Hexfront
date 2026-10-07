extends SceneTree

var failures:=0
var checks:=0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<30: push_error(message)

func generated(seed: int=90817,preset: String=WorldPopulationConfig.STANDARD) -> Dictionary:
	var grid:=PlanetGrid.new(2)
	var recipe:=PlanetGenerationConfig.new(); recipe.world_seed=seed; recipe.region_count=8; recipe.minimum_region_size=2
	var world:=GeneratedPlanet.generate(grid,recipe,false)
	var config:=WorldPopulationConfig.from_preset(preset); config.start_cells=[0,grid.breadth_first(0).order[-1]]
	return {"world":world,"config":config,"result":WorldPopulationGenerator.generate(world,ContentRegistry.default(),config)}

func test_catalog_and_generation() -> void:
	var registry:=ContentRegistry.default()
	check(registry.validate().is_empty(),"Production content registry validates")
	check(registry.trade_recipes.size()>=3 and registry.world_sites.size()>=4,"Typed site and trade catalog is loaded")
	check(registry.neutral_groups.size()>=3 and registry.unit("stone_guardian")!=null,"Reusable neutral content is loaded")
	var off:=generated(90817,WorldPopulationConfig.OFF)
	check(off.result.site_records.is_empty() and off.result.neutral_group_records.is_empty(),"Off preset produces no population")
	var standard:=generated()
	var repeated:=generated()
	check(standard.result.fingerprint==repeated.result.fingerprint,"World population is deterministic")
	check(standard.result.site_records==repeated.result.site_records and standard.result.neutral_group_records==repeated.result.neutral_group_records,"Deterministic records are byte-equivalent")
	check(not standard.result.site_records.is_empty() and not standard.result.neutral_group_records.is_empty(),"Standard preset populates sites and neutrals")
	check(standard.result.world_fingerprint==standard.world.generation_fingerprint and standard.result.config_fingerprint.length()==64,"Population has independent world/config fingerprints")
	var start_cells: Array[int]=standard.config.start_cells
	for record: Dictionary in standard.result.site_records:
		for start: int in start_cells: check(standard.world.grid_reference.distance(record.cell_id,start)>=standard.config.safe_start_distance,"Site respects safe starting area")
	for record: Dictionary in standard.result.neutral_group_records:
		if record.site_cell_id<0:
			for start: int in start_cells: check(standard.world.grid_reference.distance(record.cell_id,start)>=standard.config.neutral_start_distance,"Wildlife respects safe starting area")
	var changed_config:=standard.config.duplicate(true) as WorldPopulationConfig
	changed_config.start_cells=standard.config.start_cells.duplicate(); changed_config.neutral_groups_per_1000_cells+=8.0
	var changed:=WorldPopulationGenerator.generate(standard.world,registry,changed_config)
	check(changed.site_records==standard.result.site_records,"Neutral density cannot perturb semantic site streams")
	check(changed.fingerprint!=standard.result.fingerprint,"Population config participates in fingerprint")

func test_site_rules() -> void:
	var state:=GameState.new(PlanetGrid.new(1),{"faction_ids":["living_migration","baumeister"],"controller_kinds":[ControllerState.HUMAN,ControllerState.HUMAN],"simultaneous_combat":false})
	var rules:=GameRules.new(state)
	var unit: GameState.Unit=state.units[1]
	var trade:=state.add_world_site("trade_post",unit.cell_id)
	state.refresh_visibility()
	var interactions:=rules.available_site_interactions(1,trade.id)
	check(interactions.size()==1 and interactions[0].id=="food_for_silk","Trade offers are faction-compatible")
	var food_before:=state.players[1].resource_amount("food"); var silk_before:=state.players[1].resource_amount("silk")
	var traded:=rules.try_site_interaction(1,trade.id,"food_for_silk",unit.id)
	check(traded.success and state.players[1].resource_amount("food")==food_before-4 and state.players[1].resource_amount("silk")==silk_before+2,"Trade applies its fixed exchange exactly once")
	check(not rules.try_site_interaction(1,trade.id,"food_for_silk",unit.id).success,"A unit cannot repeat a site action in one turn")
	state.turn_state.index=1
	var baumeister_unit: GameState.Unit=state.units[3]; var baumeister_old_cell:=baumeister_unit.cell_id
	baumeister_unit.cell_id=trade.cell_id; state.refresh_visibility()
	check(rules.available_site_interactions(2,trade.id).size()==2,"Baumeister sees only its compatible recipes")
	baumeister_unit.cell_id=baumeister_old_cell; state.refresh_visibility()
	state.turn_state.index=0; unit.attacked=false; unit.moved=false
	var source:=state.add_world_site("food_source",unit.cell_id)
	state.refresh_visibility()
	var gathered:=rules.try_site_interaction(1,source.id,"gather",unit.id)
	check(gathered.success and source.runtime_state.remaining_charges==1,"Resource site consumes one finite charge")
	unit.attacked=false; unit.moved=false
	check(rules.try_site_interaction(1,source.id,"gather",unit.id).success and source.runtime_state.exhausted,"Resource site exhausts at zero charges")
	unit.attacked=false; unit.moved=false
	check(not rules.try_site_interaction(1,source.id,"gather",unit.id).success,"Exhausted sites reject harvesting")
	state._process_world_site_regeneration(); state._process_world_site_regeneration()
	check(not source.runtime_state.exhausted and source.runtime_state.remaining_charges==2,"Renewable site regenerates on its authored schedule")
	var ruin:=state.add_world_site("ancient_ruin",unit.cell_id)
	state.refresh_visibility()
	unit.attacked=false; unit.moved=false
	check(rules.try_site_interaction(1,ruin.id,"explore",unit.id).success and ruin.runtime_state.explored,"Ruin exploration records one global result")
	unit.attacked=false; unit.moved=false
	check(not rules.try_site_interaction(1,ruin.id,"explore",unit.id).success,"Explored ruin cannot reroll its reward")

func test_neutral_state_and_phase() -> void:
	var state:=GameState.new(PlanetGrid.new(1),{"simultaneous_combat":false})
	var target: GameState.Unit=state.units[1]
	var cell:=state.grid.get_neighbors(target.cell_id)[0]
	while state.is_cell_blocked(cell): cell=state.grid.get_neighbors(target.cell_id)[state.grid.get_neighbors(target.cell_id).find(cell)+1]
	var result:=WorldPopulationResult.new(); result.generation_version=WorldPopulationConfig.VERSION; result.world_fingerprint="test"; result.config_fingerprint="test"
	result.neutral_group_records=[{"definition_id":"roaming_predators","cell_id":cell,"controller_id":51,"relationship_policy":"hostile",
		"awareness_range":4,"leash_distance":4,"site_cell_id":-1,"unit_records":[{"definition_id":"wild_predator","cell_id":cell}]}]
	result.refresh_fingerprint(); state.apply_population(result)
	var neutral: GameState.Unit
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==51: neutral=unit
	check(neutral!=null and neutral.neutral_group_id=="roaming_predators","Population spawns normal units with home/group metadata")
	check(state.relationships.is_hostile(1,51) and not state.players.has(51),"Neutral controller relationships are central without fake players")
	var rules:=GameRules.new(state)
	check(rules.try_end_turn(1).success and rules.try_end_turn(2).success,"Both players can complete the round")
	check(state.turn_state.neutral_phase and state.round_number==1,"Explicit neutral phase occurs before the next round")
	var actions:=NeutralAI.new().choose_actions(state,51)
	check(actions.size()<=1 and not actions.is_empty(),"Neutral AI emits a bounded deterministic action")
	for action: Dictionary in actions:
		if action.type=="attack": rules.try_attack(51,action.attacker,action.target)
		elif action.type=="move": rules.try_move(51,action.unit,action.dest)
	check(rules.finish_neutral_phase().success and state.active_player==1 and state.round_number==2,"Neutral phase finishes into the next player round")

func _run() -> void:
	test_catalog_and_generation()
	test_site_rules()
	test_neutral_state_and_phase()
	print("World population checks complete; failures=",failures," checks=",checks)
	quit(1 if failures else 0)
