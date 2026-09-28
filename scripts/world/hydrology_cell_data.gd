class_name HydrologyCellData
extends RefCounted

enum SurfaceWater { NONE, LAKE, OCEAN }
enum RiverClass { NONE, STREAM, RIVER, MAJOR_RIVER }

var cell_id: int = -1
var runoff_input: float = 0.0
var raw_downstream_cell_id: int = -1
var downstream_cell_id: int = -1
var flow_accumulation: float = 0.0
var normalized_accumulation: float = 0.0
var basin_id: int = -1
var surface_water_type: int = SurfaceWater.NONE
var lake_id: int = -1
var river_class: int = RiverClass.NONE
var stream_order: int = 0
var river_width_factor: float = 0.0
var hydrology_moisture_bonus: float = 0.0
var wetland_potential: float = 0.0
var filled_height: float = 0.0

