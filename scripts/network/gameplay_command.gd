class_name GameplayCommand
extends RefCounted
## Primitive client intention. The authenticated peer supplies player identity.

var protocol_version: int=NetworkProtocol.NETWORK_PROTOCOL_VERSION
var client_sequence: int=0
var command_type: String=""
var parameters: Dictionary={}

static func create(sequence: int,type: String,values: Dictionary={}) -> Dictionary:
	return {"protocol_version":NetworkProtocol.NETWORK_PROTOCOL_VERSION,"client_sequence":sequence,
		"command_type":type,"parameters":values.duplicate(true)}

static func validation_error(value: Variant) -> String:
	if not value is Dictionary: return "Malformed command."
	var data:=value as Dictionary
	if data.size()!=4: return "Malformed command."
	for key: String in ["protocol_version","client_sequence","command_type","parameters"]:
		if not data.has(key): return "Malformed command."
	if int(data.protocol_version)!=NetworkProtocol.NETWORK_PROTOCOL_VERSION: return "Unsupported command protocol."
	if int(data.client_sequence)<=0: return "Invalid command sequence."
	if String(data.command_type).is_empty() or String(data.command_type).length()>64: return "Invalid command type."
	if not data.parameters is Dictionary or data.parameters.size()>32 or not _is_primitive(data.parameters): return "Malformed command parameters."
	return ""

static func _is_primitive(value: Variant,depth: int=0) -> bool:
	if depth>8: return false
	if value==null or value is bool or value is int or value is float: return true
	if value is String: return value.length()<=256
	if value is Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedStringArray:
		if value.size()>128: return false
		for item: Variant in value:
			if not _is_primitive(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size()>64: return false
		for key: Variant in value:
			if not (key is String or key is int) or not _is_primitive(value[key],depth+1): return false
		return true
	return false
