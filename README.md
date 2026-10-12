# Hexfront

Godot **4.6.2 standard**, typed GDScript, **Compatibility** renderer. Milestones **8D–21A** provide displaced terrain, deterministic world dressing, a surface-relative tactical camera, a persistent frontend, data-driven gameplay content, two complete asymmetric Alpha factions, world population, team-shared spherical fog of war, host-authoritative 2–4 player free-for-all multiplayer, and the first static Living Migration model set. Gameplay still uses the stable hex/pentagon cell graph.

The default planet is mostly land. Five replaceable placeholder material layers demonstrate the PBR pipeline; final scanned textures and vegetation are future work. Terrain changes presentation only: movement, combat, recruitment, AI, economy, and victory retain their existing rules.

## Run and controls

Open `project.godot` in Godot 4.6.2 and press **F5**, or run:

```powershell
$godotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
& $godotExecutable --path .
```

The project opens at the Main Menu. **New Game** configures factions, Human/AI control, planet size, and seed before creating the match. Small (2,562 cells) is the default; Medium has 10,242 cells. **Escape** opens Pause during play, with Resume, shared Options, Main Menu, and desktop exit.

One application-level [`MusicManager`](scripts/audio/music_manager.gd) plays The Uncharted Atlas throughout frontend navigation and crossfades over two seconds to the configured local faction theme when a match starts. Current `Blue` and `Red` faction identities map to the Swarm and Builders themes through [`MusicTrackRegistry`](scripts/audio/music_track_registry.gd). Pause and pause-options leave match music continuous; returning to Main Menu restores the title theme. Master and Music volume use separate buses and persist in `user://hexfront.cfg`.

- **Left click/release:** select a cell, unit or HQ; entities smoothly focus and link follow. **Left drag:** grab the terrain and pan (five-pixel threshold). Click empty background or press **Escape** to clear selection.
- **Right click:** move to a green cell, or attack a purple enemy target. Hover previews the cyan shortest path or damage, remaining HP and lethality.
- **HQ recruitment:** select your HQ, choose a unit, then left-click a green adjacent cell. Right-click/Escape cancels without spending.
- **WASD / arrows:** camera-relative surface pan. **Q/E:** local yaw. **Middle drag:** local yaw/pitch. All hemispheres and poles are reachable.
- **Wheel:** zoom between close tactical, regional, and whole-planet views. Zoom and terrain clearance use the displaced surface; planet framing scales with radius and FOV.
- **F:** focus and follow the selected unit/HQ; manual navigation breaks follow. **Home:** reset to your initial Player 1 HQ view.
- **F1:** strong debug cell outlines (hidden by default). **F2:** orange pentagon outlines. **F3:** cell centers. **F4:** cell IDs / neighbor counts. Pentagon markings are debug-only and off by default; labels are created only when requested.
- **F6:** procedural-world panel with seed controls, summary, debug-view selector, and selected/hovered-cell diagnostics. **F7:** cycle base fields, biomes, strategic regions, flow direction, accumulation, drainage basins, lakes, rivers, hydrology moisture, and wetland potential.
- **F8:** toggle camera diagnostics.
- **End Movement Phase:** finish movement, management, and queued combat choices. After every living player finishes, queued orders resolve automatically and empty combat is skipped. Disabled during movement, AI work, and after victory.
- **R / P:** open Research or focus the selected entity's production/context actions. **Tab / Shift+Tab:** cycle active units. **Enter:** mark your movement planning ready.
- **Targeting modes:** road, Pillar/bridge, heal, repair, designate, and recruitment show distinct legal-cell overlays. Right-click or **Escape** cancels the mode before Escape opens Pause.
- **Restart:** shown after victory. Restores initial units, HP, actions, economy, selection and camera, retaining the match mode and the same cached topology. Mode buttons also start a new match.

Gold marks selection, green movement/recruitment, cyan paths, purple attacks, and gray hover. Blue/red rings mark ownership. Health bars are world geometry and are occluded by the planet. HUD controls consume their clicks; pan to expose areas covered by the HUD.

## Globe architecture

`GameState` and `GameRules` own gameplay. Rendering nodes do not determine occupancy, legality, damage, income or victory. Units and structures store an integer `cell_id`; no axial coordinates or rectangular bounds participate in gameplay. The unused flat-grid implementation was removed.

