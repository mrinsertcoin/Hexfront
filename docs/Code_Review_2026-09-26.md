# Code review - 26 September 2026

Reviewed every current GDScript file, project/main scene, visual wrapper, fallback model scene, existing tests, README, and the design brief. Loaded all 14 scene/model resources and ran the installed Godot 4.6.2 Compatibility renderer.

## Assessment

The core separation of logical state from scene nodes is sound. Movement uses deterministic BFS, and both humans and AI apply gameplay through the same rules. However, the newer integration had blocking input, presentation, and restart regressions, and documentation overstated verification. Existing tests initially failed; one script crashed yet returned exit code zero.

The prototype now passes the reviewed gates. The board script still combines camera, UI, view creation, input and AI scheduling; separating these responsibilities is the next maintainability improvement. AI tactics remain intentionally basic.

## Fixes applied

- Right-click attacks now accept headquarters as well as military units.
- Left/right actions execute on press only. Release no longer repeats attacks, changes selection after placement, or falls through from cancellation.
- Recruitment retains the exact selected HQ, consumes authoritative validation, clears stale modes/highlights on cancel/turn/restart, and displays costs, stats, balances and Ready next turn.
- Initial income now agrees between direct core initialization and scene/restart initialization. Turn-start effects are idempotent; recruitment uses centralized costs and validates HQ type.
- ID allocation skips existing military and structure IDs.
- Camera initialization/Home/restart restore the complete orbit rig. Yaw interpolation converts degrees to radians correctly. Lost middle-button releases cannot leave orbit dragging stuck.
- Cyan path preview is no longer hidden by the green reachable material.
- Removed competing visual rebuild paths. Every unit/HQ receives one model and one functioning health bar on initial spawn, recruitment and restart.
- Authored ModelRoot children are preserved. Team tint changes only accent materials, recursively, including supported shader uniforms. Team rings keep ownership visible on assets without accent slots.
- Four unused fallback scenes contained invalid inline resource syntax; they now load normally. Unknown visual mappings return null safely.
- Restart has one button connection and clears stale HQ selection and recruitment. AI cancellation cannot let old work continue into a new match.
- AI scheduling no longer runs as a side effect of UI refresh. Human End Turn is blocked during AI control; bounded AI turns consistently refresh the UI on completion.
- AI recruitment preferences now advance after accepted recruitment. AI entry points use typed state/rules.
- Restored HQ victory/restart coverage in older UI tests; selected Hotseat explicitly for human input tests. Model assertions now check imported wrappers rather than superseded primitive meshes.
- Added full-state snapshots covering structures, balances, IDs, readiness and income markers. Added a runner that checks engine errors and test completion, not only process exit codes.
- Updated obsolete README controls, victory rules and claims that economy/AI were absent.

## Verification actually run

- Godot 4.6.2 import/parse: passed.
- Nine suites via tests/run_all.ps1: smoke, movement, hotseat, combat, combat_ui, economy, economy_ui, ai, resources. All passed with no script/engine errors.
- Resource loading: 14 scene/GLB resources, including every fallback and wrapper, plus shader accent cloning.
- AI versus passive opponent: Player 2 won in round 12, 126 actions.
- AI versus AI: Player 2 won in round 23, 404 actions.
- Blocked AI and restart during queued/in-progress AI work: passed.
- Synthetic mouse/keyboard events: recruitment cancellation/placement, immutable rejection, HQ damage/victory, restart, UI click consumption, camera reset/yaw, and path color.
- Standard six-unit scripted battle followed by HQ destruction and repeated restart: passed.
- Normal graphical main-scene launch for 120 frames and graphical synthetic combat/victory capture: passed with Compatibility OpenGL on Radeon RX 590.
- Starting/HQ, combat preview and victory frames were visually inspected.

Physical desktop input at the user's window size is not verified. AI strength, balance, long-session performance and future rig compatibility need later playtesting. Animations are not implemented yet.

## Files changed

- scripts/core/game_state.gd, scripts/core/rules.gd
- scripts/ai/simple_ai.gd
- scripts/view/board_view.gd, scripts/view/visual_map.gd
- Four assets/models/hx_*_v1.tscn fallback scenes
- tests/movement.gd, tests/hotseat.gd, tests/combat.gd, tests/combat_ui.gd
- New tests/test_state.gd, tests/economy.gd, tests/economy_ui.gd, tests/ai.gd, tests/resources.gd, tests/run_all.ps1 and generated script UID files
- README.md, assets/ASSET_CONTRACT.md, this review

The original faction brief, hex math, original smoke test, project/main scene, GLBs and textures remain unchanged. Pre-edit copies of modified existing source/test/fallback files are kept in ignored .godot/review_backup.

## Recommended next steps

1. Add path-driven visual movement and an EntityView animation interface before adding more gameplay systems. Keep rule application immediate and independent of playback; queue presentation for both human and AI actions.
2. Integrate one supplied rigged unit end to end (idle, locomotion, facing, attack, death), then apply the same wrapper/interface to almost all moving units. Agree on animation names and in-place/root-motion conventions first.
3. Extract camera, HUD/human input, entity views and AI turn scheduling from the board script; retain the regression suite through that refactor.
4. Create a Git baseline, make a Windows export, and playtest complete matches for AI decisions, pacing and readability before expanding faction/economy scope.
