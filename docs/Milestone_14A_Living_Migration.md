# Milestone 14A — The Living Migration

The production content ID is `living_migration`. It uses the Milestone 13 registry, player resources, research, relationships, occupancy, turn sequence, stat resolver, and command facade. The faction can be selected against either prototype faction from Match Setup. `F1.txt` was not present in the repository, supplied attachments, or user profile during implementation; the accepted revised faction brief and the Milestone 14A specification therefore governed this delivery.

## Source-defined mechanics

- Food, Silk, and Synapse are stored resources. Synapse remains independent from positional ant Connection.
- Living Spiders are four-movement mobile headquarters with nine internal slots, one nursery branch, fresh-terrain harvesting, renewable production, scalable Spider construction, and visible mite progress.
- A moved Spider pauses construction, mite production, and nursery development for that turn. Research-building progress continues.
- Ant Hill, Marsh, and Caterpillar Foliage use shared biological production state. Ants persist; mature larvae may be held and deploy as finite-lifetime forms; field caterpillars require both development and harvested nutrients before transformation.
- Ant roads are authoritative cell infrastructure. Workers extend up to three contiguous cells per turn. Worker and Queen movement uses active roads. Disconnected ants show a countdown, lose offensive orders after two disconnected turns, and deterministically retreat or hold.
- Eligible corpses have one visible Food value and may be consumed once by a nearby ant.
- Mites select Tracking, Weakening, or Wasting instead of movement. Exposure occurs at the owner's end turn, only one disease is active, and expiry grants immunity to that disease alone.
- The faction loses only when it has no surviving headquarters-class Spider.

## Provisional development defaults

These values are authorable in `.tres` definitions or the embedded `LivingMigrationConfig`; they are implementation defaults, not final balance.

| Setting | Development default |
|---|---:|
| Starting Food / Silk / Synapse | 20 / 8 / 5 |
| Spider HP / damage / Food upkeep | 25 / 2 / 2 |
| Spider Food / Silk / Synapse production | 3 / 2 / 1 |
| Fresh-terrain Food yield | 4 |
| Regrowth | 3 rounds |
| Spider Silk cost | 10 + 5 per currently owned Spider |
| Spider / internal construction | 2 / 2 stationary turns |
| Internal building Food cost | 3 |
| Mite interval | 3 stationary turns; upgrade 2 |
| Hill / Queen Connection range | 2 / 2 cells |
| Ant-road cost | 0 Food during development |
| Research per research building | 1 per owner turn |
| Disease durations | Tracking 2, Weakening 2, Wasting 3 turns |
| Disease immunity | 2 turns per disease |
| Weakening / Wasting | −2 attack / 1 damage per turn |

All unit combat values, recipe costs and development times, temporary lifetimes, corpse Food values, and research costs are likewise provisional content. The current Food-shortage rule pays what is available, records the unpaid amount for UI/diagnostics, and applies no starvation penalty or deletion. Mites are provisionally disease-susceptible because the source leaves that exception unresolved.

## Presentation and current limits

The selected-Spider panel exposes resources, expected production, upkeep, movement, slots, branch storage/progress, mite progress, construction, research, and legal first-pass action buttons. Cell overlays show active roads, connected ants, depleted terrain, and regrowth. Distinct primitive placeholders are used where final models are absent.

Deferred work remains: final balance and art, hero caps/leveling, morale penalties, full fog of war, advanced road and disease AI, terrain eligibility by biome, starvation consequences, zombie/movement/armor diseases, structural infection, diplomacy, multiplayer, and Baumeister mechanics.
