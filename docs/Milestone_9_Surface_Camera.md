# Milestone 9 — Surface-relative tactical camera

`SurfaceCamera` replaces the old planet-center orbit. It owns one normalized surface focus, a transported tangent heading, local yaw/pitch, current/target distance, focus travel, and entity-follow state. `PlanetBoard` routes input and supplies presentation-root positions. All settings live in `TacticalCameraConfig`; terrain, generation, gameplay rules, and animation remain independent.

## Navigation and framing

WASD/arrows pan along camera-relative surface tangents. Exponential acceleration is integrated over each frame, and world-space speed grows with zoom. Q/E and middle drag change local yaw; vertical middle drag clamps pitch to 25–80 degrees. Shortest-arc transport keeps the heading tangent without reconstructing global north at poles. Exact antipodes use the existing heading as a deterministic travel axis.

Left press records the actual displaced-terrain BVH hit and defers selection. Crossing five pixels cancels the click. During a drag, the rig rotates the current cursor hit toward the original grabbed direction; three short correction steps account for displaced terrain and perspective. Releasing below threshold executes the existing selection or recruitment interaction. Right click retains movement/attack/cancel behavior. An empty-cell click selects the cell without initiating camera focus.

Normal framing uses distance 10, 30-degree vertical FOV, and 80-degree pitch. Graphical tuning on the radius-12 development world required a steeper view than the proposed 45–60 degrees to hide the horizon while retaining readable units and useful local coverage. These are editable settings, not constraints on player orbit. Tactical scale stays in world units; radius-24/subdivision-4 uses the same local settings.

Wheel zoom is multiplicative and exponentially smoothed. Tactical/regional/strategic/planet labels describe one continuous range. At long distances, the aim point blends from terrain focus toward the planet center and the boom becomes radial. Maximum distance derives from the terrain's bounding radius and the viewport's limiting FOV, including portrait aspect ratios. There is no second globe controller.

## Focus and picking

Unit/HQ selection starts a short spherical focus transition and links the camera to that entity. F restores the link; with no selected entity it does nothing. Follow samples `EntityView.position`, never skeleton bones or an immediately committed destination. Manual pan, drag, yaw, and zoom unlink follow and interrupt travel. Interrupted pullback retains the displayed distance to avoid a sudden zoom jump.

Near transitions take roughly 0.22 seconds; full antipodal travel takes 0.85 seconds. Far travel temporarily pulls back and restores the user's zoom on arrival. Terrain height is sampled at the moving focus; a lightweight radial clearance constraint keeps the camera outside hills. Screen up comes from the transported tangent, including straight-down planet framing.

Terrain picking retains 8D's cached TriangleMesh BVH and authoritative polygon lookup. Selection/attack additionally test small presentation-root bounds before the terrain hit, allowing visible objects to take priority without selecting objects hidden behind the planet. This adds no physics colliders. F8 displays focus cell/direction, yaw, pitch, distance, band, entity, and follow state.

## Verification

`tests/camera_navigation.gd` runs headlessly or graphically, with `-- --dense` selecting radius 24/subdivision 4. It checks default terrain-filled viewport corners, six-hemisphere forward/right movement, pole crossing, frame-rate consistency, clearance, delayed clicks, subthreshold clicks, occupied/reachable/empty grab starts, grab accuracy, entity priority, selection/HQ focus, movement follow, manual unlink, F restoration, distant/antipodal travel, interruption, pitch/zoom clamps, and whole-planet framing. Graphical runs save `.godot/9_camera_*.png`, including travel, drag, follow, poles, and planet views.

`tests/run_all.ps1` runs import/parse and 16 regression suites. Existing sphere and displaced-terrain picking matrices retain independently positioned Camera3D fixtures; obsolete orbit-state assertions now check the surface rig. Authoritative gameplay tests remain in place.

Completed verification: import/parse and all 16 headless suites passed. Camera graphics tests passed with zero failures at both radius 12/642 cells and radius 24/2,562 cells, and the resulting tactical, pole, drag, transit, follow, and planet captures were inspected. The integrated gameplay graphical suite also passed at both sizes, including all procedural debug modes, seed pixel identity, movement, rear-side occlusion, AI return, and restart. Logs are `.godot/9_regression.log`, `.godot/9_camera_graphical.log`, `.godot/9_camera_graphical_dense.log`, `.godot/9_graphical.log`, and `.godot/9_graphical_dense.log`.

## Limitations

The development planet needs the steep default view described above. Lower manual pitch intentionally exposes the horizon. A drag pauses if the cursor leaves the visible globe and resumes when it returns; it never invents a rear-side grab. Entity picking uses inexpensive approximate presentation-root boxes rather than animated silhouette geometry. Physical mouse feel still benefits from user playtesting; automated graphics checks inject viewport events. No dynamic terrain LOD, minimap, strategic icons, or Milestone 10 work is included.
