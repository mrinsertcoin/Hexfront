# Milestone 21: Living Migration, simultaneous combat, and tactical HUD

## Living Migration lifecycle

- An accepted ordinary Worker Ant movement adds every reached land cell in its authoritative path to the existing `LivingMigrationState.roads` set. Spawns, displacement, interpolation, rejected moves, and water cells do not add roads. The former manual road command remains protocol-compatible but is deprecated and absent from the HUD.
- Dragonflies and Mosquitos may lay a larva on a hydrology-classified water cell at range 1. Larvae mature after 5 rounds. Their immutable result is derived from match seed, owner, species, cell, creation round, and larva ID: 25% emerge and 75% are removed. A successful blocked larva remains ready and retries without rerolling.
- Caterpillars must explicitly consume fresh vegetation or an unconsumed corpse. Vegetation grants `Food 4 / Matter 0`; corpses grant `Food 0 / Matter 4`. Consumption begins a 5-round transformation countdown.
- Provisional Alpha transformation recipes are content resources: Brimstone Butterfly requires Food 4; Fire Moth requires Food 2 + Matter 2; Admiral requires Matter 4 and has a one-per-player hero limit. Existing `lm_metamorphosis` and `lm_apex_metamorphosis` restrictions remain authoritative.

## Combat architecture and extension API

During the simultaneous player stage, every living human may revise one `CombatIntent` per eligible unit: Attack, Dodge, Counter, or no order. Ending movement independently finalizes that player's choices. After the final living human ends movement, `TurnState` enters automatic `combat_resolution`; empty combat is skipped and non-empty combat resolves from one shared position/HP snapshot, allowing mutual kills. Eliminated players are excluded.

New options are authored as `CombatOptionDefinition` resources. A future option should add its resource/capabilities and a focused resolver interaction; phase sequencing and HUD submission use stable option IDs and do not require a UI enum.

Provisional Alpha values:

- Dodge reduces every incoming hit by 2.
- Counter reduces the first eligible incoming hit by 2, retaliates for 2, has one trigger per resolution, and starts a 2-round cooldown only when triggered.

Commands `combat_intent` and `clear_combat_intent` are accepted while the authenticated player remains actionable in the shared movement stage. `end_turn` marks that player ready and automatically triggers host-authoritative resolution after the last living human. Observations expose only the recipient's own queued intents and public outcomes.

## HUD management workflow

The top bar is definition-driven and shows icon/current/income/upkeep/net resource chips plus a research book control. Research is a non-pausing overlay. The bottom-left contextual panel includes an isolated rotating `SubViewport` model preview and unit/city details. The bottom-right area contains a fog-aware equirectangular minimap and per-turn `Next Unit` / `Manage Cities` queues.

The flow is: enemy activity, simultaneous human planning, then shared combat. During planning, exhaust or skip unit/city queues, select research when needed, queue or revise combat orders, then `End Movement Phase`. There is no separate combat confirmation. Units without an order take no combat action. Queue review state is local UI state and resets each round.

The minimap draws explored/visible terrain, own and currently observed contacts, discovered sites, player colors, and camera focus from `TeamObservation`. Clicking converts through the same equirectangular projection and focuses the surface camera, including across the longitude seam.
