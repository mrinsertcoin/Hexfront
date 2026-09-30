# World Population

Milestone 16 adds a deterministic logical layer above `GeneratedPlanet`. The planet remains immutable terrain/climate/hydrology data; `WorldPopulationResult` separately records sites, neutral groups, version, world/config fingerprints, and generation time. Runtime depletion, exploration, trade usage, damage, and movement live only in `GameState`.

## Generation contract

`WorldPopulationConfig.VERSION` is 2. Match setup exposes Off, Sparse, Standard, and Dense; Standard is the normal default. Density is specified per 1,000 topology cells and bounded by category caps, so Small and Medium planets scale without unbounded entity counts. Explicit site IDs/counts remain available for authoring tests.

Generation derives independent SHA-256 sub-seeds from the world seed and semantic streams:

- `trade_posts`
- `resource_sites`
- `ruins`
- `neutral_wildlife/<group_id>`
- site guardians, derived from a site's authored guardian group

Changing neutral density cannot perturb site placement. Candidates reject surface water, use continuous fertility/moisture/roughness and biome affinities, respect graph-distance start safety and spacing, and distribute trade posts and ruins across regions while unused regions remain available. Restart reapplies the same result and resets runtime state. Regenerating with another world seed creates a new population result and fingerprint.

## Content model

All production content is loaded by `ContentRegistry` and referenced by stable IDs.

`WorldSiteDefinition` provides category, interaction type, movement blocking, trade recipes, rewards, charge/regeneration policy, optional removal on exhaustion, guardian group, tags, icon, and visual ID. Current site categories are trade, resource, ruin, and landmark.

`TradeRecipeDefinition` owns a fixed input/output exchange, optional faction allow-list, and a per-site/per-player/per-round usage limit. Registry validation checks all resources and factions. A recipe is shown only when every input and output belongs to the active faction's resource model.

`NeutralGroupDefinition` owns composition, relationship policy, biome affinities, awareness, leash, difficulty, and site-guardian behavior. Neutral members are normal `UnitDefinition` and `GameState.Unit` instances. Current reusable units are Wild Grazer, Wild Predator, and Stone Guardian.

To add a site:

1. Create a `.tres` using `scripts/content/world_site_definition.gd` under `content/world_sites`.
2. Give it a unique lowercase ID and choose a generic category/interaction.
3. For trade, add one or more `TradeRecipeDefinition` resources under `content/trade_recipes` and reference their IDs.
4. For gather, author positive rewards and charges; set `regeneration_turns` for renewable sites.
5. For ruins, author deterministic resource/research rewards and optionally a guardian group ID.
6. Run `tests/content_foundation.gd` and `tests/world_population.gd`; broken references fail validation.

To add a neutral group, create its normal unit definitions first, then a `NeutralGroupDefinition` under `content/neutral_groups`. Use `composition` for counts, set `relationship_policy` to neutral or hostile, and keep awareness/leash bounded. Setting `site_guardian` keeps it out of free wildlife generation and lets sites spawn it explicitly.

## Runtime rules

`SiteRules` is the only mutation boundary for trade, gather, and explore. It reports available interactions and exact rejection reasons before applying a command. A unit must be owned, adjacent, alive, and have an action available. A successful interaction spends that unit's move/attack action.

Trade applies authored resource deltas exactly once and records bounded usage. Deposits decrement charges; finite sites remain exhausted or may be removed according to content, while renewable sites recover after their authored round interval. Ruins are globally explored once and cannot reroll. Rewards are filtered through the acting faction's resource IDs, and research reward applies to the active project.

Neutral controllers do not become fake players. Central relationships decide whether each group is neutral or hostile. After every player has ended their turn, `TurnState` enters one explicit neutral phase. `NeutralAI` considers each unit once, obeys awareness and leash limits, and emits at most one attack or movement action per unit through normal `GameRules`. Combat, death, corpse creation, occupancy, and presentation therefore use the existing unit systems.

The normal AI may use a beneficial adjacent site but does not path away from its tactical objective to find one.

## Presentation and diagnostics

Sites have category-colored surface markers and a floating symbol; neutral units use distinct peaceful/hostile accents. Selecting a site shows category, state, charges/exploration, costs/rewards, exact disabled reasons, and a cyan interaction overlay. Notifications report completed and rejected interactions. During the neutral phase the top bar reads **Neutral activity** and End Turn is disabled.

F6 shows the population preset, generation version, site/group counts, build time, and fingerprint alongside world diagnostics. F9 labels site definitions and cells on the planet.

## Verification

`tests/world_population.gd` covers content validity, presets, deterministic records, independent streams, start safety, faction-compatible trades, exact deltas and limits, finite/renewable resources, global ruins, normal neutral units, relationships, bounded AI, and phase order. `tests/world_population_graphical.gd` captures site selection, neutral presentation, and diagnostics, and verifies restart identity. The full headless suite remains the release regression gate.

On the Milestone 16 reference run (Godot 4.6.2, Ryzen-class desktop), Standard population generation took about **1.04 s for Small** (2,562 cells, 49 sites, 36 groups including guardians) and **4.93 s for Medium** (10,242 cells, capped at 60 sites, 52 groups including guardians). Placement ranks linear candidate lists and uses bounded cached graph traversals; it does not allocate an all-pairs distance table.

Fog of war, diplomacy, roaming economies, quests, save/load, and advanced strategic AI remain later systems. The definitions and runtime state use stable IDs and serializable dictionaries so those systems can extend this layer without replacing it.
