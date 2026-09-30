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

func contains_error(errors: PackedStringArray,needle: String) -> bool:
	for error: String in errors:
		if needle in error: return true
	return false

func test_registry() -> void:
	var first:=ContentRegistry.new()
	var second:=ContentRegistry.new()
	check(first.validate().is_empty(),"Production content validates")
	check(first.fingerprint==second.fingerprint,"Content fingerprint is deterministic")
	check(first.loaded_paths==second.loaded_paths,"Content discovery order is deterministic")
	check(first.loaded_paths==PackedStringArray(first.loaded_paths.duplicate()),"Loaded paths remain stable")
	check(first.resources.has("materials"),"Materials resource resolves")
	check(first.units.has("prototype_infantry") and first.units.has("prototype_scout") and first.units.has("prototype_gunner") and first.structures.has("prototype_headquarters"),"Prototype roster resolves")
	check(first.world_sites.has("trade_post"),"Trade-post definition resolves")
	check(first.playable_factions().map(func(f: FactionDefinition)->String: return f.id)==["baumeister","blue","living_migration","red"],"Playable factions are registry-driven and sorted")
	var infantry:=first.unit("prototype_infantry")
	check(infantry.max_hp==10 and infantry.movement==2 and infantry.attack_damage==3 and infantry.costs.materials==4,"Prototype Infantry balance is preserved")
	var scout:=first.unit("prototype_scout")
	check(scout.max_hp==6 and scout.movement==3 and scout.costs.materials==3,"Prototype Scout balance is preserved")
	var gunner:=first.unit("prototype_gunner")
	check(gunner.max_hp==7 and gunner.attack_range==2 and gunner.costs.materials==5,"Prototype Gunner balance is preserved")
	var before:=first.fingerprint
	var presentation_only: UnitDefinition=infantry.duplicate(true)
	presentation_only.display_name="Presentation Only"
	first.units[presentation_only.id]=presentation_only
	first._refresh_fingerprint()
	check(first.fingerprint==before,"Presentation text is excluded from gameplay fingerprint")

func test_validation() -> void:
	check(ContentRegistry.valid_id("valid_snake_2") and not ContentRegistry.valid_id("Bad-ID"),"Stable ID format is enforced")
	var duplicate_registry:=ContentRegistry.new(false)
	var resource:=ResourceDefinition.new(); resource.id="ore"; resource.display_name="Ore"
	duplicate_registry.add_definition(resource,"first")
	duplicate_registry.add_definition(resource.duplicate(),"second")
	check(contains_error(duplicate_registry.validate(),"Duplicate content ID ore"),"Duplicate IDs are rejected")
	var missing_registry:=ContentRegistry.new(false)
	var unit:=UnitDefinition.new(); unit.id="bad_unit"; unit.display_name="Bad Unit"; unit.max_hp=1; unit.costs={"missing_resource":1}
	missing_registry.add_definition(unit)
	check(contains_error(missing_registry.validate(),"missing resource"),"Missing references are reported")
	var cycle_registry:=ContentRegistry.new(false)
	var a:=TechnologyDefinition.new(); a.id="cycle_a"; a.display_name="A"; a.prerequisite_ids=["cycle_b"]
	var b:=TechnologyDefinition.new(); b.id="cycle_b"; b.display_name="B"; b.prerequisite_ids=["cycle_a"]
	cycle_registry.add_definition(a); cycle_registry.add_definition(b)
	check(cycle_registry.technology_order().is_empty(),"Cyclic technology graph has no false ordering")
	check(contains_error(cycle_registry.validate(),"contain a cycle"),"Technology cycles are rejected")

func test_factions_players_and_research() -> void:
	var registry:=ContentRegistry.new(true,true)
	check(registry.validate().is_empty(),"Development examples also validate")
	var blue:=registry.faction("blue")
	check(blue.starting_resources.materials==8 and blue.turn_resource_income.materials==3,"Faction economy values preserve the prototype")
	check(blue.unit_roster_ids==PackedStringArray(["prototype_infantry","prototype_scout","prototype_gunner"]),"Faction roster preserves the prototype")
	var state:=GameState.new(PlanetGrid.new(1),{},registry)
	check(state.players[1].faction_id=="blue" and state.players[2].faction_id=="red","Players store stable faction IDs")
	check(state.players[1].resource_amount("materials")==11,"First-turn income preserves 8 + 3 behavior")
	check(state.players[2].resource_amount("materials")==8,"Inactive player retains starting resources")
	check(state.units[1].definition_id=="prototype_infantry" and state.units[2].definition_id=="prototype_scout" and state.units[5].definition_id=="prototype_gunner","Starting army resolves to stable definition IDs")
	var original_snapshot:=TestState.snapshot(state)
	state.players[1].resources.materials=0
	state.reset_match()
	check(state.players[1].resource_amount("materials")==11 and TestState.snapshot(state)==original_snapshot,"Restart restores faction resources and deterministic starting state")
	var rules:=GameRules.new(state)
	check(rules.available_technologies(1).is_empty(),"Faction with no technology IDs exposes no research")
	var foundation:=TechnologyDefinition.new()
	foundation.id="prototype_foundation"; foundation.display_name="Prototype Foundation"; foundation.research_cost=2
	registry.add_definition(foundation)
	var tech: TechnologyDefinition=registry.technology("prototype_logistics").duplicate(true)
	tech.prerequisite_ids=PackedStringArray([foundation.id])
	tech.unlock_unit_ids=PackedStringArray(["prototype_gunner"])
	registry.technologies[tech.id]=tech
	var custom_blue: FactionDefinition=blue.duplicate(true)
	custom_blue.technology_ids=PackedStringArray([tech.id,foundation.id])
	registry.factions["blue"]=custom_blue
	check(rules.available_technologies(1)==PackedStringArray([foundation.id]),"Only satisfied technology roots are available")
	check(rules.start_research(1,foundation.id).success and rules.add_research_progress(1,2).success,"Prerequisite research completes")
	check(rules.available_technologies(1)==PackedStringArray([tech.id]),"Completing a prerequisite exposes its dependent technology")
	check(not rules.research_rules.is_unit_unlocked(1,"prototype_gunner"),"Technology-gated roster content starts locked")
	check(rules.start_research(1,tech.id).success,"Research can start")
	check(state.players[1].research.accumulated_progress==0,"Research starts without an implicit turn grant")
	check(rules.add_research_progress(1,4).success and not state.players[1].research.is_completed(tech.id),"Partial research progress persists")
	check(rules.add_research_progress(1,1).success and state.players[1].research.is_completed(tech.id),"Research completes at its authored cost")
	check(rules.research_rules.is_unit_unlocked(1,"prototype_gunner"),"Completed research unlocks roster content")

func _run() -> void:
	test_registry()
	test_validation()
	test_factions_players_and_research()
	print("Content foundation checks: ",checks,"; failures=",failures)
	quit(1 if failures else 0)
