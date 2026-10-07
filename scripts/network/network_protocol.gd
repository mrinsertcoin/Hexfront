class_name NetworkProtocol
extends RefCounted
## Stable compatibility contract for multiplayer messages.

const NETWORK_PROTOCOL_VERSION:=3
const GAME_BUILD_VERSION:="0.2.0-m21-dev"
const GAMEPLAY_DATA_VERSION:=4
const SNAPSHOT_SCHEMA_VERSION:=4
const DEFAULT_PORT:=24567
const MAX_PLAYERS:=4
const MIN_PLAYERS:=2
const MULTIPLAYER_FACTIONS: PackedStringArray=["living_migration","baumeister"]
const CONNECTION_TIMEOUT_SECONDS:=10.0
const LOADING_TIMEOUT_SECONDS:=30.0

static func handshake(registry: ContentRegistry=ContentRegistry.default()) -> Dictionary:
	return {
		"protocol_version":NETWORK_PROTOCOL_VERSION,
		"build_version":GAME_BUILD_VERSION,
		"gameplay_data_version":GAMEPLAY_DATA_VERSION,
		"content_fingerprint":registry.fingerprint,
	}

static func compatibility_error(candidate: Dictionary,registry: ContentRegistry=ContentRegistry.default()) -> String:
	if int(candidate.get("protocol_version",-1))!=NETWORK_PROTOCOL_VERSION:
		return "Network protocol versions do not match."
	if String(candidate.get("build_version",""))!=GAME_BUILD_VERSION:
		return "Game build versions do not match."
	if int(candidate.get("gameplay_data_version",-1))!=GAMEPLAY_DATA_VERSION:
		return "Gameplay data versions do not match."
	if String(candidate.get("content_fingerprint",""))!=registry.fingerprint:
		return "Gameplay content does not match the host."
	return ""

static func valid_port(value: int) -> bool: return value>0 and value<=65535

static func clean_player_name(value: String) -> String:
	var cleaned:=value.strip_edges()
	if cleaned.length()>24: cleaned=cleaned.left(24)
	return cleaned
