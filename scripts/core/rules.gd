class_name GameRules
extends RefCounted
## Stable facade over coherent authoritative rule domains.

class Result extends RuleResult:
	pass

var state: GameState
var movement_rules: MovementRules
var combat_rules: CombatRules
var research_rules: ResearchRules
var recruitment_rules: RecruitmentRules
var site_rules: SiteRules
var living_migration_rules: LivingMigrationRules
var baumeister_rules: BaumeisterRules

func _init(game_state: GameState) -> void:
	state=game_state
	movement_rules=MovementRules.new(state)
	combat_rules=CombatRules.new(state)
	research_rules=ResearchRules.new(state)
	living_migration_rules=LivingMigrationRules.new(state,research_rules)
	movement_rules.capability_rules=living_migration_rules
	baumeister_rules=BaumeisterRules.new(state,research_rules)
	movement_rules.network_rules=baumeister_rules
	recruitment_rules=RecruitmentRules.new(state,research_rules)
	recruitment_rules.capability_rules=baumeister_rules
	site_rules=SiteRules.new(state,research_rules)

func _wrap(source: RuleResult) -> Result:
	var result:=Result.new(source.success,source.reason,source.path)
	result.damage=source.damage; result.target_hp=source.target_hp; result.killed=source.killed; result.winner_id=source.winner_id
	return result

func _commit(source: RuleResult) -> Result:
	if source.success: state.refresh_visibility()
	return _wrap(source)

func reachable(actor: int,unit_id: int) -> Array[int]:
	return movement_rules.reachable(actor,unit_id)

func path_to(actor: int,unit_id: int,destination: int) -> Array[int]:
	return movement_rules.path_to(actor,unit_id,destination)

func try_move(actor: int,unit_id: int,destination: int) -> Result:
	var result:=movement_rules.try_move(actor,unit_id,destination)
	if result.success: result.reason+=living_migration_rules.after_move(unit_id)
	return _commit(result)

func preview_attack(actor: int,attacker_id: int,target_id: int) -> Result:
	return _wrap(combat_rules.preview_attack(actor,attacker_id,target_id))

func attack_targets(actor: int,attacker_id: int) -> Array[int]:
	return combat_rules.attack_targets(actor,attacker_id)

func try_attack(actor: int,attacker_id: int,target_id: int) -> Result:
	return _commit(combat_rules.try_attack(actor,attacker_id,target_id))

func recruit_error(actor: int,headquarters_id: int,unit_id: String) -> String:
	return recruitment_rules.recruit_error(actor,headquarters_id,unit_id)

func recruit_destinations(actor: int,headquarters_id: int,unit_id: String) -> Array[int]:
	return recruitment_rules.recruit_destinations(actor,headquarters_id,unit_id)

func try_recruit(actor: int,headquarters_id: int,unit_id: String,destination: int) -> Result:
	return _commit(recruitment_rules.try_recruit(actor,headquarters_id,unit_id,destination))

func available_units(player_id: int) -> PackedStringArray:
	var result:=PackedStringArray()
	var player:=state.player_for_controller(player_id)
	if player==null: return result
	for unit_id: String in state.registry.faction(player.faction_id).unit_roster_ids:
		if research_rules.is_unit_unlocked(player_id,unit_id): result.append(unit_id)
	return result

func available_technologies(player_id: int) -> PackedStringArray:
	return research_rules.available_technologies(player_id)

func interactable_sites(controller_id: int) -> Array[WorldSiteState]:
	return site_rules.interactable_sites(controller_id)

func available_site_interactions(controller_id: int,site_id: int) -> Array[Dictionary]:
	return site_rules.available_interactions(controller_id,site_id)

func site_interaction_error(controller_id: int,site_id: int,interaction_id: String,unit_id: int=-1) -> String:
	return site_rules.interaction_error(controller_id,site_id,interaction_id,unit_id)

func try_site_interaction(controller_id: int,site_id: int,interaction_id: String,unit_id: int=-1) -> Result:
	return _commit(site_rules.try_interact(controller_id,site_id,interaction_id,unit_id))

func try_end_turn(actor: int) -> Result:
	var error:=RuleAuthority.actor_error(state,actor)
	if not error.is_empty(): return Result.new(false,error)
	living_migration_rules.end_turn(actor)
	baumeister_rules.end_turn(actor)
	state.advance_turn()
	living_migration_rules.start_turn(state.active_player)
	baumeister_rules.start_turn(state.active_player)
	return Result.new(true,"Player %d's turn." % state.active_player)

