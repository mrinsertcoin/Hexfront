class_name PlayerState
extends RefCounted

var player_id: int
var controller_id: int
var faction_id: String
var player_name: String
var ownership_color: String
var connected: bool=true
var eliminated: bool=false
var elimination_round: int=0
var resources: Dictionary[String,int]={}
var research:=ResearchState.new()

func _init(id: int=0,controller: int=0,faction: String="",display_name: String="",color_hex: String="") -> void:
	player_id=id; controller_id=controller; faction_id=faction
	player_name=display_name if not display_name.is_empty() else "Player %d" % id
	ownership_color=color_hex if color_hex.is_valid_html_color() else ""

func resource_amount(resource_id: String) -> int:
	return resources.get(resource_id,0)

func can_afford(costs: Dictionary[String,int]) -> bool:
	for resource_id: String in costs:
		if resource_amount(resource_id)<costs[resource_id]: return false
	return true

func apply_cost(costs: Dictionary[String,int]) -> void:
	for resource_id: String in costs: resources[resource_id]=resource_amount(resource_id)-costs[resource_id]

func add_resources(income: Dictionary[String,int]) -> void:
	for resource_id: String in income: resources[resource_id]=resource_amount(resource_id)+income[resource_id]
