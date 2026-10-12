class_name RelationshipState
extends RefCounted

enum Kind { SELF, ALLIED, NEUTRAL, HOSTILE }
var overrides: Dictionary[String,int]={}
var site_hostilities: Dictionary[String,bool]={}

func set_relationship(a: int,b: int,relationship: Kind) -> void:
	if a==b: return
	overrides[_key(a,b)]=relationship

func between(a: int,b: int) -> Kind:
	if a==b: return Kind.SELF
	return overrides.get(_key(a,b),Kind.NEUTRAL)

func is_hostile(a: int,b: int) -> bool:
	return between(a,b)==Kind.HOSTILE

func set_site_hostile(player_id: int,neutral_controller_id: int,site_id: int) -> void:
	site_hostilities["%d:%d:%d" % [player_id,neutral_controller_id,site_id]]=true

func is_site_hostile(player_id: int,neutral_controller_id: int,site_id: int) -> bool:
	return bool(site_hostilities.get("%d:%d:%d" % [player_id,neutral_controller_id,site_id],false))

func clear_controller(controller_id: int) -> void:
	var removed:=PackedStringArray()
	for key: String in overrides:
		var parts:=key.split(":")
		if int(parts[0])==controller_id or int(parts[1])==controller_id: removed.append(key)
	for key: String in removed: overrides.erase(key)
	removed.clear()
	for key: String in site_hostilities:
		var parts:=key.split(":")
		if int(parts[0])==controller_id or int(parts[1])==controller_id: removed.append(key)
	for key: String in removed: site_hostilities.erase(key)

func _key(a: int,b: int) -> String:
	return "%d:%d" % [mini(a,b),maxi(a,b)]
