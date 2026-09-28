class_name RiverSegment
extends RefCounted

var from_cell_id: int = -1
var to_cell_id: int = -1
var accumulation: float = 0.0
var river_class: int = HydrologyCellData.RiverClass.NONE
var stream_order: int = 0
var width_factor: float = 0.0

