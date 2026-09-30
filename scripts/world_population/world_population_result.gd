class_name WorldPopulationResult
extends RefCounted

var generation_version: int
var world_fingerprint: String
var config_fingerprint: String
var site_records: Array[Dictionary]=[]
var neutral_group_records: Array[Dictionary]=[]
var fingerprint: String
var generation_ms: float=0.0

func refresh_fingerprint() -> void:
	var rows:=PackedStringArray(["world-population-v%d" % generation_version,world_fingerprint,config_fingerprint])
	for record: Dictionary in site_records:
		rows.append("site:%s:%d:%d:%s" % [record.definition_id,record.cell_id,record.get("controller_id",0),record.get("stream","")])
	for record: Dictionary in neutral_group_records:
		var units:=PackedStringArray()
		for unit: Dictionary in record.get("unit_records",[]): units.append("%s@%d" % [unit.definition_id,unit.cell_id])
		rows.append("neutral:%s:%d:%d:%d:%s" % [record.definition_id,record.cell_id,record.get("controller_id",0),record.get("site_cell_id",-1),",".join(units)])
	fingerprint="|".join(rows).sha256_text()

func summary() -> String:
	return "World population | sites %d | groups %d | %.2f ms | %s" % [site_records.size(),neutral_group_records.size(),generation_ms,fingerprint]
