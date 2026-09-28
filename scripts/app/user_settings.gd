class_name UserSettings
extends RefCounted
## Preferences persisted between launches. Never contains match/session state.

const PATH := "user://hexfront.cfg"
var storage_path: String = PATH
var fullscreen: bool = false
var vsync: bool = true
var master_volume_db: float = 0.0
var orbit_sensitivity: float = 0.25
var zoom_response: float = 1.16
var drag_threshold: float = 5.0
var terrain_quality: String = "High"

func load_from_disk() -> void:
	var file := ConfigFile.new()
	if file.load(storage_path) != OK: return
	fullscreen = bool(file.get_value("display", "fullscreen", fullscreen))
	vsync = bool(file.get_value("display", "vsync", vsync))
	master_volume_db = clampf(float(file.get_value("audio", "master_volume_db", master_volume_db)), -40.0, 6.0)
	orbit_sensitivity = clampf(float(file.get_value("camera", "orbit_sensitivity", orbit_sensitivity)), 0.05, 1.0)
	zoom_response = clampf(float(file.get_value("camera", "zoom_response", zoom_response)), 1.02, 1.5)
	drag_threshold = clampf(float(file.get_value("camera", "drag_threshold", drag_threshold)), 2.0, 12.0)
	terrain_quality = str(file.get_value("graphics", "terrain_quality", terrain_quality))
	if terrain_quality not in ["Medium", "High"]: terrain_quality = "High"

func save_to_disk() -> Error:
	var file := ConfigFile.new()
	file.set_value("display", "fullscreen", fullscreen)
	file.set_value("display", "vsync", vsync)
	file.set_value("audio", "master_volume_db", master_volume_db)
	file.set_value("camera", "orbit_sensitivity", orbit_sensitivity)
	file.set_value("camera", "zoom_response", zoom_response)
	file.set_value("camera", "drag_threshold", drag_threshold)
	file.set_value("graphics", "terrain_quality", terrain_quality)
	return file.save(storage_path)

func apply_global() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_volume_db(0, master_volume_db)

func camera_configuration() -> TacticalCameraConfig:
	var result := TacticalCameraConfig.new()
	result.orbit_sensitivity = orbit_sensitivity
	result.zoom_response = zoom_response
	result.drag_threshold = drag_threshold
	return result

func terrain_subdivision() -> int:
	return 4 if terrain_quality == "Medium" else 5

func terrain_texture_resolution() -> int:
	return 256 if terrain_quality == "Medium" else 512