- [`PlanetGrid`](scripts/core/planet_grid.gd) starts with a regular icosahedron, subdivides each triangle into four, deduplicates shared edge midpoints, and normalizes vertices onto the unit sphere.
- Each icosphere vertex becomes a [`PlanetCell`](scripts/core/planet_cell.gd). Incident triangle centroids, normalized to the radius, form its dual polygon. Exactly **12 cells are pentagons with five neighbors**; every other cell has six neighbors and six corners.
- Polygons are **counterclockwise viewed from outside**, with outward cross products. Rendering reverses triangle winding for Godot's clockwise front faces. This centroid dual is not an exact Voronoi diagram; picking checks actual polygon containment after nearest-center lookup.
- Cell IDs follow fixed base vertex/face order and deterministic midpoint insertion. Neighbor IDs are sorted numerically. ID generation never uses scene-tree order, instance IDs or dictionary iteration order.
- `center_direction`, `center_world_position`, polygon corners, neighbor IDs and a right-handed tangent frame are generated once. The tangent basis chooses the least-aligned Cartesian reference axis to avoid polar singularities.
- `breadth_first`, `find_path`, `get_graph_distance`/`distance`, and `get_cells_within_distance` centralize graph traversal. Range counts graph edges. Movement passes occupancy blockers into the same bounded BFS used by preview and validation. Distance caches are bounded to 128 source rows.
- [`PlanetTerrainRenderer`](scripts/view/planet_terrain_renderer.gd) renders 20 continuous terrain face chunks with shared seam positions and normals. [`PlanetSurface`](scripts/view/planet_surface.gd) builds curved, slightly offset overlay meshes only when needed and caches them; debug outlines/centers use merged meshes. There are no per-cell collision bodies.
- Picking queries a cached physics-free triangle BVH of the displaced terrain, then resolves the original cell polygons. Zero displacement retains exact sphere picking; no per-cell or per-triangle collision objects are created. Hover recomputes as the camera moves, including without selection.
- [`EntityView`](scripts/view/entity_view.gd) follows the accepted `Array[int]` path with spherical interpolation. Orientation parallel-transports and smoothly turns the heading while keeping local up radial. Long frames consume each waypoint in order. `TerrainSurfaceSampler.sample_position(direction, offset)` now supplies displaced terrain height for movement, structures, selection overlays, grid lines, and labels. In-place rig animation remains separate from displacement.

The terrain mesh is presentation, independent of logical cell polygons. [`GeneratedPlanet`](scripts/world/generated_planet.gd) owns a frozen configuration snapshot, per-cell generated records, region metadata, continuous samplers, validation results, and a deterministic fingerprint. [`PlanetFieldSampler`](scripts/world/planet_field_sampler.gd) samples explicit-seed `FastNoiseLite` layers in normalized 3D direction space, so generation has no longitude seam or scene-tree dependency. Gameplay reads none of these values yet.

## Gameplay content foundation

[`ContentRegistry`](scripts/content/content_registry.gd) discovers sorted typed definitions under `content/`, validates their stable lowercase IDs and references, and produces a gameplay-only fingerprint. Units, structures, factions, resources, technologies, neutral groups, modifiers, and world sites resolve through this registry. Prototype Blue and Red content retains the prior balance while runtime entities store definition and controller IDs suitable for later serialization.

[`PlayerState`](scripts/core/player_state.gd) owns resources and research. Controller and relationship state distinguishes human, player-AI, neutral-AI, and world identities and supports self, allied, neutral, and hostile relationships. Movement, combat, recruitment, research, and site rules sit behind the existing `GameRules` facade; combat and AI now consult relationships, and all occupancy uses one query covering units, structures, and blocking sites.

The deterministic world-population layer can create logical site records after planet generation, using its own version and semantic seed streams. It is disabled in production matches. The authored `trade_post` proves the generic site path without adding trade mechanics, and development-only technology and neutral-group examples remain under `content_dev/`. See [content authoring](docs/Content_Authoring.md) for exact schemas and locations.

