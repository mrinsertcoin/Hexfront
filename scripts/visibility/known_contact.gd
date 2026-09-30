class_name KnownContact
extends RefCounted
## Historical observation. It never retains an authoritative entity reference.

var contact_id: int
var entity_kind: String
var observed_definition_id: String
var last_known_cell_id: int
var last_seen_round: int
var last_seen_turn: int
var observed_snapshot: Dictionary

func _init(snapshot: Dictionary={}) -> void:
	contact_id=snapshot.get("id",-1); entity_kind=snapshot.get("kind","")
	observed_definition_id=snapshot.get("definition_id",""); last_known_cell_id=snapshot.get("cell_id",-1)
	last_seen_round=snapshot.get("observed_round",0); last_seen_turn=snapshot.get("observed_turn",0)
	observed_snapshot=snapshot.duplicate(true)

func snapshot() -> Dictionary:
	return {"contact_id":contact_id,"entity_kind":entity_kind,"observed_definition_id":observed_definition_id,
		"last_known_cell_id":last_known_cell_id,"last_seen_round":last_seen_round,"last_seen_turn":last_seen_turn,
		"observed_snapshot":observed_snapshot.duplicate(true),"historical":true}
