# Movement presentation and rig integration

Implemented and checked with Godot 4.6.2, Compatibility. Updated for the Milestone 8A spherical graph migration on 27 September 2026.

## Existing GLB inspection

All five files are static meshes. Raw GLB JSON and Godot's imported scene hierarchy agree:

| File in assets/ | Skins | Joint bones | Weighted mesh primitives | Animation clips |
|---|---:|---:|---:|---:|
| hx_infantry_v1.glb | 0 | 0 | 0 | 0 |
| hx_scout_v1.glb | 0 | 0 | 0 | 0 |
| hx_gunner_v1.glb | 0 | 0 | 0 | 0 |
| hx_gunner_.glb (unused variant) | 0 | 0 | 0 | 0 |
| hx_hq_v1.glb | 0 | 0 | 0 | 0 |

Multiple mesh parts in a GLB are not a skeleton. None of these imports contains a Skeleton3D, skinned MeshInstance3D, or animation clip. Existing binaries and textures were not modified.

Repeat the inspection after adding models:

```powershell
$godotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
& $godotExecutable --headless --path . --editor --import
& $godotExecutable --headless --path . --script res://tools/inspect_models.gd
```

## Implemented behavior

- Rules immediately commit an accepted move's destination and action cost, exactly once. `EntityView` receives the accepted cell-ID path, immutable PlanetGrid and radial surface offset. It follows every waypoint along spherical arcs at a configurable visual speed, including detours. Long frames carry remaining travel through corners without cutting across blocked tiles.
- The entity frame keeps local +Y radial and smoothly turns local -Z toward travel. Units, HQs and health bars align with the local surface, including the bottom hemisphere. HUD refresh and inspection do not snap moving units to their logical destination.
- `UnitVisual` discovers an AnimationPlayer beneath the wrapper or uses an explicit path. It blends between in-place Idle and Move clips. Walk, Run, Crawl, and Hop are supported fallback names, including namespaced clips. Exact clip names can be set in the Inspector.
- Clip resources are duplicated per instance before enabling looping. Skeletons, imported track paths, and ModelRoot corrections remain intact. Static models move and turn without fabricated limb animation. Missing idle stops locomotion safely.
- While any unit is moving, human move/attack/recruit/end-turn requests wait; highlights and End Turn are disabled. Camera movement, inspection, Escape and starting a new match remain available. AI awaits movement before its next command. Restart/new match invalidates old AI work; removal/death discards the old view without retaining an input lock.
- Attacks and death still resolve/display immediately. Their animation choreography is a later integration task. There is no root-motion-driven gameplay or new faction content.

## Queen ant, frog and spider handoff

Supply each model as a GLB with its skeleton, skin weights, and preferably **in-place Idle and Move clips**. A rig alone does not include walking/crawling animation. Optional Attack and Death clips can be supplied now for later integration. Use +Y up, -Z forward, ground-level origin. Keep translation out of the locomotion root; body bounce/leg movement can remain inside the rig. A frog's jump cycle can use a custom Move clip name; match its cycle and visual speed when the model arrives.

For each model:

1. Import and run the inspection command above. Confirm skins, weighted primitives, bones and clip names.
2. Instance the GLB under a unit wrapper's `ModelRoot`. Authored content takes precedence over fallback assets. Put scale/orientation corrections on ModelRoot, outside the imported skeleton hierarchy.
3. Attach `scripts/view/unit_visual.gd` to the wrapper root (the existing three military wrappers already use it). Set `move_speed`, `idle_clip`, `move_clip`, `blend_seconds`, and optionally `animation_player_path` relative to that wrapper. The default speed is 4 world units/second. Tune against the actual stride to reduce foot sliding.
4. Point `VisualMap` at the wrapper once the creature's gameplay role is agreed. Queen ant, frog and spider names do not yet introduce new stats or rules. Current headquarters remain stationary; a future mobile spider can reuse the presenter when its movement rules are implemented.
5. Check footprint, turning, skin deformation, looping, idle transitions and both team colors in game. Start with one representative rig, then apply the proven setup to the other two. Retargeting, procedural IK and AnimationTree complexity are not needed for this first integration.

## Validation and manual acceptance

Passed import/parse and all eleven headless suites. The new animation suite covers path corners, frame-size consistency, facing, immediate logical commitment, no repeated state changes, redraw preservation, input gating, actual scene-tree advancement, AI waiting/completion, cancellation, explicit/namespaced clips, isolated animation resources and a test Skeleton3D bone track.

Also passed the animation suite graphically using Compatibility, inspected a captured in-motion frame (`.godot/movement_midway.png`), and launched the normal main scene for 120 frames without engine/script errors. This does not verify physical input or deformation on models that have not been supplied.

Manual check: F5, choose **Hotseat (new)**, select P1 Scout, hover an empty reachable cell several steps away, then right-click. It should follow the cyan path, turn, and land exactly on the destination; End Turn should read **Moving...** until arrival. Try another action during motion; it should be rejected without spending anything. Orbit while it moves, then move the other unit. End both turns to restore actions. In **Vs AI (new)**, end your turn and check that enemy movement finishes before its next action. Start a new match mid-move and check the initial setup is restored.

Changed files for this work: `scripts/view/entity_view.gd`, `unit_visual.gd`, `board_view.gd`; the three military wrappers in `scenes/visuals/units/`; `tests/animation.gd`, `hotseat.gd`, `combat_ui.gd`, `economy_ui.gd`, `run_all.ps1`; `tools/inspect_models.gd`; README, asset contract and this document. Godot also generates script `.uid` sidecars. Existing synchronous UI regression suites explicitly disable movement presentation; the new suite exercises it enabled. That earlier rig-only change left core gameplay unchanged. Milestone 8A subsequently migrated state/rules to cell IDs and graph traversal; see Milestone_8A_Recovery.md for the current architecture and verification.