The selectable **Living Migration** faction uses Food, Silk, and Synapse; mobile Spider headquarters; internal nursery production; terrain consumption and regrowth; ant roads and Connection; finite-lifetime marsh creatures; nutrient-driven caterpillar transformation; and three temporary mite diseases. Its values are visible, data-driven development defaults. See [Milestone 14A](docs/Milestone_14A_Living_Migration.md) for the source-defined rules, provisional tuning, controls, and deferred mechanics.

The selectable **Baumeister** faction uses Food, Materials, Energy, and Unity to build local-Integrity Pillar Cities, owned districts, and damageable bridge supply networks. It includes weighted bridge movement, specialized biological/vehicle support, deployable artillery, target designation, and a legal development AI. See [Milestone 14B](docs/Milestone_14B_Baumeister.md).

The [Alpha 0.1 balance report](docs/Balance_Alpha01.md) is generated from the current content definitions. Living Migration now has a [15-node prerequisite research root system](docs/Living_Research_Roots.md); Baumeister retains 10 technologies. Faction upgrades affect their authored mechanics, and unpaid unit/district upkeep suspends production until recovery. The deterministic comparison records opening production, military, research, expansion, and representative army costs without treating the result as an automated balance verdict.

The [model inventory](docs/Model_Inventory.md) maps 11 Living Migration roster entries to imported textured GLBs through presentation-only visual profiles. Four roster entries without clear source models keep their generated placeholders. The inventory records exact mappings, transforms, rig/animation status, triangle and texture costs, and the repeatable graphical gallery workflow.

The in-match [strategic interface](docs/Strategic_UI.md) presents faction-defined resources, authoritative production reasons, a reusable research tree, context actions, Spider/Pillar management, world-site inspection, interaction modes, and focusable notifications. Selected units use a single bottom-left tactical card with an auto-framed rotating model preview, resolved statistics, grouped actions, statuses, and queued simultaneous-combat intent; enemy and last-seen cards expose only permitted observation data. Its state is rebuilt from the current match and is never serialized as gameplay.

Menus, research and city/unit cards share [mythic engraved frames](docs/Mythic_UI_Frames.md): antique-gold root knots, leaves and hex seals, with elaborate page borders and compact tactical borders. Vector ornaments preserve input and layout, and redraw only on resize.

[World population](docs/World_Population.md) is a separately versioned deterministic layer over the generated planet. Match setup offers Off/Sparse/Standard/Dense density; Standard places region-aware trade posts, finite and renewable resource sites, one-shot guarded ruins, peaceful grazers, hostile predators, and ruin guardians outside safe starts. Generic site rules provide faction-compatible fixed trade, gathering, and exploration. Every round runs enemy activity (neutral units, then player AI), simultaneous human planning, and shared combat resolution.

[Painted Ant roads and neutral villages](docs/Milestone_22_Ant_Roads_and_Villages.md) add topology-derived dirt/border overlays plus configurable deterministic single-tile villages with shared-allegiance defenders, peaceful faction-compatible trade, scoped hostility, destruction, and one-time loot.

[Fog of war](docs/Fog_of_War.md) derives packed unexplored/explored/visible masks, detached current observations, immutable last-known contacts, site memory, concealment detection, Tracking reveal, and team-shared spotting from authoritative state. The spherical overlay, entity/site filtering, hotseat privacy handoff, and player AI all consume the same permitted observation.

[Multiplayer](docs/Multiplayer_Architecture.md) adds a configurable ENet host/join flow, a four-player-ready peer/player registry and development lobby, compatibility handshakes, exact-once primitive commands, host-only simulation, private population seeding, per-recipient observation snapshots, revision/resynchronization handling, and predictable disconnect cleanup. Two-player localhost integration launches independent Godot processes; the document includes the separate two-computer Windows procedure and current development-client limitations.

[Four-player free-for-all](docs/Multiplayer_FFA.md) upgrades that flow to synchronized 2–4 player capacity, Living Migration/Baumeister duplicate faction selection, independent ownership colors and fog, graph-spaced faction-aware starts, simultaneous human turns, explicit elimination/victory, deterministic disconnect removal, and a real four-process localhost regression.

