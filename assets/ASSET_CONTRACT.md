# Hexfront Model Pack v1 — Asset Contract

These are first-pass low-poly GLB assets for the current Hexfront roster.

## Files
- hx_infantry_v1.glb
- hx_scout_v1.glb
- hx_gunner_v1.glb
- hx_hq_v1.glb

## Coordinate / import conventions
- Godot units: treated as meters.
- Ground plane: Y = 0.
- Up axis: +Y.
- Forward direction: -Z.
- Origin: centered on the unit/structure footprint at ground level.
- Models contain no gameplay logic and should be wrapped by presentation-only Godot scenes.

## Material naming
The pack uses a small shared semantic palette:
- HX_Body
- HX_DarkMetal
- HX_TeamAccent
- HX_Emissive
- HX_Warning

For team ownership, override only `HX_TeamAccent` (and optionally emissive color) in the Godot wrapper.
Do not duplicate the entire model per player.

## Intended visual roles
- Infantry: medium armored biped, general-purpose frontline silhouette.
- Scout: light quadruped recon walker, narrow/light silhouette and sensor mast.
- Gunner: slow tracked support platform with a long ranged cannon.
- HQ: broad fortified bunker/command tower with antenna and power modules.

## Godot wrapper recommendation
Create presentation scenes such as:
- scenes/visuals/units/infantry_visual.tscn
- scenes/visuals/units/scout_visual.tscn
- scenes/visuals/units/gunner_visual.tscn
- scenes/visuals/structures/hq_visual.tscn

Each wrapper should:
1. Instance the imported GLB.
2. Apply scale only in the wrapper if board scale requires adjustment.
3. Apply Player 1 / Player 2 accent material overrides.
4. Contain selection/health/damage VFX hooks.
5. Contain no movement, damage, ownership, economy, or combat rules.

These assets are deliberately first-pass silhouettes. They are designed to validate the pipeline and can later be swapped for Blender-authored production models without changing gameplay code.


## Rigged units and movement animation direction

Almost all moving military units are intended to animate. The user will supply rigged models for each unit. Keep the existing +Y up, -Z forward, ground-origin convention; put scale/orientation adjustments on ModelRoot and preserve the imported skeleton hierarchy and animation track paths.

Plan for in-place clips named Idle, Move (walk/run/crawl as appropriate), Attack and Death, or provide an explicit per-model name mapping. Locomotion should loop and face the direction of travel. Headquarters can remain stationary. Test one representative rig before standardizing every unit.

The authoritative move command returns the accepted axial path. `EntityView` now follows those waypoints while the logical destination/action state is committed by rules; `UnitVisual` plays Idle/Move clips when supplied. Animation completion never applies movement, damage, resource changes or income a second time. Avoid gameplay driven by root motion.

Presentation serializes human/AI actions, finishes movement safely, discards stale playback on death/restart/new match, and returns to idle. Model replacement must not duplicate meshes, HUD, signals or AnimationPlayers. Current code retains authored ModelRoot children and imported rig hierarchies.

The upcoming supplied models are the queen ant, frog and spider. A rig needs skin weights and locomotion clips to animate; all five existing GLBs are currently static. See [movement and rig integration](../docs/Movement_and_Rig_Integration.md) for inspection results, wrapper settings, and the handoff checklist. Put import scale/orientation corrections on ModelRoot; leave wrapper yaw available for travel facing. Attack/Death clips remain reserved for later presentation work.
