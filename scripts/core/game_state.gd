class_name GameState
extends RefCounted

# Logical state only. Scene nodes read this; Rules applies gameplay commands.
class Unit extends RefCounted:
	var id: int
	var owner_id: int
	var unit_type: String
	var cell_id: int
	var movement: int
	var moved: bool = false
	var max_hp: int
	var hp: int
	var attack_range: int
	var attack_damage: int
	var attacked: bool = false
	var ready_next_turn: bool = false

	func _init(unit_id: int, owner: int, kind: String, coordinate: int, allowance: int = -1) -> void:
		id = unit_id
		owner_id = owner
		unit_type = kind.capitalize()
		cell_id = coordinate
		var stats: Dictionary = UnitTypes.STATS[unit_type]
		movement = int(stats["movement"]) if allowance < 0 else allowance
		max_hp = int(stats["hp"])
		hp = max_hp
		attack_range = int(stats["range"])
		attack_damage = int(stats["damage"])

class Structure extends RefCounted:
	var id: int
	var owner_id: int
	var structure_type: String
	var cell_id: int
	var max_hp: int
	var hp: int
	var recruit_available: bool = true

	func _init(struct_id: int, owner: int, kind: String, coordinate: int, hp_value: int) -> void:
		id = struct_id
		owner_id = owner
		structure_type = kind
		cell_id = coordinate
		max_hp = hp_value
		hp = max_hp

var units: Dictionary[int, Unit] = {}
var structures: Dictionary[int, Structure] = {}
var next_id: int = 200
var last_started_turn: int = -1
var materials: Dictionary[int, int] = {1: 8, 2: 8}
var active_player: int = 1
var round_number: int = 1
var winner_id: int = 0

var grid: PlanetGrid

func _init(topology: PlanetGrid = null) -> void:
	grid = topology if topology != null else PlanetGrid.new()
	reset_match()

func reset_match() -> void:
	units.clear()
	structures.clear()
	# Start generated IDs well above scene-created IDs to avoid collisions
	next_id = 200
	materials = {1: 8, 2: 8}
	active_player = 1
	round_number = 1
	winner_id = 0
	last_started_turn = -1
	# Vertex 0 and its graph-farthest cell: deterministic and widely separated.
	var homes: Array[int] = [0, grid.breadth_first(0).order[-1]]
	for player in [1, 2]:
		var home: int = homes[player - 1]
		var neighbors: Array[int] = grid.get_neighbors(home)
		var ids: Array[int] = []
		ids.assign([1, 2, 5] if player == 1 else [3, 4, 6])
		var kinds: Array[String] = ["Infantry", "Scout", "Gunner"]
		for index in range(3):
			units[ids[index]] = Unit.new(ids[index], player, kinds[index], neighbors[index])
		var hq_id: int = 99 + player
		structures[hq_id] = Structure.new(hq_id, player, "Headquarters", home, 25)
	start_turn()

func unit_at(cell_id: int) -> Unit:
	for unit: Unit in units.values():
		if unit.cell_id == cell_id:
			return unit
	return null

func structure_at(cell_id: int) -> Structure:
	for s: Structure in structures.values():
		if s.cell_id == cell_id:
			return s
	return null

func entity_at(cell_id: int) -> RefCounted:
	var u := unit_at(cell_id)
	if u != null:
		return u
	var s := structure_at(cell_id)
	if s != null:
		return s
	return null

func allocate_id() -> int:
	while units.has(next_id) or structures.has(next_id):
		next_id += 1
	var id := next_id
	next_id += 1
	return id


func start_turn() -> void:
	# Idempotent: repeated initialization/presentation cannot grant income twice.
	var turn: int = (round_number - 1) * 2 + active_player
	if winner_id != 0 or last_started_turn == turn:
		return
	last_started_turn = turn
	materials[active_player] += 3
	for unit: Unit in units.values():
		if unit.owner_id == active_player:
			unit.moved = false
			unit.attacked = false
			unit.ready_next_turn = false
	for structure: Structure in structures.values():
		if structure.owner_id == active_player:
			structure.recruit_available = true
