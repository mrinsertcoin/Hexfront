class_name RelationshipState
extends RefCounted

enum Kind { SELF, ALLIED, NEUTRAL, HOSTILE }
var overrides: Dictionary[String,int]={}

func set_relationship(a: int,b: int,relationship: Kind) -> void:
	if a==b: return
	overrides[_key(a,b)]=relationship

func between(a: int,b: int) -> Kind:
	if a==b: return Kind.SELF
	return overrides.get(_key(a,b),Kind.NEUTRAL)

func is_hostile(a: int,b: int) -> bool:
	return between(a,b)==Kind.HOSTILE

func clear_controller(controller_id: int) -> void:
	var removed:=PackedStringArray()
	for key: String in overrides:
		var parts:=key.split(":")
		if int(parts[0])==controller_id or int(parts[1])==controller_id: removed.append(key)
	for key: String in removed: overrides.erase(key)

func _key(a: int,b: int) -> String:
	return "%d:%d" % [mini(a,b),maxi(a,b)]
