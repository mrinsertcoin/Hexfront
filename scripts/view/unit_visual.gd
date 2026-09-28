class_name UnitVisual
extends Node3D
## Presentation settings live on the wrapper, outside the imported rig.
@export_range(0.1, 20.0) var move_speed: float = 4.0
@export var idle_clip: StringName = &"Idle"
@export var move_clip: StringName = &"Move"
@export var animation_player_path: NodePath
@export_range(0.0, 1.0) var blend_seconds: float = 0.12

var animation_player: AnimationPlayer
var _idle: StringName
var _move: StringName

func initialize_animation() -> void:
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer if not animation_player_path.is_empty() else _find_player(self)
	if animation_player == null:
		return # Static placeholders still follow the movement path.
	_idle = _resolve_clip(idle_clip, ["idle"])
	_move = _resolve_clip(move_clip, ["move", "walk", "run", "crawl", "hop"])
	# Imported animation resources are shared between instances. Localize before
	# setting loop mode so one model's settings never modify another's resources.
	for library_name: StringName in animation_player.get_animation_library_list():
		var library: AnimationLibrary = animation_player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	for clip: StringName in [_idle, _move]:
		if not clip.is_empty():
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	set_moving(false)

func set_moving(moving: bool) -> void:
	if animation_player == null:
		return
	var clip: StringName = _move if moving else _idle
	if clip.is_empty():
		animation_player.stop() # Missing idle must not leave locomotion looping.
	elif animation_player.current_animation != clip or not animation_player.is_playing():
		animation_player.play(clip, blend_seconds)

func _resolve_clip(preferred: StringName, aliases: Array[String]) -> StringName:
	if animation_player.has_animation(preferred):
		return preferred
	# Namespaced clips such as locomotion/Walk work without renaming the GLB.
	for clip: StringName in animation_player.get_animation_list():
		if String(clip).get_file().to_lower() in aliases:
			return clip
	return &""

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
