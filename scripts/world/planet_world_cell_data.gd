class_name PlanetWorldCellData
extends RefCounted
## Cached samples, separate from PlanetCell topology and gameplay occupancy.
const FIELD_NAMES: PackedStringArray = ["height", "temperature", "moisture", "fertility", "terrain_roughness"]
var cell_id: int = -1
var height: float
var temperature: float
var moisture: float
var base_moisture: float
var effective_moisture: float
var fertility: float
var terrain_roughness: float
var biome_weights: PackedFloat64Array = [] # Config's explicit biome order.
var dominant_biome: String
var region_id: int = -1
var hydrology: HydrologyCellData

func scalar_values() -> PackedFloat64Array:
	return [height, temperature, moisture, fertility, terrain_roughness]
