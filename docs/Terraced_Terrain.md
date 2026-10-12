# Terraces, ramps and cliffs

Normal matches and direct scene runs now override continuous noise displacement with seed-derived terrain containing four elevation levels. Low-frequency ridged noise distributes broad highland belts. Adjacent terraces differ by at most one level. Rise is 0.65 world units (reduced only when necessary to fit a transition inside unusually small tiles), for 1.95 total relief. This is almost three times the original 0.22-unit spacing, making cliff drops and highland silhouettes more distinctive.

Range frequency now scales as `0.65 * sqrt(12 / planet_radius)`. Larger planets therefore get broader bands and more flat land rather than densely alternating slopes. Initial rank allocation favors lowlands (65% / 20% / 12% / 3% across the four levels), followed by the adjacency cleanup and peak guarantee. A representative seed measured 57% flat tiles on Tiny, 71% on Small and 89% on Medium. Village candidates must be flat according to the same terrain classification used by the renderer.

Height changes are confined to ramp transition bands. Their shared profile uses a 35-degree rise/run ratio, with a run shorter than one tile spacing; broad flat areas retain a single elevation. The renderer samples this profile in cell-aligned meshes and matches edge tessellation between flats and ramps. Rasterized triangle normals approximate the profile on the curved planet; physical unit contact uses the actual rendered triangles.

Advanced Settings in New Game and Host Game expose **None, Rare, Low, Moderate, High, Experimental** cliff generation. Rare is the default. Density is the fraction of potential terrace transitions converted into cliff edges, not the fraction of all tiles. None creates no cliffs. Generation preserves global ground connectivity by opening a minimum set of ramp connections between components.

Cliffs have rocky vertical faces and a thin opaque red rim, filtered by exploration. Both directed sides of an edge are blocked. Ordinary movement, weighted Baumeister movement, route validation and forced ant retreat respect those edges; AI issues the same authoritative movement commands. Flying insects have explicit `flying` tags and may cross them. The cliff setting survives MatchConfig copying and multiplayer setup, and the gameplay compatibility version is bumped.

Network verification also exposed a loading-barrier race: receiving an initial snapshot made a client actionable before the host had all players' load acknowledgements. Clients now wait for the host's readiness broadcast. The four-process integration intentionally delays the fourth client's initial snapshot to exercise that ordering.

Walking units no longer inherit the previous floating visual offsets: their authored mesh bounds are normalized to a ground origin, and their position follows the rendered terrain with 0.006-unit clearance. Root and squad members follow the local ground normal, including during ramp motion. Flying units retain hover clearance. Source model transforms, rigs and animations are preserved. Water levels use the same normalized-height-to-world-height mapping as the new terrain.

Uploaded texture archives and all extracted map roles are retained in the [terrain library](../assets/terrain/README.md). Five active albedos use GPU compression and 1024-pixel import limits. Texture displacement is intentionally excluded from physical geometry to preserve terrace and ramp constraints.

## Verification

`tests/terraces.gd` checks four levels across seeds, bounded height differences, fixed rise/run, deterministic terrain/cliffs, None/Rare/Experimental settings, ground connectivity, blocked ground movement, flying movement and network setup copying. `tests/terraces_graphical.gd` captures cliffs, walking ramp contact and the planet overview. Existing terrain/animation checks now verify contact against the rendered surface rather than the previous floating analytic offset.

```powershell
& $godotExecutable --headless --path . --script res://tests/terraces.gd
& $godotExecutable --path . --script res://tests/terraces_graphical.gd --quit-after 5000
& $godotExecutable --path . --script res://tests/planet_performance.gd -- --board
```

The old continuous generator remains only as an explicit reference configuration (`terraced_terrain=false`) for legacy geometry/climate regression fixtures; normal setup does not offer it. The final Medium stress run retains all 10,242 cells and 300 additional units. On the RX 590 it loaded in 19.3 seconds and measured about 144 FPS during camera rotation, with a 1.35 ms p95 board update, 287 MB tracked static memory and 81 MB texture memory. Those figures describe the tested tactical view, not every possible dense battle.
