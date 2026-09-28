class_name PlanetRegionData
extends RefCounted
var id: int
var cell_ids: Array[int] = []
var center_direction: Vector3
var dominant_biome: String
var average_height: float
var average_temperature: float
var average_moisture: float
var average_fertility: float
var average_roughness: float
var cell_count: int:
	get:
		return cell_ids.size()
