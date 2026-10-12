# Milestone 15 — Strategic UI, Research & Production Management

Milestone 15 reorganizes the in-match interface around the authoritative M13–M14 content and rule systems. It does not add faction mechanics or change balance.

## HUD structure

`PlanetBoard` owns ephemeral presentation state and builds five named regions under its `CanvasLayer`:

- **TopBar** shows the active faction, controller, round, faction-defined stored resources, projected income/upkeep/net values, active research, Research, and `End Movement Phase`. Combat orders resolve automatically after the final living player finishes movement.
- **SelectionPanel** resolves units, structures, districts, and world sites from their definitions and runtime state. A selected unit gets one opaque bottom-left tactical card: identity and role, a rotating isolated model preview, HP and squad strength, resolved combat statistics, queued intent, grouped actions, compact status badges, and contextual detail. Integrity, Connection, supply, diseases, deployment, construction, and relationships stay local to the selected object.
- **ActionBar** contains context actions and production cards. Buttons dispatch `GameRules` commands; disabled buttons retain the authoritative failure reason in their tooltip.
- **StrategicPanel** presents the active faction's definition-driven technology tree with locked, available, researching, and completed states, prerequisites, costs, descriptions, and unlocks.
- **Notifications** keeps a bounded match-local feed with info, success, warning, and critical severities. Entries may hold a logical entity or cell ID for camera focus and never retain scene nodes.

The layout is recalculated from viewport dimensions and the persisted interface-scale setting. It is intended for 1280×720 through 2560×1440. UI construction and refresh happen on state changes; no tree or production list is rebuilt every frame.

The selection card has a fixed 340-unit width (scaled only by the interface preference). Contents grow it upward from the bottom-left anchor; it stops below the top bar and uses vertical scrolling for overflow. Preview minima, wrapped notes, queued orders and clipped city buttons prevent rightward expansion. Redundant detailed statistics are behind a Details disclosure, and empty preview/feedback rows consume no space.

`StatIcons` supplies a reusable SVG set under `assets/ui/stats/` for health, group size, armour, damage, movement, attack range, vision, detection, slots and time. Both icons and adjacent values accept hover and explain their current values. Armour reports the authored classification or an unavailable numeric rating rather than inventing damage reduction.

Gameplay definitions expose an optional `icon_path`. `ContentIcon` loads that texture when present; controls retain their complete text label when art is absent or invalid, so icon work can be added incrementally without changing UI logic.

Living Migration research now uses the [Root of Knowledge](Living_Research_Roots.md):
15 gameplay unlocks arranged as a scrollable, zoomable organic root system,
with strict prerequisites, animated sap, living frame accents and bundled
Cinzel Decorative typography. The diagram and backend share the same authored
definitions. Inspection preserves node focus; locked roots remain inspectable
and explain exactly which prerequisite is missing.

`ModelPreview` renders the definition's real visual in its own `SubViewport` and world. It derives framing from the visual's mesh bounds, rotates slowly, and accepts optional per-visual preview scale, rotation, vertical offset, and camera distance metadata for exceptional assets. It never reuses the tactical camera or world entity node.

## Interaction modes and overlays

`StrategicInputMode` centralizes normal, move, attack, recruit, road, Pillar/bridge, heal, repair, and designate modes. The board stores only the active mode, a logical source ID, and transient path cells. Every accepted action still goes through `GameRules`.

The tactical card is presentation-only. Attack enters the existing target mode, stance buttons submit the existing simultaneous-combat command, and queued orders expose the existing cancellation path. Buttons remain visible when unavailable and explain the authoritative reason in their tooltip. Clicking or scrolling the card is consumed by the UI and cannot issue a world command.

Enemy cards show only currently observable facts. They omit queued intent, cooldowns, development, disease, designation, Connection state, and other owner-only runtime details. A lost contact uses the historical-contact card and never resolves a live entity for display.

Right click or Escape cancels the current mode before ordinary input or Pause handling. Recruitment uses green cells, roads and construction use gold/orange, healing uses teal, repair uses orange, designation uses red, movement uses green, paths use cyan, and attacks use purple. Pillar planning previews the authoritative bridge path, cost, and construction time before dispatch.

## Faction management

Living Migration Spider selection shows all nine internal slots, the permanent nursery branch warning, brood costs and time, timed and nutrient progress, held deployment, mites, Spider construction, Connection, road mode, lifespan, diseases, and terrain/corpse actions.

Spider production, internal construction, new-Spider growth/deployment, brood deployment and research are all inside the unit card's SPIDER CITY section. Costs, nursery capacity, research locks, occupied slots and construction conflicts disable the corresponding controls with hover reasons. The P shortcut focuses the card's first usable city/tactical action. City information remains inspectable while actions are disabled.

Baumeister Pillar selection shows Integrity separately from HP, supply and maintenance, district cells and construction, bridge connections, expansion planning, repair, and a supply overlay toggle. Recruitment continues to use district capability rules, so Barracks and Workshop availability and every locked reason come from the existing rules.

## Controls

- **R:** open or close Research.
- **P:** focus the current context actions/production.
- **Tab / Shift+Tab:** cycle forward/backward through the active controller's units.
- **Enter:** finish the local player's movement planning; other humans continue until ready.
- **Escape / right click:** cancel targeting or placement first; Escape opens Pause only when no interaction mode is active.

The existing camera, debug, selection, movement, attack, and pause controls remain unchanged.

## Verification

`tests/strategic_ui.gd` covers faction-generated resource bars, economy tooltips, research states and prerequisites, locked production reasons, resolved selection statistics, live HP and squad refresh, target-mode attack dispatch, queued-order cancellation, input consumption, enemy-data safety, Spider slots, Pillar state, generic world-site selection, notifications, and supported layout sizes. `tests/strategic_ui_graphical.gd` validates rotating/framed Worker Ant, Fighter Ant, Dragonfly, and enemy Baumeister previews; captures the unit card at 1280×720, 1920×1080, and 2560×1440; and retains both faction research and management captures.

Run the complete headless suite with `tests/run_all.ps1`. Run the graphical milestone check with:

```powershell
& $godotExecutable --path . --script res://tests/strategic_ui_graphical.gd --quit-after 5000
```
