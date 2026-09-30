extends SceneTree

var failures:=0

func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(MusicTrackRegistry.path_for(MusicTrackRegistry.TITLE).ends_with("the_uncharted_atlas.ogg"),
		"Title context resolves The Uncharted Atlas")
	check(MusicTrackRegistry.track_for_faction("Swarm")==MusicTrackRegistry.SWARM
		and MusicTrackRegistry.track_for_faction("Blue")==MusicTrackRegistry.SWARM,
		"Swarm faction identity resolves Cycles of the Canopy")
	check(MusicTrackRegistry.track_for_faction("Builders")==MusicTrackRegistry.BUILDERS
		and MusicTrackRegistry.track_for_faction("Red")==MusicTrackRegistry.BUILDERS,
		"Builders faction identity resolves Weight of the Foundation")
	for track_id: StringName in MusicTrackRegistry.TRACK_PATHS:
		var stream:=MusicTrackRegistry.load_stream(track_id)
		check(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop,
			"Canonical music stream loads in streamed looping format: "+str(track_id))
	var manager:=MusicManager.new()
	manager.crossfade_seconds=0.0
	manager.playback_enabled=false # Logical test double avoids headless decoder lifetime noise.
	manager.warn_on_missing_tracks=false
	root.add_child(manager)
	check(AudioServer.get_bus_index("Music")>=0,"Dedicated Music audio bus is available")
	check(manager.play_title() and manager.current_track_id==MusicTrackRegistry.TITLE,
		"Music manager accepts title context")
	var generation:=manager.transition_generation
	var player:=manager.active_player()
	check(not manager.play_title() and manager.transition_generation==generation and manager.active_player()==player,
		"Repeated same-track request does not restart playback")
	check(manager.play_faction("Swarm") and manager.current_track_id==MusicTrackRegistry.SWARM,
		"Music manager accepts Swarm match context")
	check(manager.active_player().bus=="Music","Music playback routes through Music bus")
	generation=manager.transition_generation
	check(not manager.request_track(&"missing_test_track")
		and manager.current_track_id==MusicTrackRegistry.SWARM
		and manager.transition_generation==generation,"Missing track fails gracefully and preserves playback")
	var path:="user://hexfront_music_test_%d.cfg" % Time.get_ticks_usec()
	var saved:=UserSettings.new()
	saved.storage_path=path
	saved.music_volume_db=-17.0
	check(saved.save_to_disk()==OK,"Music volume saves")
	var loaded:=UserSettings.new()
	loaded.storage_path=path
	loaded.load_from_disk()
	check(loaded.music_volume_db==-17.0,"Music volume persists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	manager.free()
	print("Music checks complete; failures=",failures)
	quit(0 if failures==0 else 1)
