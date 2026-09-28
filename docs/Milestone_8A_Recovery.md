# Milestone 8A recovery and delivery

Completed 27 September 2026 using Godot 4.6.2 standard, Compatibility, on Windows. Scope stops at the geodesic globe foundation.

## Recovery audit

`git status --short` failed because this workspace has no `.git` directory. There were therefore no reliable tracked/untracked classifications or Git diffs. The files, timestamps, existing test archive, README and references were inspected directly. Before editing, scripts, tests, README and project configuration were saved to `.godot/pre_8a_recovery.zip`. The pre-existing `tests/legacy_flat_snapshot.zip` was retained. A final comparison against the recovery ZIP confirms `unit_types.gd`, `unit_visual.gd` and project configuration were not changed.

| Recovered area | State when resumed | Result |
|---|---|---|
| PlanetCell / PlanetGrid generator | Complete, isolated, architecturally sound | Preserved generation, stable IDs, adjacency, polygons, tangents, picking lookup and fingerprints; added public path/distance entry points |
| Topology tests | Complete but absent from test runner | Baseline 412,003 checks passed; integrated into runner and extended to starting positions at every level |
| State, rules, AI | Flat axial gameplay still authoritative | Migrated to integer cell IDs and one PlanetGrid graph |
| View, camera, picking, overlays, movement | Flat board presentation | Migrated to spherical rendering, radial placement, surface paths and orbit camera |
| Regression tests | Ten valid flat-board suites | All ten passed before editing; migrated fixtures/assertions and retained all behavioral areas |
| README | Described the old 10x10 board | Rewritten for the current globe |

Initial import had no parser errors. This was primarily an unfinished integration, rather than a broken generator. During integration, runtime checks caught a typed-array conditional initialization error and a presenter basis mismatch when replaying from a different starting cell; both were repaired. The picking test was corrected to distinguish fully hidden cells from cells that straddle the horizon. Graphical inspection caught insufficient ambient lighting on the opposite hemisphere; explicit ambient light fixes it.

## Architecture

- `scripts/core/planet_grid.gd`: fixed regular icosahedron; ordered triangle subdivision; midpoint deduplication by sorted endpoint pair; unit-sphere normalization; vertex-dual cells. Configurable subdivisions 0–5 and positive planet radius. No nodes or gameplay entities.
- `scripts/core/planet_cell.gd`: stable ID, normalized center direction, scaled center, sorted neighbor IDs, ordered polygon corners, boundary normals and cached tangent frame. Exactly 12 degree-5 cells; all others degree 6. Polygons are outward CCW. Tangent construction uses the least-aligned reference axis and has no pole singularity.
- `scripts/core/game_state.gd`: units/HQs store `cell_id`; owns the grid reference. Deterministic HQs start at 0 and the graph-farthest BFS cell. Starting units use three sorted adjacent cells. Restart retains the exact grid instance.
- `scripts/core/rules.gd`: uses the shared bounded BFS with occupied cells blocked. Highlights, path previews, validation and execution agree on `Array[int]` routes. Combat and recruitment use graph distance/adjacency; no sphere geometry enters damage or economy calculations.
- `scripts/ai/simple_ai.gd`: preserves action priorities, recruitment sequence, exposure scoring and turn budget; uses graph distance and rules-provided candidates.
- `scripts/view/board_view.gd` (`PlanetBoard`): one neutral sphere; camera orbit/zoom/focus; front ray/sphere picking; hover; unit/HQ views; existing HUD and AI scheduling.
- `scripts/view/planet_surface.gd`: presentation-only curved overlays, cached on first use; merged outline/center/pentagon meshes. No per-cell physics bodies. Labels are optional and instantiated only on request.
- `scripts/view/entity_view.gd`: radial unit/HQ transforms; spherical waypoint interpolation; parallel-transported heading and smooth turns; long-frame waypoint consumption. `UnitVisual` remains responsible for in-place clips, with no root-motion dependency.

The old `hex_grid.gd` and UID were removed after migration. The final source search found no active HexGrid/HexBoard references, axial gameplay fields, fixed-six neighbor loops, rectangular bounds, flat-plane picking or global-up entity placement. Remaining Vector2i uses are viewport dimensions and undirected edge keys. Vector3.UP in the camera is an orbit reference, not entity orientation.

## Determinism

Generation version: **1**. SHA-256 input: version, subdivision, cell IDs, sorted neighbor IDs and center directions quantized at 1e-6. Radius is intentionally excluded. Repeated generation with different radii preserves the same directions, IDs, neighbors and hash; restart reuses topology.

| Level | Cells | Pentagons | Generation measured (ms) | Lookup measured (microseconds/query) |
|---:|---:|---:|---:|---:|
| 0 | 12 | 12 | 0.768 | 3.345 |
| 1 | 42 | 12 | 1.505 | 6.375 |
| 2 | 162 | 12 | 6.357 | 23.420 |
| 3 | 642 | 12 | 25.678 | 71.205 |
| 4 | 2,562 | 12 | 105.106 | 312.305 |
| 5 | 10,242 | 12 | 417.629 | 3,250.050 |

These are single-run observations, not formal benchmarks. Lookup samples mix center and polygon-interior queries. Generation occurs once per board creation, not per frame or restart.

Default level-3 fingerprint:

```text
14bf42deb7d2915ab6130a15686f15e2fa3bd09e1e7b92dd76b1d717d8f9a930
```

Level-4 fingerprint:

```text
f562defb83e5ede6181cbac2a87a50e72cdb31d4a6ef4d14ac77365f7ef5411f
```

