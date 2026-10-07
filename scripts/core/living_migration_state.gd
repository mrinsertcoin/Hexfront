class_name LivingMigrationState
extends RefCounted

var terrain: Dictionary[int,TerrainConsumptionState]={}
var roads: Dictionary[int,Dictionary]={}
var corpses: Dictionary[int,CorpseState]={}
var next_corpse_id: int=1
var last_regrowth_round: int=1
var unpaid_upkeep: Dictionary[int,Dictionary]={}
var larvae: Dictionary[int,LarvaState]={}
var next_larva_id: int=1

func terrain_at(cell_id: int) -> TerrainConsumptionState:
	if not terrain.has(cell_id): terrain[cell_id]=TerrainConsumptionState.new()
	return terrain[cell_id]

func add_road(controller_id: int,cell_id: int) -> void:
	if not roads.has(controller_id): roads[controller_id]={}
	roads[controller_id][cell_id]=true

func road_cells(controller_id: int) -> Array[int]:
	var result: Array[int]=[]
	for cell_id: int in roads.get(controller_id,{}).keys(): result.append(cell_id)
	result.sort(); return result

func add_corpse(definition_id: String,cell_id: int,food_value: int) -> CorpseState:
	var corpse:=CorpseState.new(next_corpse_id,definition_id,cell_id,food_value)
	next_corpse_id+=1; corpses[corpse.id]=corpse; return corpse

func add_larva(owner: int,species: String,cell_id: int,created_round: int,maturation_round: int,outcome: bool) -> LarvaState:
	var larva:=LarvaState.new(next_larva_id,owner,species,cell_id,created_round,maturation_round,outcome)
	next_larva_id+=1; larvae[larva.id]=larva; return larva
