class_name UnitTypes
extends RefCounted

# One source for prototype stats. No combat or presentation code owns copies.
const STATS: Dictionary = {
	"Infantry": {"hp": 10, "movement": 2, "range": 1, "damage": 3},
	"Scout": {"hp": 6, "movement": 3, "range": 1, "damage": 2},
	"Gunner": {"hp": 7, "movement": 1, "range": 2, "damage": 3},
}

const COSTS: Dictionary = {
	"Infantry": 4,
	"Scout": 3,
	"Gunner": 5,
}