func finish_neutral_phase() -> Result:
	if not state.turn_state.neutral_phase: return Result.new(false,"Neutral activity is not in progress.")
	state.advance_turn()
	living_migration_rules.start_turn(state.active_player)
	baumeister_rules.start_turn(state.active_player)
	return Result.new(true,"Player %d's turn." % state.active_player)

func restart_match() -> void:
	state.reset_match()
	living_migration_rules.start_turn(state.active_player)
	baumeister_rules.start_turn(state.active_player)

func _start_turn() -> void:
	state.start_turn()

func start_research(player_id: int,technology_id: String) -> Result:
	return _wrap(research_rules.start_research(player_id,technology_id))

func add_research_progress(player_id: int,amount: int) -> Result:
	return _wrap(research_rules.add_research_progress(player_id,amount))

func choose_nursery(actor: int,spider_id: int,branch_id: String) -> Result: return _commit(living_migration_rules.choose_nursery(actor,spider_id,branch_id))
func start_internal_construction(actor: int,spider_id: int,building_id: String) -> Result: return _commit(living_migration_rules.start_internal_construction(actor,spider_id,building_id))
func queue_biological_production(actor: int,spider_id: int,recipe_id: String) -> Result: return _commit(living_migration_rules.queue_biological_production(actor,spider_id,recipe_id))
func deploy_biological(actor: int,spider_id: int,job_index: int,outcome_id: String,cell_id: int) -> Result: return _commit(living_migration_rules.deploy_biological(actor,spider_id,job_index,outcome_id,cell_id))
func transform_caterpillar(actor: int,unit_id: int,outcome_id: String) -> Result: return _commit(living_migration_rules.transform_caterpillar(actor,unit_id,outcome_id))
func start_spider_construction(actor: int,spider_id: int) -> Result: return _commit(living_migration_rules.start_spider_construction(actor,spider_id))
func deploy_spider(actor: int,spider_id: int,cell_id: int) -> Result: return _commit(living_migration_rules.deploy_spider(actor,spider_id,cell_id))
func deploy_mite(actor: int,spider_id: int,cell_id: int) -> Result: return _commit(living_migration_rules.deploy_mite(actor,spider_id,cell_id))
func try_build_road(actor: int,worker_id: int,path: Array) -> Result:
	var typed_path: Array[int]=[]
	for cell_id: Variant in path: typed_path.append(int(cell_id))
	return _commit(living_migration_rules.try_build_road(actor,worker_id,typed_path))
func try_consume_corpse(actor: int,ant_id: int,corpse_id: int) -> Result: return _commit(living_migration_rules.try_consume_corpse(actor,ant_id,corpse_id))
func select_disease(actor: int,mite_id: int,disease_id: String) -> Result: return _commit(living_migration_rules.select_disease(actor,mite_id,disease_id))
func build_district(actor: int,pillar_id: int,cell_id: int,district_id: String) -> Result: return _commit(baumeister_rules.build_district(actor,pillar_id,cell_id,district_id))
func start_bridge_extension(actor: int,engineer_id: int,pillar_id: int,cell_id: int) -> Result: return _commit(baumeister_rules.start_bridge_extension(actor,engineer_id,pillar_id,cell_id))
func toggle_deployment(actor: int,unit_id: int) -> Result: return _commit(baumeister_rules.toggle_deployment(actor,unit_id))
func heal_unit(actor: int,healer_id: int,target_id: int) -> Result: return _commit(baumeister_rules.heal_unit(actor,healer_id,target_id))
func repair_unit(actor: int,engineer_id: int,target_id: int) -> Result: return _commit(baumeister_rules.repair_unit(actor,engineer_id,target_id))
func repair_structure(actor: int,engineer_id: int,pillar_id: int) -> Result: return _commit(baumeister_rules.repair_structure(actor,engineer_id,pillar_id))
func damage_bridge(actor: int,attacker_id: int,bridge_id: int) -> Result: return _commit(baumeister_rules.damage_bridge(actor,attacker_id,bridge_id))
func repair_bridge(actor: int,engineer_id: int,bridge_id: int) -> Result: return _commit(baumeister_rules.repair_bridge(actor,engineer_id,bridge_id))
func designate_target(actor: int,commander_id: int,target_id: int) -> Result: return _commit(baumeister_rules.designate_target(actor,commander_id,target_id))
func district_support(actor: int,district_id: int,target_id: int) -> Result: return _commit(baumeister_rules.district_support(actor,district_id,target_id))
