class_name SurfaceCamera
extends RefCounted
## One surface-relative rig. Heading is parallel transported, never reset to north.
var config: TacticalCameraConfig
var camera: Camera3D
var surface: TerrainSurfaceSampler
var radius: float
var focus_direction := Vector3.LEFT
var heading := Vector3.FORWARD
var yaw: float = 0.0
var target_yaw: float = 0.0
var pitch: float = 60.0
var target_pitch: float = 60.0
var distance: float = 5.0
var target_distance: float = 5.0
var focused_entity: int = -1
var transitioning: bool = false
var pan_velocity := Vector2.ZERO
var _start := Vector3.LEFT
var _goal := Vector3.LEFT
var _axis := Vector3.UP
var _angle: float = 0.0
var _elapsed: float = 0.0
var _duration: float = 0.0
var _pullback: float = 0.0

func initialize(view: Camera3D, terrain: TerrainSurfaceSampler, planet_radius: float, settings: TacticalCameraConfig) -> void:
	camera = view
	surface = terrain
	radius = planet_radius
	config = settings
	camera.fov = config.field_of_view
	camera.far = max_distance() + radius * 3.0
	reset(Vector3.LEFT)

func max_distance() -> float:
	# Respect the limiting horizontal/vertical FOV, including portrait windows.
	var size := camera.get_viewport().get_visible_rect().size
	var half_fov := deg_to_rad(config.field_of_view * 0.5)
	if size.x < size.y:
		half_fov = atan(tan(half_fov) * size.x / maxf(size.y, 1.0))
	return (radius + surface.config.mapped_height(1.0)) / sin(half_fov) * config.planet_frame_margin

func reset(direction: Vector3) -> void:
	manual_navigation()
	pan_velocity = Vector2.ZERO
	focus_direction = direction.normalized()
	heading = -PlanetCell.tangent_basis(focus_direction).z
	yaw = 0.0
	target_yaw = 0.0
	pitch = config.default_pitch
	target_pitch = pitch
	distance = config.default_distance
	target_distance = distance
	apply_transform()

func manual_navigation() -> void:
	# Interrupt a pullback at its currently displayed distance, without a pop.
	if _pullback > 0.0:
		distance = minf(distance + _pullback, max_distance())
		target_distance = distance
	transitioning = false
	_pullback = 0.0
	focused_entity = -1

func rotation_between(a: Vector3, b: Vector3) -> Quaternion:
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.9999999:
		return Quaternion.IDENTITY
	var axis := a.cross(b)
	if axis.length_squared() < 0.00000001:
		axis = heading - a * heading.dot(a)
	return Quaternion(axis.normalized(), acos(dot))

func transport(direction: Vector3) -> void:
	var next := direction.normalized()
	var rotation := rotation_between(focus_direction, next)
	heading = rotation * heading
	heading = (heading - next * heading.dot(next)).normalized()
	focus_direction = next

func forward() -> Vector3:
	return heading.rotated(focus_direction, deg_to_rad(yaw))

func focus(direction: Vector3, immediate: bool = false) -> void:
	pan_velocity = Vector2.ZERO
	_goal = direction.normalized()
	if immediate:
		transitioning = false
		_pullback = 0.0
		transport(_goal)
		apply_transform()
		return
	_start = focus_direction
	_angle = acos(clampf(_start.dot(_goal), -1.0, 1.0))
	_axis = _start.cross(_goal)
	if _axis.length_squared() < 0.00000001:
		_axis = heading
	_axis = _axis.normalized()
	_duration = lerpf(config.near_focus_seconds, config.far_focus_seconds, clampf(_angle / PI, 0, 1))
	_elapsed = 0.0
	transitioning = true

func orbit(delta: Vector2) -> void:
	manual_navigation()
	target_yaw -= delta.x * config.orbit_sensitivity
	target_pitch = clampf(target_pitch - delta.y * config.orbit_sensitivity, config.min_pitch, config.max_pitch)