Height combines continent, regional, and detail scales plus explicit sphere-space domain warp. Temperature combines latitude, coherent noise, and elevation cooling. Moisture is coherent 3D noise; fertility combines temperature, moisture, height, and local variation; terrain roughness measures a dedicated coherent field. Five data-defined [`BiomeDefinition`](scripts/world/biome_definition.gd) resources score those fields continuously, and every cell retains normalized weights alongside its dominant biome. Regions grow deterministically across grid adjacency from farthest-point seeds; undersized regions merge by shared border and stable tie-breaks, then cache aggregate field and biome values.

[`PlanetHydrology`](scripts/world/planet_hydrology.gd) derives raw downhill flow and preliminary catchments from `neighbor_ids`, including five-neighbor pentagons. A deterministic graph priority flood then resolves depressions into an acyclic final drainage tree. Ocean cells are flood roots when enabled; the default mostly-land configuration uses the global low point as an intentional closed-globe terminal basin. Connected depressions become lakes only when they meet configured depth, area, and normalized-catchment criteria. Oversized depressions remain breached drainage terrain rather than accidental inland seas.

Runoff combines a baseline with base climate moisture. Reverse flood order accumulates every upstream contribution once, and normalized planet-wide accumulation drives size-independent stream, river, and major-river thresholds. Explicit directed [`RiverSegment`](scripts/world/river_segment.gd) records carry accumulation, Strahler order, class, and a future width factor. Lakes and rivers add smoothly decaying moisture without destroying base moisture; effective moisture and wetland potential then feed the existing biome scorer and refreshed strategic-region summaries.

## Configuration and determinism

Select the main scene root and set `subdivision_level`, `planet_radius`, and the [`PlanetGenerationConfig`](scripts/world/planet_generation_config.gd) in the Inspector before starting. Defaults: **subdivision 3, radius 12, topology version 1, world-generation version 1, seed 48293617**. F6 can regenerate the cached world with an entered signed 64-bit seed or choose a random seed once; all subsequent generation remains deterministic. Restart retains the same generated-world object. For subdivision 4, radius 24 preserves approximately the current unit-to-cell scale. Subdivision 5 topology remains supported and tested, while generated-world acceptance covers levels 0 through 4.

| Subdivision | Cells (`10 * 4^n + 2`) | Pentagons |
|---:|---:|---:|
| 0 | 12 | 12 |
| 1 | 42 | 12 |
| 2 | 162 | 12 |
| 3 | 642 | 12 |
| 4 | 2,562 | 12 |
| 5 | 10,242 | 12 |

The grid fingerprint is SHA-256 over topology generation version, subdivision, IDs, sorted neighbors, and center directions quantized to one millionth. Radius is deliberately excluded: changing physical scale does not change logical topology. Default grid fingerprint:

```text
14bf42deb7d2915ab6130a15686f15e2fa3bd09e1e7b92dd76b1d717d8f9a930
```

HQ 1 starts at cell 0; HQ 2 is the last cell in deterministic BFS order from 0, at maximum graph distance. Each side's three units occupy the first three sorted HQ neighbors. All starts are distinct at every supported subdivision. Restart reuses the grid object and restores the exact starting IDs and fingerprint.

World subsystems derive stable SHA-256 sub-seeds from the world seed and semantic labels such as `height` and `moisture`; adding one subsystem does not perturb the others. The generated-world fingerprint covers the serialized config, topology identity, cell values, biome weights, and region assignments. Default world fingerprint:

```text
baba403acade672107d4a49c838a0f2259c3fb8da1a7c7f8b5cde0466ed77162
```

## Continuous terrain and materials

`terrain_config` on the board controls visual subdivision (default **5**, 10,242 vertices / 20,480 triangles), height scale (1.25), center, contrast, exponent, material resolution, normal-map quality, rock exposure, wetness, and water widths. Gameplay subdivision remains independent: both 642-cell/radius-12 and 2,562-cell/radius-24 worlds can use the same terrain tessellation. Set visual subdivision 6 for 81,920 triangles. Call `rebuild_terrain()` after changing visual settings; seed regeneration rebuilds automatically and restart reuses existing geometry.

Terrain vertices sample the canonical generated height field and use `radius + (height^exponent - center) * contrast * height_scale`. Smooth area-weighted normals are calculated after displacement and shared across all chunks. Godot culls the 20 face instances independently. Geometry builds once per world/settings change, with no dynamic LOD or per-frame noise generation.

