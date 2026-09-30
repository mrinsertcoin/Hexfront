class_name PlayerState
extends RefCounted

var player_id: int
var controller_id: int
var faction_id: String
var resources: Dictionary[String,int]={}
var research:=ResearchState.new()

func _init(id: int=0,controller: int=0,faction: String="") -> void:
	player_id=id; controller_id=controller; faction_id=faction

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