## Verification and exact commands

The following commands were executed from `C:\Code\games\hexfront`:

```powershell
git status --short
$g = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
& $g --headless --path . --editor --import
& $g --headless --path . --script res://tests/planet_grid.gd
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_all.ps1

# Targeted reruns after extending the movement and camera-input checks:
& $g --headless --path . --script res://tests/movement.gd
& $g --headless --path . --script res://tests/smoke.gd --quit-after 100

# Actual Compatibility graphical execution:
& $g --path . --script res://tests/graphical_smoke.gd --quit-after 1500
& $g --path . --script res://tests/graphical_smoke.gd --quit-after 1500 -- --dense
& $g --path . --script res://tests/combat_ui.gd --quit-after 5000
& $g --path . --script res://tests/animation.gd --quit-after 5000
& $g --path . --quit-after 180
```

The runner expands to import plus each of `planet_grid`, `smoke`, `movement`, `hotseat`, `combat`, `combat_ui`, `economy`, `economy_ui`, `ai`, `resources`, `animation`, using `--headless --path <project> --script res://tests/<suite>.gd --quit-after 5000`. It checks errors, completion markers, failures and leaked instances, in addition to exit status.

Actual results:

- **Import/parse: PASS**, no engine/script errors.
- **All 11 headless suites: PASS.** Logs: `.godot/8a_tests.log`, `.godot/8a_import.log`, and `.godot/8a_<suite>.log`.
- **Topology: 412,057 checks, zero failures.** All supported counts, degree distribution, Euler characteristic, connectivity, adjacency symmetry, uniqueness, normalized centers, polygon radius/winding/corners, deterministic generation, point ownership, distinct starts and separated HQs.
- **Movement: 19,974 checks, zero failures.** An independent relaxation oracle checks shortest paths and graph distances around pentagons and hexagons; adjacent and multistep moves, actual blocker detours, trapped units, invalid IDs, HQ blockers, occupied destinations, path limits/reconstruction, highlight-preview-command equivalence, read-only rejection, turns and identical restart.
- **Picking: 9,898 visible-center picks, zero failures**, plus fully hidden-cell rejection, near-horizon samples, poles, four yaw orientations, three zooms, unit/HQ/pentagon targets, background clearing, hover without selection, smooth opposite-hemisphere focus, wheel clamping and middle-drag/release events. CPU picking-matrix run took about 3 seconds.
- **Combat/economy/UI: PASS.** Existing fixed stats, range, action order, immutable failures, damage preview, HP, death/occupancy cleanup, recruitment cost/readiness, income idempotency, both winners, victory locks, restart and HUD event consumption remain covered. The full standard starting-force battle still runs through viewport clicks and reaches HQ victory.
- **AI: PASS.** Passive-human simulation: Player 2 wins round 15 after 172 AI actions. AI-versus-AI: Player 2 wins round 56 after 1,135 actions. Both remain within the original 200-turn bound. Blocked HQ yields; scheduled turns finish; restart cancels old work.
- **Animation/resources: PASS.** Every sampled movement frame stays on the outward radius with valid radial orientation; frame-size agreement, waypoint overshoot, no flips, immediate logical commitment, input gating, death/restart cancellation, real scene-tree advancement, AI waiting, bone-track playback and clip mapping all pass. Imported scenes/assets load.
- **Graphical smoke: PASS at 642 and 2,562 cells.** Real OpenGL Compatibility on Radeon RX 590. A pixel-exact comparison with hidden/revealed far-side units, HQ, health bars and cell overlay demonstrates depth occlusion. Captures of initial globe, close path, intermediate movement, opposite hemisphere and overview pentagons were opened and visually inspected. Full combat UI and rig/movement suites also pass graphically. Normal main-scene launch ran 180 frames without errors.

This is automated graphical smoke with visual inspection and synthetic viewport input, not a claim of physical mouse/keyboard playtesting. The manual repeat checklist is in README.

## Performance

Default development configuration: **642 cells, subdivision 3, radius 12**. The denser smoke uses **2,562 cells, subdivision 4, radius 24** to preserve approximate unit footprint relative to cells.

During 180 frames of scripted orbit, with the normal HUD, units, grid and debug pentagons:

| Cells | Median frame (ms) | p95 frame (ms) |
|---:|---:|---:|
| 642 | 6.940 | 7.197 |
| 2,562 | 6.935 | 7.414 |

The host was comfortably interactive in these runs. Measurements include frame scheduling/vsync and are not a portable FPS guarantee. Only visited overlay cells acquire MeshInstance3D nodes; the 642-cell measurement had 267 total scene nodes. Static graph geometry is cached, and graph distances use a bounded cache.

## Limitations and 8B handoff

No unresolved failures were observed in the completed 8A suites. Physical input feel still needs human playtesting. Cell lookup is a linear scan (adequate at the measured 642/2,562 sizes); optional per-cell labels are a debugging tool. Current model assets have no supplied locomotion rigs/clips, so animation infrastructure is tested with a synthetic skeleton. The AI is the existing basic opponent and has not been redesigned or rebalanced.

The planet remains neutral with one terrain radius. No seed system, biomes, noise, elevation, rivers, lakes, resources, roads, terrain bonuses, fog, multiplayer or campaigns were implemented.

Minimum next step for **8B**: introduce a separate cell-ID-keyed planet-field container and deterministic 3D sampling from `center_direction`, using `sample_position` as the eventual elevation boundary. Preserve topology/version/fingerprint independently of generated fields. Stop here; 8B work is not included.