`GeneratedPlanet.sample_fields()` and `sample_biome_weights()` now continuously interpolate cached hydrology influence over the primal spherical triangles before applying the existing biome scorer. Base climate remains unchanged. This makes wetland transitions and effective moisture agree with cell data while avoiding nearest-cell material boundaries.

[`StylizedTerrainMaterial`](scripts/view/stylized_terrain_material.gd) binds five continuous biome fields to a restrained natural palette. The active shader uses broad color regions, low-frequency object-space variation, real-surface slope rock tint, and hydrology darkening without scanned maps or runtime texture arrays. See [terrain material notes](assets/terrain/README.md).

[`WorldDressing`](scripts/view/world_dressing.gd) composes deterministic forest groves, grassland copses, rock fields, wetland growth, and dryland scrub from continuous environmental fields. Eight reviewed Meshy assets use their explicit tactical, regional, and strategic LODs in 24 bounded MultiMesh batches; planet view hides all props. Each member samples displaced terrain and normals, while opening units and headquarters receive presentation-only clearings. [The runtime catalog](assets/environment/stylized/README.md) records accepted and rejected candidates.

River ribbons follow the authoritative directed segments using constrained spherical Hermite smoothing, dense height samples, hydrology-scaled widths, and overlapping junction patches. Lakes merge logical membership into rounded external contours, triangulate a common authoritative water radius, and add a narrow damp shoreline. Both use opaque restrained water materials for reliable depth occlusion. Water animation and channel carving are deferred; no authoritative height or drainage data is changed.

Normal idle viewing hides the grid. Selection/reachability/path/attack overlays remain translucent and conform to terrain. Units and HQs use host-cell elevation; movement resamples elevation along the accepted spherical route while keeping a stable radial orientation. The surface-relative camera uses this same sampler for focus and clearance, and the terrain BVH for grab dragging.

## Preserved rules

| Unit | HP | Move | Range | Damage | Recruitment cost |
|---|---:|---:|---:|---:|---:|
| Infantry | 10 | 2 | 1 | 3 | 4 |
| Scout | 6 | 3 | 1 | 2 | 3 |
| Gunner | 7 | 1 | 2 | 3 | 5 |

Each side starts with these three units and one 25-HP HQ. A unit can move once and attack once per turn. Moving first permits an attack; attacking spends remaining movement. Each edge costs 1; units and structures block passage. Attacks use graph distance, ignore intervening entities, always hit for fixed damage and never retaliate.

Players start with 8 materials and gain 3 when their shared player stage opens, including the initial round. Turn-start processing is idempotent. Each HQ recruits once per owner round into an adjacent empty cell, including at pentagons. Recruits have full HP and both actions become available in their next player stage.

**Destroy the enemy HQ to win.** Army elimination alone does not win. The AI retains its recruitment, attack and movement priorities and uses the same rules commands. Its actions are bounded per turn and wait for movement presentation.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_all.ps1
# Override an executable path with -GodotExecutable.

