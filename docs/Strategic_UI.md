# Milestone 15 — Strategic UI, Research & Production Management

Milestone 15 reorganizes the in-match interface around the authoritative M13–M14 content and rule systems. It does not add faction mechanics or change balance.

## HUD structure

`PlanetBoard` owns ephemeral presentation state and builds five named regions under its `CanvasLayer`:

- **TopBar** shows the active faction, controller, round, faction-defined stored resources, projected income/upkeep/net values, active research, Research, and End Turn.
- **SelectionPanel** resolves units, structures, districts, and world sites from their definitions and runtime state. Integrity, Connection, supply, diseases, deployment, construction, and relationships stay local to the selected object.
- **ActionBar** contains context actions and production cards. Buttons dispatch `GameRules` commands; disabled buttons retain the authoritative failure reason in their tooltip.
- **StrategicPanel** presents the active faction's definition-driven technology tree with locked, available, researching, and completed states, prerequisites, costs, descriptions, and unlocks.
- **Notifications** keeps a bounded match-local feed with info, success, warning, and critical severities. Entries may hold a logical entity or cell ID for camera focus and never retain scene nodes.

The layout is recalculated from viewport dimensions and the persisted interface-scale setting. It is intended for 1280×720 through 2560×1440. UI construction and refresh happen on state changes; no tree or production list is rebuilt every frame.

Gameplay definitions expose an optional `icon_path`. `ContentIcon` loads that texture when present; controls retain their complete text label when art is absent or invalid, so icon work can be added incrementally without changing UI logic.

## Interaction modes and overlays

`StrategicInputMode` centralizes normal, move, attack, recruit, road, Pillar/bridge, heal, repair, and designate modes. The board stores only the active mode, a logical source ID, and transient path cells. Every accepted action still goes through `GameRules`.

Right click or Escape cancels the current mode before ordinary input or Pause handling. Recruitment uses green cells, roads and construction use gold/orange, healing uses teal, repair uses orange, designation uses red, movement uses green, paths use cyan, and attacks use purple. Pillar planning previews the authoritative bridge path, cost, and construction time before dispatch.

## Faction management

Living Migration Spider selection shows all nine internal slots, the permanent nursery branch warning, brood costs and time, timed and nutrient progress, held deployment, mites, Spider construction, Connection, road mode, lifespan, diseases, and terrain/corpse actions.

Baumeister Pillar selection shows Integrity separately from HP, supply and maintenance, district cells and construction, bridge connections, expansion planning, repair, and a supply overlay toggle. Recruitment continues to use district capability rules, so Barracks and Workshop availability and every locked reason come from the existing rules.

## Controls

- **R:** open or close Research.
- **P:** focus the current context actions/production.
- **Tab / Shift+Tab:** cycle forward/backward through the active controller's units.
- **Enter:** end the current human turn.
- **Escape / right click:** cancel targeting or placement first; Escape opens Pause only when no interaction mode is active.

The existing camera, debug, selection, movement, attack, and pause controls remain unchanged.

## Verification

`tests/strategic_ui.gd` covers faction-generated resource bars, economy tooltips, research states and prerequisites, locked production reasons, resolved selection statistics, Spider slots, Pillar state, mode cancellation, active-turn HUD switching, generic world-site selection, notifications, and supported layout sizes. `tests/strategic_ui_graphical.gd` captures Living Migration actions and notifications, both faction research panels, and the Baumeister Pillar action view at 1280×720.

Run the complete headless suite with `tests/run_all.ps1`. Run the graphical milestone check with:

```powershell
& $godotExecutable --path . --script res://tests/strategic_ui_graphical.gd --quit-after 5000
```
