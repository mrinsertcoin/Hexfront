# Medium planet performance

Medium retains 10,242 gameplay cells and radius 48. The performance pass targets loading, memory, exploration, and large armies without reducing that world size or changing population placement.

## Causes and changes

Scenery loaded 72 full-resolution, lossless textures across three supplied mesh LODs. Imported environment maps now use GPU compression and 1024/512/256 pixel limits by LOD. Unit maps use GPU compression and a 1024 pixel limit, with 2048 for the larger Spider. Source art is untouched. Godot performs a one-time reimport after these settings change. The limits and compression follow the [Godot image import guidance](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).

Cell picking previously scanned every planet cell. A balanced spatial index finds the nearest cell, then retains the original polygon containment checks and numeric ID tie-breaking. Terrain and population fingerprints are unchanged. Population spacing and nearby guardian placement now use bounded graph traversals instead of allocating full-world distance rows.

Environment meshes are grouped into up to 20 spatial sectors per asset and LOD, allowing independent frustum culling. Existing mesh resources remain shared, placement density remains unchanged, and only one LOD is active. Permitted props are packed into a visible prefix: unexplored props previously had zero scale but still submitted their geometry to the GPU. Cell ownership for each prop is resolved once rather than during every visibility update. Unchanged zoom bands do no work.

Units wholly behind the solid planet have render layers disabled and animation playback suspended; logical entities, fog permissions, movement, and squad state remain intact. Bounds provide a conservative horizon margin. Army meshes use LOD bias 0.15 to prefer their imported reduced geometry at tactical screen sizes; previews keep their independent detail settings. Tactical shadows have a fixed 32-unit range instead of expanding with planet radius. Ownership rings use 288 triangles rather than 4096, and rings/health bars do not cast shadows. `tools/inspect_unit_lods.gd` audits the actual imported index buffers; see [Godot's LOD guidance](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html).

The minimap's explored terrain is cached in a small texture rather than issuing thousands of individual draw commands. Observation, viewer, match and size changes invalidate it. Ant Connection highlights share a controller-wide query, and unchanged camera/pointer positions skip hover picking. Debug geometry is built only on request; hidden model previews stop rendering.

`GameState` owns `VisibilitySystem`; the latter now holds a weak reference back to the state. This removes an ownership cycle that retained discarded matches and their topology in memory.

Restart invalidates fog, scenery and minimap caches explicitly: observation revision numbers restart with match state and must not identify cached data from the previous match.

## Reproduce

`tests/planet_performance.gd` checks spatial queries against exhaustive nearest-cell lookup, containing polygons, visual resolution, a tracked memory budget, and match-state release. Its default case runs in `tests/run_all.ps1`.

```powershell
& $godotExecutable --headless --path . --script res://tests/planet_performance.gd -- --medium
& $godotExecutable --path . --script res://tests/planet_performance.gd -- --board
```

The second command loads a real Medium Living Migration/Baumeister match with standard population, adds 300 units (including five-member Worker and three-member Fighter squads), rotates the tactical camera, reports CPU update time and observed rendering throughput, and captures `.godot/performance_medium_busy.png`. Run benchmarks separately from other test processes for comparable timings. Tracked Godot memory is not total operating-system or GPU process memory.

Initial same-machine measurements: terrain/scenery preparation fell from 13.34 seconds to about 3.6–4.0 seconds, tracked memory from 1254 MB to about 124–140 MB, and 1000 Medium cell queries from 3202 ms to about 37–55 ms. Standard population generation retained fingerprint `7a76d19c84957787517a9493f14d25cb00d3194b8885cab588630392338b1fbb` while falling from about 7.4 seconds to 1.1–1.3 seconds. These component measurements are not total loading times.

The final real-renderer busy-board run on the Radeon RX 590 at 1280×720 loaded Medium in 12.21 seconds, added/refreshed 300 units in 2.05 seconds, and measured 103.8 frames/second during tactical camera rotation with a 1.83 ms p95 board CPU update. Godot reported 162.1 MB tracked static memory and 86.1 MB texture memory; 338 entity views were suspended behind the globe or by fog. These are measurements for this camera and workload, not a benchmark of hundreds of high-detail units simultaneously filling the screen.

Validation included all 38 headless suites, both ENet process integrations, the Medium component and real-renderer stress tests, and graphical unit-preview captures. Final scenery visibility compaction and restart invalidation received additional targeted scenery, visibility, hotseat, UI, camera, movement/animation and smoke checks. The scenery regression verifies permitted instance counts, no submissions for a fresh observer, and complete restoration in omniscient mode.

## Remaining limits

Loading still builds the board synchronously. Dynamic armies still use individual scene nodes and authored models; extremely dense visible battles can remain limited by draw calls, model complexity, shadows, or simulation work. This pass establishes a reproducible workload and removes major costs, but does not claim unlimited units, 60 FPS on every device, or proof that every reported crash had the same cause. Larger future workloads should guide model LODs, batching of repeated unit visuals, simulation indexing, and staged loading.
