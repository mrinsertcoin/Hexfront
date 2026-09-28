class_name TacticalCameraConfig
extends Resource
## Distances and speeds use world units, independent of planet subdivision.
@export var default_distance: float = 10.0
@export var min_distance: float = 2.5
@export var planet_frame_margin: float = 1.15
@export var default_pitch: float = 80.0
@export var min_pitch: float = 25.0
@export var max_pitch: float = 80.0
@export var field_of_view: float = 30.0
@export var orbit_sensitivity: float = 0.25
@export var keyboard_yaw_speed: float = 90.0
@export var drag_threshold: float = 5.0
@export var close_pan_speed: float = 3.0
@export var far_pan_speed: float = 45.0
@export var pan_response: float = 14.0
@export var zoom_response: float = 1.16
@export var smoothing: float = 14.0
@export var near_focus_seconds: float = 0.22
@export var far_focus_seconds: float = 0.85
@export var distant_angle: float = 0.6
@export var pullback_fraction: float = 0.45
@export var terrain_clearance: float = 0.6
@export var tactical_band_multiplier: float = 1.3
@export var regional_band_multiplier: float = 2.4
@export var planet_band_fraction: float = 0.7
