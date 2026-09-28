class_name DrainageBasinData
extends RefCounted

var id: int = -1
var sink_cell_id: int = -1
var cell_ids: PackedInt32Array = []
var spill_inside_cell_id: int = -1
var spill_outside_cell_id: int = -1
var spill_height: float = INF

