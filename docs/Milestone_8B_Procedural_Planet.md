# Milestone 8B: Procedural Planet Data Foundation

## Delivery status

Milestone 8B is complete in Godot 4.6.2. It adds deterministic, continuous sphere-native generated fields, weighted biomes, connected regions, seed controls, diagnostics, debug rendering, and automated acceptance coverage. The existing geodesic topology and all gameplay rules remain intact.

The pre-8B workspace is archived at `.godot/pre_8b.zip`. This workspace has no Git metadata, so validation used direct file inspection, deterministic fingerprints, automated suites, and rendered captures.

## Architecture

- `PlanetGenerationConfig` is the serialized generation contract. It carries the signed 64-bit world seed, generation version, field parameters, sea-level reference, biome definitions, and region settings. `GeneratedPlanet` deep-copies it so later Inspector or UI edits cannot mutate an existing world.
- `PlanetFieldSampler` owns explicitly configured `FastNoiseLite` instances. Every subsystem receives a stable SHA-256-derived sub-seed from `hexfront-seed-v1|<world seed>|<label>`. For example, seed `12345` and label `height` derive `1928025828`.
- `PlanetWorldCellData` caches normalized height, temperature, moisture, fertility, terrain roughness, biome weights, dominant biome, and region ID by stable cell ID.
- `BiomeDefinition` is data-driven. Each definition has a display color and Gaussian preferences for the five scalar fields. Compatibility scores normalize into a continuous distribution; the largest weight supplies the dominant label.
- `PlanetRegionGenerator` selects deterministic farthest-point seeds, grows regions through real cell adjacency, and merges undersized regions using shared-border size and stable ID tie-breaks. `PlanetRegionData` caches member IDs and aggregate fields/biomes.
- `GeneratedPlanet` is the single generated-world result. It exposes cached cell and region records, continuous direction sampling, validation, statistics, and a content fingerprint. Gameplay state has no dependency on it.
- `PlanetWorldDebugView` and `PlanetWorldDebugPanel` are presentation-only consumers. Regenerating a seed replaces the generated data and debug mesh without rebuilding topology or resetting the match.

## Field construction

All noise is sampled from normalized Cartesian direction `(x, y, z)`. No longitude is used, so the antimeridian has no special case or texture seam.

- **Height:** sphere-space domain warp followed by continent, regional, and detail layers at distinct frequencies and weights. The final value uses stable clamping into `[0, 1]`.
- **Temperature:** absolute latitude supplies the main equator-to-pole gradient. Coherent 3D variation breaks uniform bands, and elevation above sea level applies cooling.
- **Moisture:** an independent coherent 3D field with its own derived seed.
- **Fertility:** combines moisture, habitable temperature, moderate elevation, and independent local variation.
- **Terrain roughness:** an independent coherent high-frequency field for later terrain synthesis.

Defaults define Grassland, Forest, Dryland, Rocky, and Wetland. These are preferences rather than hard thresholds. Every cell retains all normalized weights, and the blend debug view interpolates biome colors from them.

The default seed `48293617` at subdivision 3 produces 642 cells and 14 regions:

| Field | Minimum | Average | Maximum |
|---|---:|---:|---:|
| Height | 0.000 | 0.499 | 0.972 |
| Temperature | 0.007 | 0.555 | 1.000 |
| Moisture | 0.000 | 0.466 | 1.000 |
| Fertility | 0.158 | 0.484 | 0.787 |
| Terrain roughness | 0.009 | 0.456 | 0.898 |

Dominant coverage is Grassland 31.2%, Forest 20.6%, Dryland 33.5%, Rocky 10.6%, and Wetland 4.2%. The default generated-world fingerprint is:

```text
f9c76f2b4a5346e011b535fe48d71f3ca218fdc631d544bdbe93533ea748408f
```

## Runtime controls

Press **F6** to show or hide the generated-world panel. It provides a signed seed entry, Apply Seed and New Planet actions, the generated summary, view selection, and full diagnostics for the selected or hovered cell. Invalid or out-of-range seed text is rejected without changing the current world.

Press **F7** to cycle through Normal, Height, Temperature, Moisture, Fertility, Terrain Roughness, Dominant Biome, Biome Blend, and Regions. Scalar and blended views use a continuous debug sphere; categorical biome and region views use cell polygons. Debug rendering does not regenerate data. Restart retains the same `GeneratedPlanet` object and topology. New Planet chooses one random seed, then follows the same deterministic path as an entered seed.

## Verification

The complete headless command is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_all.ps1
```

It imports and parses the project before running 13 suites. All passed after integration: `planet_grid`, `planet_world`, `world_ui`, `smoke`, `movement`, `hotseat`, `combat`, `combat_ui`, `economy`, `economy_ui`, `ai`, `resources`, and `animation`.

`planet_world.gd` performs 74,863 checks. It covers same-seed equality and different-seed variation; serialized configuration and snapshot isolation; fixed and independent sub-seeds; continuous samples and seam continuity; latitude and elevation cooling; finite normalized ranges; mixed normalized biome weights; region connectivity, cleanup, aggregates, and deterministic IDs; corrupt-data validation; and generated worlds at subdivisions 0 through 4. On the final host run, generation took about 85 ms for 642 cells and 352 ms for 2,562 cells. Average neighboring differences were smaller than distant-pair differences for both height and moisture.

The graphical acceptance command is:

```powershell
& $godotExecutable --path . --script res://tests/graphical_smoke.gd --quit-after 2500
```

It passed with real Compatibility rendering on a Radeon RX 590 at subdivisions 3 and 4. It captured all eight generated-data views, verified same-seed logical and pixel identity with nondeterministic timing text excluded, verified a different seed changed both fingerprint and pixels, inspected the opposite hemisphere, and retained movement, depth-occlusion, orbit, AI, and restart checks. Rotating-view timing measured 6.94 ms median and 7.20 ms p95 at 642 cells, and 6.95 ms median and 7.18 ms p95 at 2,562 cells, with 290 scene nodes in either case. Captures and logs are under `.godot/8b_*`.

## Scope boundary and 8C handoff

8B intentionally stops at generated data and diagnostic presentation. It does not classify final land/ocean, route rivers, fill lakes, simulate erosion, displace the production mesh, place resources, or apply terrain effects to movement, combat, economy, or AI. The normal view therefore remains the neutral 8A globe.

The clean 8C handoff is to consume `GeneratedPlanet` without changing its field identities: classify land and ocean from height and sea level; build hydrology and erosion as new derived layers; derive coast, river, and lake masks; generate displaced presentation geometry through the existing sampling boundary; then introduce gameplay effects as explicit rule inputs. Independent sub-seeds allow those additions without reshuffling 8B results.
