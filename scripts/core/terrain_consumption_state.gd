class_name TerrainConsumptionState
extends RefCounted

enum Kind { FRESH, DEPLETED, REGROWING }
var kind: Kind=Kind.FRESH
var regrowth_turns_remaining: int=0

func deplete(regrowth_turns: int) -> void:
	kind=Kind.DEPLETED; regrowth_turns_remaining=maxi(0,regrowth_turns)

func advance() -> void:
	if kind==Kind.DEPLETED:
		kind=Kind.REGROWING
		regrowth_turns_remaining=maxi(0,regrowth_turns_remaining-1)
	elif kind==Kind.REGROWING:
		regrowth_turns_remaining=maxi(0,regrowth_turns_remaining-1)
	if kind==Kind.REGROWING and regrowth_turns_remaining==0: kind=Kind.FRESH

func snapshot() -> Dictionary: return {"kind":kind,"regrowth_turns_remaining":regrowth_turns_remaining}
