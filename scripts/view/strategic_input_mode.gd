class_name StrategicInputMode
extends RefCounted
## Ephemeral board interaction modes. Authoritative changes still go through GameRules.

enum Kind {
	NORMAL,
	MOVE,
	ATTACK,
	RECRUIT,
	ROAD,
	PILLAR,
	BRIDGE,
	HEAL,
	REPAIR,
	DESIGNATE,
}

static func display_name(mode: int) -> String:
	if mode < 0 or mode >= Kind.size(): return "Unknown"
	return Kind.keys()[mode].capitalize()
