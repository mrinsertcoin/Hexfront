# Milestone 8C: Planetary Hydrology, Rivers & Lakes

## Existing state

The canonical 8A `PlanetGrid` and 8B `GeneratedPlanet`, continuous field sampler, weighted biome system, strategic regions, seed protocol, and fingerprint were verified before implementation. The workspace contains no Git metadata, so `git status` reports that it is not a repository. Import/parse and all existing suites passed at the 8B handoff. No blocking 8A/8B redesign was needed.

## Files

Added under `scripts/world`: `hydrology_settings.gd`, `hydrology_cell_data.gd`, `drainage_basin_data.gd`, `lake_data.gd`, `river_segment.gd`, and `planet_hydrology.gd`. Added `tests/hydrology.gd`.

Modified `planet_generation_config.gd`, `planet_world_cell_data.gd`, `planet_field_sampler.gd`, `generated_planet.gd`, `planet_region_generator.gd`, the world debug view/panel, board-integrated tests, graphical smoke, the aggregate runner, and `README.md`.

## Architecture and configuration

Hydrology is generated once between base-field sampling and biome/region calculation. `PlanetHydrology` owns per-cell `HydrologyCellData`, raw `DrainageBasinData`, connected `LakeData`, and directed `RiverSegment` arrays. It reads stable topology, cached base fields, and centralized `HydrologySettings`; gameplay has no dependency on it.

Settings include enable/version flags, runoff and moisture influence, normalized stream/river/major thresholds, lake area/catchment/depth constraints, wetland radius, separate river/lake/ocean moisture strengths, and optional ocean/sea-level behavior. Defaults keep oceans disabled and the planet mostly land.

## Flow and basins

Raw flow selects the strictly lowest neighbor by generated height, with cell ID resolving equal candidates. Following raw routes identifies preliminary sink catchments. Each basin caches its members and the lowest boundary crossing, where spill elevation is `max(inside height, outside height)` with stable inside/outside ID tie-breaks.

Final routing uses a graph-adapted priority flood. Enabled ocean cells are roots. Without oceans, the deterministic global low point is the intentional closed-globe terminal; there is no invisible edge drain. The min-heap orders by filled elevation and cell ID. A newly reached cell points to the already settled neighbor, producing an acyclic drainage tree while breaching/filling raw depressions. Reverse settlement order accumulates local runoff exactly once. Runoff is `runoff_base + base_moisture * moisture_runoff_influence`.

## Lakes

Connected cells whose filled height exceeds terrain by `lake_min_depth` form candidates. Candidates must satisfy minimum/maximum cells and normalized contributing catchment. Smaller or oversized candidates remain routed through the priority-flood breach, preventing puddle spam and continent-sized inland seas. The no-ocean terminal receives a small connected terminal lake even when its depth is zero.

Each lake stores stable ID, connected cell IDs, common logical surface elevation, inflow cells, normalized catchment contribution, center direction, terminal flag, and outlet. Non-terminal lakes use the deterministic first lowest crossing along final routing; terminal lakes have no outlet. These are logical data only—final local flat water surfaces belong to 8D.

## Rivers

Local runoff and all upstream runoff produce flow accumulation. Classification compares normalized accumulation against configurable planet fractions, so thresholds scale from 642 to 2,562 and future 10,242-cell worlds. Default thresholds are 0.006 stream, 0.020 river, and 0.060 major river. Micro-drainage remains cached but invisible below the stream threshold.

Every visible route is an explicit directed graph edge. Segments store endpoints, normalized accumulation, river class, Strahler stream order, and a square-root-scaled width factor. Tributaries and confluences emerge from accumulation; no random splines or unrelated river sources are used. Debug lines subdivide spherical interpolation and sit slightly above the globe, avoiding chords through it.

## Climate integration

The original `base_moisture` remains unchanged. Lakes, oceans, and visible rivers seed configurable moisture influence, propagated through bounded graph distance with smooth falloff. `effective_moisture = clamp(base_moisture + hydrology_moisture_bonus, 0, 1)`.

