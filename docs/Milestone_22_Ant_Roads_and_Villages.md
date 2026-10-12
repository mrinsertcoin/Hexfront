# Milestone 22: Painted Ant Roads and Neutral Villages

## Painted Ant roads

Ant-road gameplay remains authoritative in `LivingMigrationState.roads`; accepted Worker Ant movement is still the only normal way to extend it. `AntRoadOverlay` is presentation-only and uses the supplied dirt texture:

- `res://assets/factions/swarm/structs/ant road/source/ant_road.png.png`

Each road cell builds a small junction and narrow 0.16-unit paths to shared edge midpoints, forming a continuous network with same-owner neighbors. Strips are sampled every 0.12 world units and placed against the actual rendered terrain mesh, only 0.01 units above it. A subdued wider edge sits underneath each path; full-tile dirt patches and perimeter twig borders are removed. Meshes do not cast shadows. `PlanetGrid.neighbor_across_edge()` handles pentagons and hexagons identically. Changes rebuild only the affected cell and neighbors. Connection remains a separate rules query; its full-cell tint appears only in road/supply modes so it does not obscure the paths during normal play.

## Village generation and allegiance

`village` is a normal `WorldSiteDefinition` using `res://assets/neutral/village/tile/source/village_tile.glb`. Its imported bounds are fitted to the selected cell's full tangent-plane footprint, with source centering and ground-origin correction. The definition's scale multiplier is 1.0. Villages are included in world-dressing exclusions so new matches clear vegetation around their footprint.

`MatchConfig.villages_per_player` accepts 0–4 and defaults to 2. Villages use the independent `world_population/.../villages` deterministic stream. Candidates must be dry, moderately sloped land outside player-start exclusions and the configured seven-cell village spacing. The target is players multiplied by the setting; genuine placement constraints may produce fewer.

Every village creates two seven-member Villager squads and exactly one Knight of the Land on deterministic legal nearby cells. Both use the supplied models under `assets/neutral/village/`, with grounded visual profiles and imported mesh LODs. Original geometry is preserved; textures use GPU compression with a 1024-pixel import limit. Seven members occupy distinct centre-plus-six formation positions.

All use neutral controller 53 and allegiance `free_villages`, making village defenders mutually friendly. Each defender's home is its own village, with a strict five-cell graph radius. AI destinations and authoritative movement paths enforce it, including intermediate detour steps and after the village is destroyed. Hostility remains scoped per player and home-site ID; attacking one village does not provoke every village. Production village sites only spawn on flat terrace tiles.

## Provisional Alpha values

| Content | HP | Move | Range | Damage | Notes |
|---|---:|---:|---:|---:|---|
| Village | 24 | — | — | — | Destructible site |
| Villager | 5 | 1 | 1 | 2 | Two squads per village; seven members per squad |
| Knight of the Land | 16 | 2 | 1 | 5 | Exactly one per village |

Villages offer the existing faction-compatible recipes `food_for_silk` and `materials_for_energy`, each subject to its authored once-per-turn usage limit. A hostile or destroyed village cannot trade.

Destruction exposes one global loot claim. The content table contains Food 8, Silk 4, Materials 8, Energy 4, filtered to resources usable by the claiming faction, plus 3 research progress when a technology is active. Claiming is authoritative, marks the cache permanently claimed, and spends the interacting unit's action. Living defenders remain active after destruction.

## Visibility, UI, and networking

Village sites use normal discovery memory; live defenders require current visibility. The minimap colors villages green when neutral, red when hostile to the viewer, and gray when destroyed. The bottom-left site panel reuses normal model preview, HP/state, allegiance, observed guard information, trade, and loot controls. Attacks use the existing attack/combat-intent command with a site target ID; trade and loot use the existing authoritative site-interaction command. Protocol, gameplay-data, and observation schema versions are bumped for the new fields.

`tests/milestone22.gd` covers painted-road topology/local refresh/spherical geometry, deterministic generation and settings, terrain/spacing/start rules, guardian composition, scoped allegiance and AI response, trade, destruction, single-claim loot, fog filtering, and command authority.

`tests/overlay_ux.gd` additionally verifies full-tile village fit and the road offset against the rendered terrain. Run it without `--headless` to capture village/path views and unit/Spider overlays at 720p, 1080p and 1440p.

`tests/village_flatlands.gd` checks size-scaled flat land, flat-only village spawning, five-cell movement/AI leashes and seven distinct formation positions. `tests/village_defenders_graphical.gd` captures the supplied character models, their previews and the village overview. `tools/inspect_village_models.gd` reports bounds, source triangle counts and actual imported LOD sizes.
