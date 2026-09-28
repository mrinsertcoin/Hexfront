# Milestone 8D — Continuous Planet Terrain Renderer & Biome Material System

## Existing state and repairs

The initial audit found the canonical `PlanetGrid`, `GeneratedPlanet`, 8B field/biome sampler, 8C hydrology records, tactical overlays, and radial entity presentation. `git status --short` confirmed this workspace has no Git metadata. Before changes, Godot import/parse and all 14 existing automated suites passed.

Two integration gaps were repaired. Arbitrary-direction biome queries previously ignored hydrology even though cached cells included it; `PlanetClimateInterpolator` now interpolates moisture bonus and wetland potential over the existing primal spherical triangles before calling the same biome scorer used by cells. The lake validation block also contained an unconditional `continue`; its indentation is corrected so membership, connectivity, and terminal/outlet consistency actually run. The default 8C world fingerprint is preserved.

## Terrain architecture and files

New presentation classes are `TerrainRenderConfig`, `TerrainSurfaceSampler`, `BiomeMaterialDefinition`, `TerrainMaterialLibrary`, `PlanetTerrainRenderer`, and `PlanetWaterRenderer`, under `scripts/view/`. New shaders and texture setup guidance are under `assets/terrain/`. `PlanetClimateInterpolator` is under `scripts/world/` because continuous climate queries belong to the generated-world API.

Modified integration points are `GeneratedPlanet`, `PlanetBoard`, `PlanetSurface`, `EntityView`, and `PlanetWorldDebugView`. Tests add `terrain.gd` and `terrain_graphical.gd`, extend the runner and graphical smoke, and adapt board presentation expectations in `hotseat.gd` and `animation.gd`. The full original spherical picking matrix remains in `smoke.gd` using zero displacement; displaced picking receives additional coverage in `terrain.gd`.

The renderer creates its own subdivided icosphere. Default visual subdivision 5 means **10,242 vertices and 20,480 triangles**, regardless of whether gameplay has 642 or 2,562 cells. Subdivision 6 is exposed for 81,920 triangles. The original 20 faces become separate static mesh instances for frustum culling and future LOD. A single welded source computes positions, weights, and normals before partitioning into chunks, so shared boundaries agree exactly. There is no per-cell ground mesh and no per-frame rebuild.

## Height, normals, and presentation sampling

Every vertex uses the canonical `GeneratedPlanet.sample_height(direction)`. The visual remapping is:

```text
radius = planet_radius
       + (height ^ height_exponent - height_center)
       * height_contrast * terrain_height_scale
```

Default scale is 1.25, exponent 1.25, contrast 1, center 0. Normals are area-weighted from displaced triangles and normalized after accumulation. Material normals use triplanar projection rather than UV tangents. No new height noise or destructive terrain edits were introduced.

`TerrainSurfaceSampler` is shared by entity placement, movement, overlay meshes, debug borders, labels, and camera clearance. Unit/HQ up remains radial for stable strategic presentation. Movement follows the existing accepted cell route and resamples terrain along spherical interpolation. Stationary placement and path initialization use the same normalized cell direction, preserving the exact no-snap animation invariant. Structures use host-cell height without footprint flattening.

## Biome materials

Five data-driven `BiomeMaterialDefinition` resources support albedo, normal, and roughness maps; tint; world-unit repeat scale; normal strength; and roughness multiplier. Predictable asset folders are `assets/terrain/grassland`, `forest`, `dryland`, `rocky`, and `wetland`. Missing assets use deterministic subtle placeholder grain, flat normal maps, and configured roughness, with one concise warning per application run. No purchased/scanned textures are required and no per-tile texture variants exist.

The material library resizes layers to a configurable resolution, packs roughness into albedo alpha, generates mipmaps, and creates two texture arrays. Triplanar projection uses object-local positions in world units, with no longitude seam or polar UV singularity. Continuous biome weights travel in vertex color/UV channels and blend all five material layers. Actual surface slope and generated roughness bias toward rock. Effective moisture and wetland potential darken ground and modestly lower roughness; a roughness floor avoids a glossy hemisphere. Stable macro variation and restrained detail preserve unit readability.

Normal perturbations from the three projection planes are transformed into the local surface tangent plane, blended, and normalized before lighting. Neutral normal maps preserve the displaced normal. Full quality uses 15 packed albedo/roughness samples plus 15 normal samples per fragment; disabling normal maps removes the latter 15. Shader coordinate mapping, weights, texture sampling, normal projection, wetness, and lighting are separated and commented. [Godot shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html) informed sampler hints and texture-array usage.

## Rivers, lakes, and shores

`PlanetWaterRenderer` consumes every authoritative `RiverSegment`. A constrained spherical Hermite interpolation smooths the cell polyline while retaining endpoints and remaining near the original great-circle route. Each centerline receives dense terrain samples; tangent-perpendicular left/right vertices form an actual ribbon. Width ranges from 0.035 to 0.16 world units using hydrology width factors. Endpoint blends meet adjacent lake levels, and small overlapping patches close confluences. Winding is corrected for consistent ribbon/junction lighting. There are no random river splines or new drainage decisions.