func zoom(steps: float) -> void:
	manual_navigation()
	target_distance = clampf(target_distance * pow(config.zoom_response, steps), config.min_distance, max_distance())

func grab(anchor: Vector3, cursor: Vector2) -> void:
	manual_navigation()
	pan_velocity = Vector2.ZERO
	# Rotate the camera frame from the current ray hit back to the grabbed point.
	# A few corrections accommodate displaced terrain and perspective at low pitch.
	for iteration in range(3):
		var hit := surface.ray_hit(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
		if hit == Vector3.ZERO: return
		var rotation := rotation_between(hit.normalized(), anchor)
		heading = rotation * heading
		focus_direction = (rotation * focus_direction).normalized()
		heading = (heading - focus_direction * heading.dot(focus_direction)).normalized()
		apply_transform()

func update(delta: float, pan: Vector2 = Vector2.ZERO, followed_position: Vector3 = Vector3.ZERO) -> void:
	var blend := 1.0 - exp(-config.smoothing * delta)
	yaw = rad_to_deg(lerp_angle(deg_to_rad(yaw), deg_to_rad(target_yaw), blend))
	pitch = lerpf(pitch, target_pitch, blend)
	distance = lerpf(distance, target_distance, blend)
	var speed := lerpf(config.close_pan_speed, config.far_pan_speed, clampf((distance - config.min_distance) / max_distance(), 0, 1))
	if pan.length_squared() > 0:
		manual_navigation()
	var desired := pan.limit_length() * speed
	var response := 1.0 - exp(-config.pan_response * delta)
	var integrated_pan := desired * delta + (pan_velocity - desired) * response / config.pan_response
	pan_velocity = pan_velocity.lerp(desired, response)
	if integrated_pan.length_squared() > 0.00000001:
		var ahead := forward()
		var movement := ahead.cross(focus_direction) * integrated_pan.x + ahead * integrated_pan.y
		transport(focus_direction.rotated(focus_direction.cross(movement).normalized(), movement.length() / surface.radius_at(focus_direction)))
	if transitioning:
		_elapsed += delta
		var t := clampf(_elapsed / _duration, 0, 1)
		var eased := t * t * (3.0 - 2.0 * t)
		transport(_start.rotated(_axis, _angle * eased))
		_pullback = sin(PI * t) * radius * config.pullback_fraction if _angle > config.distant_angle else 0.0
		if t >= 1:
			transport(_goal)
			transitioning = false
			_pullback = 0.0
	elif focused_entity != -1 and followed_position != Vector3.ZERO:
		var rotation := rotation_between(focus_direction, followed_position.normalized())
		transport(Quaternion.IDENTITY.slerp(rotation, blend) * focus_direction)
	apply_transform()

func apply_transform() -> void:
	camera.fov = config.field_of_view
	camera.far = max_distance() + radius * 3.0
	var focus_position := surface.sample_position(focus_direction)
	var boom := distance + _pullback
	var planet_mix := smoothstep(radius * 0.75, max_distance(), boom)
	var aim := focus_position.lerp(Vector3.ZERO, planet_mix)
	var angle := deg_to_rad(lerpf(pitch, 90.0, planet_mix))
	var offset := focus_direction * sin(angle) - forward() * cos(angle)
	var position := focus_position + offset * boom
	var clearance := surface.radius_at(position.normalized()) + config.terrain_clearance
	if position.length() < clearance:
		position = position.normalized() * clearance
	camera.position = position
	# The forward tangent defines screen up even at a straight-down planet view.
	camera.look_at(aim, forward())

func zoom_band() -> String:
	if distance < config.default_distance * config.tactical_band_multiplier: return "TACTICAL"
	if distance < maxf(radius, config.default_distance * config.regional_band_multiplier): return "REGIONAL"
	if distance < max_distance() * config.planet_band_fraction: return "STRATEGIC"
	return "PLANET"