# Real Compatibility rendering, captures, depth occlusion and frame timing:
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 3500
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 3500 -- --dense
# Production terrain QA at both supported development sizes:
& $godotExecutable --path . --script res://tests/terrain_graphical.gd --quit-after 3500
& $godotExecutable --path . --script res://tests/terrain_graphical.gd --quit-after 3500 -- --dense
& $godotExecutable --path . --script res://tests/terrain_graphical.gd --quit-after 3500 -- --medium
# Full mouse-routed battle and movement/rig suites can also run graphically:
& $godotExecutable --path . --script res://tests/combat_ui.gd --quit-after 5000
& $godotExecutable --path . --script res://tests/animation.gd --quit-after 5000
# Selected-unit overlay framing, information safety, and supported resolutions:
& $godotExecutable --path . --script res://tests/strategic_ui_graphical.gd --quit-after 5000
& $godotExecutable --path . --script res://tests/overlay_ux.gd --quit-after 5000
& $godotExecutable --path . --script res://tests/terraces_graphical.gd --quit-after 5000
& $godotExecutable --path . --script res://tests/village_defenders_graphical.gd --quit-after 5000
# Medium loading/memory and a real 300-unit stress scene:
& $godotExecutable --headless --path . --script res://tests/planet_performance.gd -- --medium
& $godotExecutable --path . --script res://tests/planet_performance.gd -- --board
# Static Swarm roster gallery and board integration:
& $godotExecutable --path . --script res://tests/swarm_models_graphical.gd --quit-after 5000
```

The runner imports/parses first, then runs **41 headless suites** plus real two-process and four-process ENet integrations, including dedicated model-asset, balance, FFA and planet performance, multiplayer, visibility, Living Migration, Baumeister, strategic UI, and world-population coverage; content-foundation, world-interaction, world-dressing determinism, placement, slope/water exclusion, LOD, density, fallback, and gameplay-isolation checks. It rejects script/engine errors, missing completion markers and nonzero failures, even if Godot returns exit code 0. Logs are saved under `.godot/10_*.log`.

Coverage includes all six topology subdivision counts and generated worlds at levels 0 through 4; deterministic serialization and fingerprints, independent sub-seeds, seam continuity, latitude and elevation effects, normalized biome blends, connected regions and deterministic cleanup; plus adjacency, pathfinding, picking, movement, combat, economy, AI, restart, and rig tracks. The procedural suite performs 80,371 checks at the default seed.

Graphical smoke covers procedural debug modes, seed identity, gameplay, navigation, AI, and far-side depth occlusion. `terrain_graphical.gd` captures production terrain, all five biome targets at tactical/regional distances, both poles, and lakes for three seeds; it checks production pixel identity, wetness/rock effects, and records frame timing, draw calls, dressing counts, and build time. See [the world-dressing report](docs/Milestone_11_PBR_and_World_Dressing.md) for results.

Physical mouse/keyboard feel remains a manual check; automated UI tests inject actual viewport events. To repeat manually: launch a Small match, select and move a Scout, pan during movement, focus an HQ and recruit, navigate to the opposite hemisphere, try close and whole-planet zoom, pause/resume, return to Main Menu, and start another match. For a complete scripted battle, run `combat_ui.gd` above.

## Limits and next milestone

[Terraced terrain](docs/Terraced_Terrain.md) replaces continuous height displacement in normal matches with four elevation levels, a shared ramp profile, rare cliffs that block ground movement, and red cliff rims. New Game and Host Game expose cliff density under Advanced Settings. Uploaded terrain textures are organized under assets/terrain/materials, and walking units contact the rendered surface.

[Medium performance](docs/Planet_Performance.md) documents compressed texture budgets, spatial scenery batches and cell picking, cached minimap terrain, batched Connection queries, horizon culling, match-state cleanup, and a repeatable busy-world benchmark. Medium retains all 10,242 gameplay cells.

The renderer is a single-valued radial height surface with static chunks. Erosion, channel carving, animated water, terrain gameplay effects, and terrain-mesh LOD remain future work. Large structures use their host-cell height without flattening the ground beneath their footprint.

Milestone 9 is implemented by [`SurfaceCamera`](scripts/view/surface_camera.gd) and [`TacticalCameraConfig`](scripts/view/tactical_camera_config.gd). See [the camera report](docs/Milestone_9_Surface_Camera.md) for framing choices, follow, antipodal travel, verification, and limits. Run `camera_navigation.gd` without `--headless` for graphical camera checks; add `-- --dense` for radius 24.

Milestone 10 is implemented by [`AppController`](scripts/app/app_controller.gd), [`MatchConfig`](scripts/app/match_config.gd), and [`UserSettings`](scripts/app/user_settings.gd). See [the frontend report](docs/Milestone_10_Frontend.md) for navigation, size mappings, persistence, verification, and current limits.

Other documentation: [content authoring](docs/Content_Authoring.md), [8B delivery](docs/Milestone_8B_Procedural_Planet.md), [8A recovery](docs/Milestone_8A_Recovery.md), [design brief](docs/Faction_Brief_and_Day_One_Plan.md), [asset contract](assets/ASSET_CONTRACT.md), [movement/rig integration](docs/Movement_and_Rig_Integration.md), and [earlier review](docs/Code_Review_2026-09-26.md).
