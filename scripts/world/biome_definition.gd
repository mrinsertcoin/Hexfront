class_name BiomeDefinition
extends Resource
## Ordered preferences: height, temperature, moisture, fertility, terrain roughness.
@export var biome_id: String = "Grassland"
@export var centers: PackedFloat64Array = [0.45, 0.60, 0.50, 0.65, 0.30]
@export var widths: PackedFloat64Array = [0.45, 0.40, 0.25, 0.30, 0.30]
@export var influences: PackedFloat64Array = [0.3, 0.3, 1.0, 0.3, 0.7]
@export var prior: float = 1.0

func score(fields: PackedFloat64Array) -> float:
	var penalty: float = 0.0
	for i in range(5):
		var deviation: float = (fields[i] - centers[i]) / widths[i]
		penalty += influences[i] * deviation * deviation
	return prior * exp(-0.5 * penalty)

func to_dict() -> Dictionary:
	return {"id": biome_id, "centers": Array(centers), "widths": Array(widths),
		"influences": Array(influences), "prior": prior}

static func definition(id: String, target: PackedFloat64Array, spread: PackedFloat64Array,
		importance: PackedFloat64Array, bias: float = 1.0) -> BiomeDefinition:
	var result := BiomeDefinition.new()
	result.biome_id = id
	result.centers = target
	result.widths = spread
	result.influences = importance
	result.prior = bias
	return result

static func defaults() -> Array[BiomeDefinition]:
	return [
		definition("Grassland", [0.45,0.60,0.50,0.65,0.30], [0.45,0.40,0.25,0.30,0.30], [0.3,0.3,1.0,0.3,0.7]),
		definition("Forest", [0.50,0.60,0.76,0.75,0.40], [0.40,0.35,0.22,0.30,0.35], [0.3,0.4,1.5,0.5,0.4]),
		definition("Dryland", [0.50,0.70,0.20,0.30,0.45], [0.45,0.50,0.23,0.35,0.40], [0.2,0.2,1.8,0.5,0.2]),
		definition("Rocky", [0.72,0.40,0.40,0.30,0.78], [0.24,0.60,0.50,0.40,0.24], [0.8,0.1,0.1,0.3,1.5]),
		definition("Wetland", [0.25,0.55,0.82,0.70,0.20], [0.24,0.45,0.23,0.40,0.27], [0.8,0.2,1.3,0.2,0.7])]