Wetland potential combines effective moisture, local low slope, and drainage strength. The existing five-field biome scorer receives effective moisture; its Wetland result receives a continuous wetland-potential multiplier, after which all weights are renormalized. This creates transitions rather than forcing every river neighbor to Wetland. Strategic region membership stays stable and only cached effective-moisture/biome aggregates are refreshed.

## Debugging

F6 opens seed controls, summary, selector, and cell/lake inspection. F7 cycles all modes. Added views are Base Moisture, Effective Moisture, Flow Direction, Flow Accumulation, Drainage Basins, Lakes, Rivers, Hydrology Moisture, and Wetland Potential. Cell diagnostics expose height, both moisture values, runoff, accumulation, downstream, basin, lake, river class, order, moisture bonus, and wetland potential. Lake selection adds area, surface height, terminal/outlet state, and catchment.

## Determinism and fingerprint

Hydrology generation version 1 is serialized inside the world config. All traversals use sorted topology neighbors, stable heap ordering, and explicit ID tie-breaks. The world fingerprint now includes the hydrology configuration and, per cell, downstream ID, basin/lake IDs, river class, quantized accumulation, hydrology moisture, effective moisture, and recalculated biome weights.

Default seed `48293617`, subdivision 3 fingerprint:

```text
baba403acade672107d4a49c838a0f2259c3fb8da1a7c7f8b5cde0466ed77162
```

## Tests and results

Commands run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_all.ps1
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 3500
```

Import/parse and all 14 suites passed: `planet_grid`, `planet_world`, `hydrology`, `world_ui`, `smoke`, `movement`, `hotseat`, `combat`, `combat_ui`, `economy`, `economy_ui`, `ai`, `resources`, and `animation`. The updated world suite performs 80,371 checks; hydrology adds 9,753 controlled and generated checks.

Coverage includes controlled downhill slopes, confluence accumulation, raw basins/spill edges, terminal lakes, optional ocean sinks, maximum lake size, neighbor validity, cycle detection, path termination, lake connectivity/outlets, exact same-seed hydrology, different seeds, moisture/biome propagation, all 12 pentagons, and normalized density at subdivisions 3 and 4. Existing topology, picking, pathfinding, movement, combat, economy, recruitment, AI, victory, restart, world determinism, regions, and animation coverage remains enabled.

## Quality and performance

Rendered debug views were inspected for seeds `48293617`, `246813579`, and `-42`, with an additional different-seed identity check at `48293618`. At 642 cells they produced 8, 9, 8, and 16 lakes respectively; each had one intentional terminal lake with oceans disabled. Visible segment totals were 186, 194, 204, and 190, including minor streams. Images show branching spherical routes, distinct coherent basins, bounded lake patches, no longitude seam, no loops, and no teleporting/chord segments.

The default 642-cell world measured about 138–155 ms total generation during final graphical/headless runs. A 2,562-cell generated world measured about 692 ms in the validation-heavy world suite. Visible-segment density was 0.290 at 642 cells and 0.162 at 2,562 cells, within the acceptance scaling bound. The final real-rendering run measured 6.96 ms median and 7.27 ms p95 on the Radeon RX 590 with 296 scene nodes.

## Known limitations and 8D handoff

Priority flood uses a single global terminal when oceans are disabled, so all ultimate drainage belongs to one planetary outlet tree even though raw catchments, non-terminal lakes, and watersheds remain distinct. This is deterministic and valid for a closed globe, but future climate tuning may choose multiple deliberate endorheic terminals. Logical lake surface height is ready for rendering, but the current debug cell overlay cannot show a locally flat water plane. Line primitives communicate route and strength by color; final width geometry is pending.

8D should consume lake membership/surface height and river segment endpoints/order/width factor to build locally flat lake surfaces and smoothed spherical river ribbons, then use accumulation and proximity for non-destructive channel shaping. It must retain 8C IDs and routes as authoritative and keep movement/combat rules separate. Erosion, sediment, animated water, coast geometry, bridges, resources, and gameplay effects were not implemented here.
