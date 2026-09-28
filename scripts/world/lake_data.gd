class_name LakeData
extends RefCounted

var id: int = -1
var cell_ids: PackedInt32Array = []
var surface_height: float = 0.0
var inflow_cells: PackedInt32Array = []
var outflow_cell_id: int = -1
var terminal: bool = false
var catchment_size: float = 0.0
var center_direction: Vector3 = Vector3.ZERO

