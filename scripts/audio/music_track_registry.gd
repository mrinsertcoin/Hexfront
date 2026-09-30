class_name MusicTrackRegistry
extends RefCounted
## Canonical music IDs and stable runtime asset paths.

const TITLE: StringName = &"title"
const SWARM: StringName = &"swarm"
const BUILDERS: StringName = &"builders"

const TRACK_PATHS := {
	TITLE: "res://assets/audio/music/title/the_uncharted_atlas.ogg",
	SWARM: "res://assets/audio/music/factions/swarm/cycles_of_the_canopy.ogg",
	BUILDERS: "res://assets/audio/music/factions/builders/weight_of_the_foundation.ogg",
}

# Stable content music IDs resolve here; display-name aliases remain compatible.
const FACTION_TRACKS := {
	"swarm": SWARM,
	"builders": BUILDERS,
	"blue": SWARM,
	"red": BUILDERS,
	"Blue": SWARM,
	"Swarm": SWARM,
	"Red": BUILDERS,
	"Builders": BUILDERS,
}

static func path_for(track_id: StringName) -> String:
	return TRACK_PATHS.get(track_id, "")

static func track_for_faction(faction_id: String) -> StringName:
	return FACTION_TRACKS.get(faction_id, &"")

static func load_stream(track_id: StringName,warn_if_missing: bool = true) -> AudioStream:
	var path:=path_for(track_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		if warn_if_missing: push_warning("Music track is unavailable: %s (%s)" % [track_id,path])
		return null
	var stream:=load(path) as AudioStream
	if stream==null:
		if warn_if_missing: push_warning("Music resource could not be loaded: "+path)
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop=true
	return stream