Each lake merges its cell boundaries, removes interior edges, rounds the outer contour with bounded corner cutting, triangulates it, and subdivides on the sphere at the mapped authoritative water radius. There is one merged surface per lake rather than separate cell puddles. A narrow damp shoreline joins exposed edges; portions buried beneath higher terrain do not produce detached shore bands. Terminal lakes share the same presentation as other lakes. Enabled oceans receive a sea-level sphere; they remain disabled by default.

Water is opaque and mildly reflective, avoiding transparency sorting and far-side leaks. It has a separate, reusable shader, with calmer lake roughness. Water animation, channel carving, erosion, and fluid simulation are deferred. The renderer never changes lake membership, downstream routing, or authoritative height.

## Picking, tactical overlays, and debug views

Idle gameplay hides persistent grid lines. Selection, reachability, paths, attack ranges, and hover use translucent, subdivided overlays sampled above the actual terrain. F1 exposes the strong debug grid; F2–F4 retain pentagons, centers, and IDs. F6/F7 retain all 8B/8C field, biome, region, flow, basin, lake, river, and wetness modes without world regeneration. Debug surfaces and lines also follow terrain. Production water is hidden while diagnostic modes are active.

Picking uses one cached triangle BVH built from rendered terrain and resolves hits back to the original `PlanetGrid` polygons. There are no physics collision objects. A tiny subpixel ray footprint resolves floating-point ambiguity exactly on shared triangle edges; the nearest intersection wins. Zero-height settings retain exact analytical sphere picking. This follows Godot's [physics-free TriangleMesh query API](https://docs.godotengine.org/en/stable/classes/class_trianglemesh.html). The camera retains its existing controls and receives only a surface-clearance clamp.

## Determinism and rebuilds

World regeneration rebuilds geometry and masks from the new canonical object. `rebuild_terrain()` applies renderer-setting changes without regenerating world data. Restart reuses the world and meshes. Geometry and material masks repeat exactly for the same world/settings, and production screenshots are tested for same-seed pixel identity. No visual randomness depends on frame timing.

Default world identity remains:

```text
baba403acade672107d4a49c838a0f2259c3fb8da1a7c7f8b5cde0466ed77162
```

## Validation commands and coverage

```powershell
$godotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_all.ps1
& $godotExecutable --path . --script res://tests/terrain_graphical.gd --quit-after 3500
& $godotExecutable --path . --script res://tests/terrain_graphical.gd --quit-after 3500 -- --dense
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 3500
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 3500 -- --dense
```

The runner covers 15 suites: topology, procedural world, hydrology, world UI, terrain, spherical picking/transforms, movement, hotseat, combat, combat UI, economy, economy UI, AI, resources, and animation. The new terrain suite checks finite positions/normals, valid indices, two-face edge incidence, radius mapping, shared chunk normals, continuous hydrology/biome agreement at cell centers, all lake surface radii, authoritative river coverage, ribbon widths and terrain proximity, motion over hills/valleys, deterministic rebuilds, every cell at three picking distances, and an off-axis displaced-triangle camera matrix. Old spherical horizon/pole/picking checks remain intact as a zero-displacement fixture.

Rendered QA uses seeds `48293617`, `246813579`, and `-42`, inspecting production terrain, close views, both poles, lake connections, tactical overlays, wetness/rock toggles, and regeneration. The original graphical suite additionally checks all debug modes, opposite-hemisphere viewing, movement, far-side unit/HQ/health-bar/overlay occlusion, AI return of control, and restart. Logs and captures use `.godot/8d_*`.

## Known limitations and Milestone 9

Both graphical suites completed with zero failures at 642 cells/radius 12 and 2,562 cells/radius 24 on the Radeon RX 590 Compatibility renderer. The terrain profile held 20,480 triangles: median/p95 6.914/7.347 ms at 642 cells and 6.949/7.119 ms at 2,562 cells. The gameplay graphical profile measured 6.950/7.224 ms and 6.938/7.174 ms respectively. These are observed frame timings on this machine, not portable performance guarantees. All 15 headless suites passed across the initial aggregate run and targeted animation/terrain reruns after correcting waypoint normalization; Milestone 9 adds a final integrated regression run.

Materials are clean replaceable placeholders, not final scanned PBR art. Terrain chunks are static with exposed resolution settings; dynamic LOD is not implemented. Water follows 8C routing and levels without carving channels, so physically eroded banks and depression breaches remain future visual work. Large structure footprints are not flattened. Lake outline smoothing is bounded within the coarse membership footprint rather than a full erosion-derived shoreline model. No trees, resources, terrain gameplay bonuses, or water movement restrictions were added.

Milestone 9 should consume the existing surface position/normal queries and BVH for closer surface-relative navigation and focus, preserve graph-based command resolution, and use the chunk boundary to add camera-driven LOD later if profiling requires it. The full tactical-camera redesign is deliberately outside 8D.
