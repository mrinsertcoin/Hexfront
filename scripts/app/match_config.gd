class_name MatchConfig
extends Resource
## Immutable-in-practice setup for one match. User preferences live elsewhere.

enum PlanetSize { DEV_TINY, SMALL, MEDIUM }

const SIZE_DEFINITIONS := {
	PlanetSize.DEV_TINY: {"name": "Dev / Tiny", "subdivision": 3, "radius": 12.0, "cells": 642},
	PlanetSize.SMALL: {"name": "Small", "subdivision": 4, "radius": 24.0, "cells": 2562},
	PlanetSize.MEDIUM: {"name": "Medium", "subdivision": 5, "radius": 48.0, "cells": 10242},
}

@export var world_seed: int = 48293617
@export var planet_size: PlanetSize = PlanetSize.SMALL
@export var player_faction: String = "Blue"
@export var opponent_faction: String = "Red"
@export_enum("Human", "AI") var opponent_controller: String = "AI"
@export var ai_difficulty: String = "Standard"

static func normal_planet_sizes() -> Array[PlanetSize]:
	return [PlanetSize.SMALL, PlanetSize.MEDIUM]

func size_definition() -> Dictionary:
	return SIZE_DEFINITIONS.get(planet_size, SIZE_DEFINITIONS[PlanetSize.SMALL])

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not SIZE_DEFINITIONS.has(planet_size): errors.append("Choose a valid planet size.")
	if player_faction not in ["Blue", "Red"]: errors.append("Choose a valid player faction.")
	if opponent_faction not in ["Blue", "Red"]: errors.append("Choose a valid opponent faction.")
	if player_faction == opponent_faction: errors.append("Player and opponent must use different factions.")
	if opponent_controller not in ["Human", "AI"]: errors.append("Choose a valid opponent controller.")
	if ai_difficulty != "Standard": errors.append("Choose a supported AI difficulty.")
	return errors

func copy() -> MatchConfig:
	var result := MatchConfig.new()
	result.world_seed = world_seed
	result.planet_size = planet_size
	result.player_faction = player_faction
	result.opponent_faction = opponent_faction
	result.opponent_controller = opponent_controller
	result.ai_difficulty = ai_difficulty
	return result
