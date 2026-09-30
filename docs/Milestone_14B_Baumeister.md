# Milestone 14B — Baumeister

The production content ID is `baumeister`. It uses the shared registry, player resources, research, relationships, occupancy, turn sequencing, stat resolver, recruitment facade, and generalized headquarters victory. `F1.txt` was unavailable during implementation; the accepted revised faction brief and Milestone 14B specification therefore govern this delivery.

## Source-defined mechanics

- Food, Materials, Energy, and Unity are stored faction resources. Integrity is a local condition on each Pillar City, separate from HP and never an empire currency.
- The initial Pillar is an independent supply origin. Further Pillars require a Bridgewright, a supplied origin, bounded placement, Materials, and an authoritative logical bridge path with construction time.
- Completed, living bridges form one deterministic supply graph. Destroying a bridge isolates downstream Pillars without destroying them or stopping their local production; repairing the same bridge record restores supply.
- Mines, Greenhouses, Power Plants, Civic Monuments, Barracks, Hospitals, and Workshops occupy one neighboring district cell owned by one Pillar. They construct over time and have distinct production, recruitment, research, healing, or repair roles.
- Bridgewrights construct and repair infrastructure and perform limited vehicle repair. Medics and Hospitals heal only biological units; Workshops repair and produce vehicles.
- The active roster is Scout Trike, Bridgewright, Conqueror Squad, Assault Tank, Long Range Tank, Anti-Air Tank, Medic Squad, and Trike Commander. Long Range Tanks switch between MOBILE and DEPLOYED; only DEPLOYED grants artillery range. The Commander applies bounded, non-stacking target designation.
- Supplied operational bridge edges use deterministic weighted movement without changing `PlanetGrid` topology. Ordinary movement retains its previous reach.
- Multiple Pillars use the generalized rule: defeat occurs only when no headquarters-class Pillar remains.

## Provisional development defaults

All values below live in typed `.tres` content or `BaumeisterConfig` and are development tuning rather than final balance.

| Setting | Default |
|---|---:|
| Starting Food / Materials / Energy / Unity | 20 / 20 / 6 / 3 |
| Pillar HP / Integrity | 30 / 20 |
| Maximum bridge distance | 4 cells |
| Bridge cost | 2 Materials per edge + 8-Material Pillar |
| Bridge build time / HP / maintenance | 2 turns / 12 / 1 Material |
| Neglected Integrity loss | 1 per unpaid bridge turn |
| Ordinary / bridge edge cost | 2 / 1, with doubled movement budget |
| Repair cost / amount / supplied bonus | 1 Material / 3–4 / +1 |
| Designation | range 3, duration 2, +1 damage |
| District build time | 2 owner turns |
| Hero limit | 1 |

Unit statistics and costs, district output, technology names/costs, Integrity damage ratio, maintenance, and starting values are also provisional. Scout Trike is the single initial reconnaissance role; Entdeckersquad differentiation is deferred.

## Deferred

Transport Tank/passengers, pillar artillery, air units and full AA interception, Panzersquad, Deathsquad, Botschafter, Aufseher, full territorial capture, empire directives, final hero progression, final balance/art, diplomacy, and multiplayer remain deferred. No global city-count Integrity decay was added.
