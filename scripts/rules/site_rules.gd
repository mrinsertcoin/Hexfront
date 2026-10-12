class_name SiteRules
extends RefCounted
## Authoritative, generic world-site interaction domain.

const TRADE:="trade"
const GATHER:="gather"
const EXPLORE:="explore"
const CLAIM_LOOT:="claim_loot"

var state: GameState
var research_rules: ResearchRules
func _init(game_state: GameState,research: ResearchRules=null) -> void:
	state=game_state; research_rules=research if research!=null else ResearchRules.new(state)

func site_at(cell_id: int) -> WorldSiteState: return state.site_at(cell_id)

func interactable_sites(_controller_id: int) -> Array[WorldSiteState]:
	var result: Array[WorldSiteState]=[]
	var team_id:=state.visibility_system.team_id_for_controller(_controller_id)
	for site: WorldSiteState in state.world_sites.values():
		var definition:=state.registry.world_site(site.definition_id)
		if definition!=null and definition.interactable and state.visibility_system.has_discovered_site(team_id,site.id): result.append(site)
	result.sort_custom(func(a: WorldSiteState,b: WorldSiteState)->bool: return a.id<b.id)
	return result

func available_interactions(actor: int,site_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not state.world_sites.has(site_id): return result
	var team_id:=state.visibility_system.team_id_for_controller(actor)
	if not state.visibility_system.has_discovered_site(team_id,site_id): return result
	var site: WorldSiteState=state.world_sites[site_id]
	var definition:=state.registry.world_site(site.definition_id)
	if definition==null or not definition.interactable: return result
	var unit:=_adjacent_unit(actor,site.cell_id)
	if definition.category=="village" and site.runtime_state.get("destroyed",false):
		if site.runtime_state.get("loot_available",false) and not site.runtime_state.get("loot_claimed",false):
			result.append({"id":CLAIM_LOOT,"type":CLAIM_LOOT,"label":"Claim Village Loot","unit_id":unit.id if unit!=null else -1,
				"cost":{},"reward":_compatible_rewards(actor,definition.loot_resources),
				"error":interaction_error(actor,site_id,CLAIM_LOOT,unit.id if unit!=null else -1)})
		return result
	if definition.category=="village" and state.relationship_for_site(actor,site)==RelationshipState.Kind.HOSTILE: return result
	if definition.interaction_type==TRADE:
		for recipe_id: String in definition.trade_recipe_ids:
			var recipe:=state.registry.trade_recipe(recipe_id)
			if recipe==null or not _recipe_compatible(actor,recipe): continue
			result.append({"id":recipe.id,"type":TRADE,"label":recipe.display_name,"unit_id":unit.id if unit!=null else -1,
				"cost":recipe.input_costs.duplicate(),"reward":recipe.output_rewards.duplicate(),
				"error":interaction_error(actor,site_id,recipe.id,unit.id if unit!=null else -1)})
	elif definition.interaction_type in [GATHER,EXPLORE]:
		result.append({"id":definition.interaction_type,"type":definition.interaction_type,
			"label":"Gather" if definition.interaction_type==GATHER else "Explore",
			"unit_id":unit.id if unit!=null else -1,"cost":{},"reward":_compatible_rewards(actor,definition.reward_resources),
			"error":interaction_error(actor,site_id,definition.interaction_type,unit.id if unit!=null else -1)})
	return result

func interaction_error(actor: int,site_id: int,interaction_id: String,unit_id: int=-1) -> String:
	var actor_error:=RuleAuthority.actor_error(state,actor)
	if not actor_error.is_empty(): return actor_error
	if not state.world_sites.has(site_id): return "Unknown world site."
	var team_id:=state.visibility_system.team_id_for_controller(actor)
	if not state.visibility_system.has_discovered_site(team_id,site_id): return "That site has not been discovered."
	if not state.visibility_system.is_visible(team_id,state.world_sites[site_id].cell_id): return "The site must be currently observed to interact."
	var site: WorldSiteState=state.world_sites[site_id]
	var definition:=state.registry.world_site(site.definition_id)
	if definition==null or not definition.interactable: return "This site cannot be used."
	var unit: GameState.Unit=state.units.get(unit_id)
	if unit==null or unit.controller_id!=actor: return "Move one of your units next to the site."
	if unit.attacked: return "This unit already used its action."
	if state.grid.distance(unit.cell_id,site.cell_id)>1: return "The unit must be adjacent to the site."
	if definition.category=="village" and site.runtime_state.get("destroyed",false):
		if interaction_id!=CLAIM_LOOT: return "Destroyed villages cannot trade."
		if site.runtime_state.get("loot_claimed",false) or not site.runtime_state.get("loot_available",false): return "This village's loot has already been claimed."
		if _compatible_rewards(actor,definition.loot_resources).is_empty() and definition.loot_research_progress<=0: return "This village has no useful loot for your faction."
		return ""
	if definition.category=="village" and state.relationship_for_site(actor,site)==RelationshipState.Kind.HOSTILE:
		return "This village is hostile and will not trade."
	if definition.interaction_type==TRADE:
		var recipe:=state.registry.trade_recipe(interaction_id)
		if recipe==null or interaction_id not in definition.trade_recipe_ids: return "That trade is not offered here."
		if not _recipe_compatible(actor,recipe): return "This faction cannot use that trade."
		if not state.players[actor].can_afford(recipe.input_costs): return "Insufficient resources for this trade."
		var key:=_usage_key(actor,recipe.id)
		if int(site.runtime_state.get("trade_usage",{}).get(key,0))>=recipe.usage_limit_per_turn: return "This trade reached its turn limit."
	elif definition.interaction_type==GATHER:
		if interaction_id!=GATHER: return "Invalid gathering action."
		if site.runtime_state.get("exhausted",false) or int(site.runtime_state.get("remaining_charges",0))<=0: return "This site is exhausted."
		if _compatible_rewards(actor,definition.reward_resources).is_empty(): return "This site has no resource your faction can use."
	elif definition.interaction_type==EXPLORE:
		if interaction_id!=EXPLORE: return "Invalid exploration action."
		if site.runtime_state.get("explored",false): return "This ruin has already been explored."
	else: return "This site has no interaction."
	return ""

func try_interact(actor: int,site_id: int,interaction_id: String,unit_id: int=-1) -> RuleResult:
	var error:=interaction_error(actor,site_id,interaction_id,unit_id)
	if not error.is_empty(): return RuleResult.new(false,error)
	var site: WorldSiteState=state.world_sites[site_id]
	var definition:=state.registry.world_site(site.definition_id)
	var player: PlayerState=state.players[actor]
	var message:="Interaction completed."
	if interaction_id==CLAIM_LOOT:
		var reward:=_compatible_rewards(actor,definition.loot_resources); player.add_resources(reward)
		if definition.loot_research_progress>0 and not player.research.current_technology_id.is_empty():
			research_rules.add_research_progress(actor,definition.loot_research_progress)
		site.runtime_state.loot_claimed=true; site.runtime_state.loot_available=false; site.runtime_state.loot_claimed_by=actor
		message="Village loot claimed."
	elif definition.interaction_type==TRADE:
		var recipe:=state.registry.trade_recipe(interaction_id)
		player.apply_cost(recipe.input_costs); player.add_resources(recipe.output_rewards)
		var usage: Dictionary=site.runtime_state.get("trade_usage",{})
		var key:=_usage_key(actor,recipe.id); usage[key]=usage.get(key,0)+1; site.runtime_state.trade_usage=usage
		message="Trade completed: "+recipe.display_name
	else:
		var reward:=_compatible_rewards(actor,definition.reward_resources)
		player.add_resources(reward)
		if definition.interaction_type==GATHER:
			var charges:=int(site.runtime_state.get("remaining_charges",0))-1
			site.runtime_state.remaining_charges=charges
			if charges<=0:
				site.runtime_state.exhausted=true
				site.runtime_state.regeneration_remaining=definition.regeneration_turns
				if definition.remove_when_exhausted: state.world_sites.erase(site.id)
			message="Resources gathered."
		else:
			site.runtime_state.explored=true
			if definition.research_progress_reward>0 and not player.research.current_technology_id.is_empty():
				research_rules.add_research_progress(actor,definition.research_progress_reward)
			message="Ruin explored."
	var unit: GameState.Unit=state.units[unit_id]
	unit.attacked=true; unit.moved=true
	return RuleResult.new(true,message)

func _adjacent_unit(actor: int,cell_id: int) -> GameState.Unit:
	var ids: Array[int]=[]
	for unit: GameState.Unit in state.units.values():
		if unit.controller_id==actor and state.grid.distance(unit.cell_id,cell_id)<=1: ids.append(unit.id)
	ids.sort()
	return state.units[ids[0]] if not ids.is_empty() else null

func _recipe_compatible(actor: int,recipe: TradeRecipeDefinition) -> bool:
	if not state.players.has(actor): return false
	var faction:=state.registry.faction(state.players[actor].faction_id)
	if not recipe.allowed_faction_ids.is_empty() and faction.id not in recipe.allowed_faction_ids: return false
	for values: Dictionary in [recipe.input_costs,recipe.output_rewards]:
		for resource_id: String in values:
			if resource_id not in faction.resource_ids: return false
	return true

func _compatible_rewards(actor: int,rewards: Dictionary[String,int]) -> Dictionary[String,int]:
	var result: Dictionary[String,int]={}
	if not state.players.has(actor): return result
	var faction:=state.registry.faction(state.players[actor].faction_id)
	for resource_id: String in rewards:
		if resource_id in faction.resource_ids: result[resource_id]=rewards[resource_id]
	return result

func _usage_key(actor: int,recipe_id: String) -> String:
	return "%d:%d:%s" % [actor,state.round_number,recipe_id]
