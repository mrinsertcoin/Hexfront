class_name MusicManager
extends Node
## Persistent two-player music playback. App state chooses the requested track.

const MUSIC_BUS: StringName = &"Music"
const SILENCE_DB: float = -80.0

@export_range(0.0,5.0,0.1) var crossfade_seconds: float = 2.0
@export var playback_enabled: bool = true
@export var warn_on_missing_tracks: bool = true

var current_track_id: StringName = &""
var transition_generation: int = 0
var _players: Array[AudioStreamPlayer]=[]
var _active_index: int = -1
var _transition: Tween

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	# Headless suites validate state transitions without opening decoder playback.
	if DisplayServer.get_name()=="headless": playback_enabled=false
	ensure_music_bus()
	for index in range(2):
		var player:=AudioStreamPlayer.new()
		player.name="MusicPlayer%d" % (index+1)
		player.bus=MUSIC_BUS
		player.process_mode=Node.PROCESS_MODE_ALWAYS
		player.volume_db=SILENCE_DB
		add_child(player)
		_players.append(player)

static func ensure_music_bus() -> int:
	var index:=AudioServer.get_bus_index(MUSIC_BUS)
	if index<0:
		AudioServer.add_bus()
		index=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,MUSIC_BUS)
		AudioServer.set_bus_send(index,&"Master")
	return index

func set_music_volume_db(value: float) -> void:
	AudioServer.set_bus_volume_db(ensure_music_bus(),clampf(value,-40.0,6.0))

func play_title() -> bool:
	return request_track(MusicTrackRegistry.TITLE)

func play_faction(faction_id: String) -> bool:
	var track_id:=MusicTrackRegistry.track_for_faction(faction_id)
	if track_id.is_empty():
		push_warning("No music is registered for faction: "+faction_id)
		return false
	return request_track(track_id)

func request_track(track_id: StringName) -> bool:
	if track_id.is_empty() or track_id==current_track_id: return false
	var stream:=MusicTrackRegistry.load_stream(track_id,warn_on_missing_tracks)
	if stream==null: return false
	if _players.size()!=2:
		push_warning("MusicManager is not ready for playback")
		return false
	transition_generation+=1
	if _transition!=null and _transition.is_valid(): _transition.kill()
	var outgoing_index:=_active_index
	var incoming_index:=0 if outgoing_index!=0 else 1
	var incoming:=_players[incoming_index]
	var outgoing: AudioStreamPlayer=null if outgoing_index<0 else _players[outgoing_index]
	incoming.stop()
	incoming.stream=stream
	incoming.volume_db=SILENCE_DB
	if playback_enabled: incoming.play()
	_active_index=incoming_index
	current_track_id=track_id
	if crossfade_seconds<=0.0:
		incoming.volume_db=0.0
		if outgoing!=null: outgoing.stop()
		return true
	var generation:=transition_generation
	_transition=create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition.set_parallel(true)
	_transition.tween_property(incoming,"volume_db",0.0,crossfade_seconds)
	if outgoing!=null and outgoing.playing:
		_transition.tween_property(outgoing,"volume_db",SILENCE_DB,crossfade_seconds)
	_transition.chain().tween_callback(_finish_transition.bind(generation,outgoing_index))
	return true

func _finish_transition(generation: int,outgoing_index: int) -> void:
	if generation!=transition_generation: return
	if outgoing_index>=0 and outgoing_index!=_active_index:
		_players[outgoing_index].stop()

func active_player() -> AudioStreamPlayer:
	return null if _active_index<0 else _players[_active_index]

func _exit_tree() -> void:
	if _transition!=null and _transition.is_valid(): _transition.kill()
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream=null
	_players.clear()
