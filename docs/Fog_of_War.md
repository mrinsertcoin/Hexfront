# Fog of War, Reconnaissance, and Intelligence

Milestone 17 separates complete simulation state from what a team is allowed to know. `GameState` remains authoritative. Its `VisibilitySystem` derives one persistent `VisibilityState` per team, and consumers receive detached `TeamObservation` snapshots. The board and player AI use those snapshots for enemy entities, contacts, and sites; action rules validate against the same visibility state.

## Visibility and teams

Each logical cell is `UNEXPLORED`, `EXPLORED`, or `VISIBLE`. Current vision is rebuilt after relevant authoritative changes; explored bits persist. Masks are packed byte arrays indexed by `PlanetGrid` cell ID, so a Medium planet uses a compact contiguous representation and does not create cell Nodes. Vision uses deterministic graph distance, including pentagons and polar cells. Terrain elevation does not currently obstruct sight.

`ControllerState.team_id` is separate from faction identity. Player controllers with the same team ID contribute sources to one shared observation and are allied for the fixed match. Diplomacy and mid-match team changes remain deferred.

Units and structures provide content-driven `vision_range` and `detection_range`. Current provisional defaults are unit vision 2/detection 0 and structure vision 3/detection 1. Recon overrides are:

| Unit | Vision | Detection |
|---|---:|---:|
| Prototype Scout | 3 | 2 |
| Scout Trike | 4 | 3 |
| Trike Commander | 3 | 1 |
| Mosquito | 4 | 1 |
| Dragonfly | 3 | 1 |
| Mite | 2 (default) | 2 |

These are initial integration values rather than final faction balance.

## Observation boundary and contacts

`TeamObservation` contains copied visibility masks, copied current entity records, copied site records, historical contacts, and permitted discovery/loss event IDs. It exposes no live `Unit`, `Structure`, `PlayerState`, or `WorldSiteState` reference. Entity records contain only currently observed tactical fields. They omit private resources, research, production, and intended movement.

When a hostile or neutral entity leaves observation, `KnownContact` stores its last observed definition, cell, round, turn serial, and detached snapshot. Hidden movement, HP changes, status changes, transformation, and death never update that record. Rediscovery replaces it with a current observation. Observing its old cell empty invalidates the location. A contact is historical intelligence and cannot be attacked as an entity.

Discovered sites remain on the map using their last observed state. Their hidden charge, regeneration, exploration, ownership, and other runtime changes do not update panels until the site is visible again. Guessed undiscovered site IDs return no interaction options, and every interaction still requires current observation and the normal adjacency/action checks.

## Detection and explicit reveal

Ordinary vision reveals ordinary entities. A concealed entity also needs detection at its cell. Every vision source detects adjacent cells, while authored positive detection range acts continuously within that graph radius. `content_dev/units/concealed_test_unit.tres` validates the shared path without granting stealth to a production faction.

An attack reveals its attacker to the target team through the following turn serial. Living Migration Tracking uses the real `DiseaseState`: the infected entity and its one-cell neighborhood remain visible to the source controller's team, follow movement, and disappear when the disease expires. Explored knowledge remains. Baumeister designation still grants only its bounded damage bonus and requires a visible target; it does not grant global sight. Scout Trike vision can spot for a deployed Long Range Tank through team-shared observation. Direct artillery attacks require a currently observed entity, and blind fire remains deferred.

## Combat, movement, AI, and world population

Combat target enumeration and validation reject unobserved IDs. Hidden targets therefore create no target highlights. Movement into unexplored cells remains legal. Preview pathfinding uses known allied and observed blockers, so it cannot disclose hidden units or undiscovered blocking sites. Execution checks the authoritative route and returns a generic obstruction message without identifying the hidden blocker.

Player AI reads current enemies, sites, and headquarters from `TeamObservation`. It may use its own units and economy from authoritative state, investigate last-known headquarters, and deterministically move toward the nearest unexplored frontier. Adversarial tests verify that changing a hidden enemy's position and HP cannot alter the chosen action. AI and human commands use the same rules. Neutral AI remains authoritative but considers targets only inside each unit's authored awareness and leash; combat validates that awareness.

Wildlife, predators, guardians, structures, and normal units share the entity observation path. Deterministic generation does not imply discovery. Trade posts, deposits, vents, groves, and ruins use the site observation path, and guardian composition is not present in a hidden site record.

## Rendering and interface

`FogOfWarOverlay` rebuilds one displaced spherical `ArrayMesh` only when an observation revision changes. Visible cells have no overlay. Explored cells receive a translucent dark, desaturated layer; unexplored cells receive an almost opaque dark layer. The mesh samples `TerrainSurfaceSampler`, so it follows the rendered globe at tactical, regional, and whole-planet zoom. It creates one mesh node and no per-cell materials or scene nodes.

`WorldDressing` keeps original deterministic MultiMesh transforms and zero-scales instances only in unexplored cells. It does not rebuild asset batches. Entity roots are disabled when absent from the observation, which also hides models, health bars, ownership rings, labels, animation, selection, and hover geometry. A separate subdued ring and question marker renders last-known contacts.

Selection filters authoritative hits through the active observation. If a selected enemy leaves sight, the panel switches to historical type, cell, and last-seen round without live HP or actions. Spot/contact/site notifications come from observation revisions. AI and neutral execution use generic activity feedback rather than hidden action results. A hotseat team switch clears selection, input modes, target overlays, and notifications, then covers the view with an opaque handoff screen until the incoming player accepts it.

F10 explicitly toggles omniscient development rendering and labels the mode. F1–F9 retain the existing map, terrain, camera, and population diagnostics. Omniscience changes presentation only and never changes authoritative visibility or AI input.

## Performance and validation

Visibility is event-driven through `GameRules` commits, population changes, status/turn processing, and match reset. Camera motion never recalculates it. A representative 48-unit benchmark measured 6.5 ms on Small (2,562 cells) and 7.5 ms on Medium (10,242 cells) on the development machine. Cached displaced fog geometry is built once with the scene; subsequent Compatibility-renderer color/mesh revisions measured 103.1 ms on Small and 101.7 ms on Medium on the RX 590 baseline. Ordinary frames reuse that mesh without visibility work.

`tests/visibility.gd` covers state transitions, team sharing, pentagons and multiple topology sizes, source movement/removal, immutable contacts, hidden death, rediscovery/invalidation, concealment, detection, Tracking, attack reveal, allied artillery spotting, unknown blockers, site memory, neutral discovery, AI information invariance, and Small/Medium processing. `tests/visibility_graphical.gd` captures fresh, partial, explored, current-contact, historical-contact, Tracking/recon/site/neutral, whole-planet, and hotseat-handoff views for Small and Medium.

The current sight model intentionally uses graph radius without terrain line of sight. It has no camouflage terrain, weather visibility, blind fire, false or misidentified contacts, espionage, diplomacy, or Veilkin mechanics. A future false-contact implementation should add perceived contact records to the observation layer and leave authoritative entities in `GameState`; presentation and AI must continue consuming observations rather than resolving those records back to hidden live entities.
