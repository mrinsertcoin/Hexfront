# Hexfront Balance Report — Alpha 0.1

> All numbers are **provisional Alpha 0.1 values**. This file is generated from gameplay content by `scripts/tools/generate_balance_report.gd`.

## Baumeister

- Starting resources: 6 Energy, 20 Food, 20 Materials, 3 Unity
- Base production: 1 Food, 1 Materials
- Starting upkeep: 3 Food
- Expansion: Pillar costs 8 Materials plus 2 per bridge edge; 2 turns; 1 Materials/turn maintenance
- Research: 10 technologies; Industrial Foundations (Provisional) 4; Civic Services (Provisional) 4; Armored Fabrication (Provisional) 5; Deployed Artillery (Provisional) 6; Air Defense Preparation (Provisional) 5; Repair Doctrine (Provisional) 4; Command Network (Provisional) 6; Logistics Grid 5; District Specialization 6; Integrity Engineering 6

| Unit | Cost | Upkeep | HP | Move | Range | Damage | Important ability | Research requirement |
|---|---:|---:|---:|---:|---:|---:|---|---|
| Scout Trike | 1 Food, 3 Materials | 1 Food | 7 | 4 | 1 | 2 | reconnaissance | Available at start |
| Bridgewright | 2 Food, 4 Materials | 1 Food | 9 | 2 | 1 | 1 | engineer | Available at start |
| Conqueror Squad | 3 Food, 3 Materials | 1 Food | 11 | 2 | 1 | 3 | capture | Available at start |
| Assault Tank | 3 Energy, 8 Materials | 1 Materials | 18 | 2 | 1 | 5 | armored | Armored Fabrication (Provisional) |
| Long Range Tank | 5 Energy, 9 Materials | 1 Energy, 1 Materials | 12 | 2 | 1 | 2 | deployable artillery, deployed range 4 / damage 5 | Deployed Artillery (Provisional) |
| Anti-Air Tank | 4 Energy, 8 Materials | 1 Materials | 13 | 2 | 2 | 3 | anti air | Air Defense Preparation (Provisional) |
| Medic Squad | 1 Energy, 3 Food, 2 Materials | 1 Food | 8 | 2 | 1 | 1 | healer | Civic Services (Provisional) |
| Trike Commander | 3 Energy, 5 Materials, 6 Unity | 1 Food, 1 Unity | 12 | 3 | 2 | 3 | hero, designator | Command Network (Provisional) |

### Deterministic development comparison

| Measure | Approximate turn/value |
|---|---:|
| First additional production | Turn 3 |
| First military recruit | Turn 3 |
| First researched upgrade | Turn 5 |
| First expansion operational | Turn 3 |
| Representative midgame army | 9 Energy, 12 Food, 32 Materials; upkeep 1 Energy, 5 Food, 2 Materials |

## The Living Migration

- Starting resources: 20 Food, 8 Silk, 5 Synapse
- Base production: 3 Food, 2 Silk, 2 Synapse
- Starting upkeep: 4 Food
- Expansion: additional Spider costs 15 Silk, then +5 Silk per owned Spider; 2 turns
- Research: 12 technologies; Symbiotic Foundations (Provisional) 4; Ant Adaptation (Provisional) 5; Queen Signal 6; Migration Networks 5; Marsh Metabolism (Provisional) 5; Marsh Longevity 6; Directed Metamorphosis (Provisional) 5; Apex Metamorphosis 7; Controlled Virulence (Provisional) 5; Migration Efficiency (Provisional) 6; Regenerative Clearings 5; Synaptic Bloom 5

| Unit | Cost | Upkeep | HP | Move | Range | Damage | Important ability | Research requirement |
|---|---:|---:|---:|---:|---:|---:|---|---|
| Living Spider | 10 Silk | 2 Food | 25 | 4 | 1 | 2 | mobile headquarters, synaptic, terrain harvester | Available at start |
| Mite | 1 Food, 1 Synapse | 1 Food | 4 | 2 | 1 | 0 | synaptic, disease carrier | Available at start |
| Worker Ant | 2 Food, 1 Synapse | 1 Food | 6 | 2 | 1 | 1 | road builder | Available at start |
| Fighter Ant | 3 Food, 2 Synapse | 1 Food | 9 | 2 | 1 | 3 | standard combatant | Available at start |
| Fire Ant | 4 Food, 3 Synapse | 2 Food | 7 | 2 | 2 | 2 | standard combatant | Ant Adaptation (Provisional) |
| Ant Queen | 6 Food, 2 Silk, 5 Synapse | 2 Food, 1 Silk | 12 | 2 | 1 | 2 | hero, queen connection source | Queen Signal |
| Dragonfly | 3 Food, 2 Synapse | 2 Food | 6 | 4 | 1 | 3 | temporary, 5-turn lifespan | Marsh Metabolism (Provisional) |
| Mosquito | 2 Food, 1 Synapse | 1 Food | 4 | 4 | 1 | 2 | temporary, 4-turn lifespan | Marsh Metabolism (Provisional) |
| Poison Dart Frog | 5 Food, 3 Synapse | 3 Food | 8 | 2 | 2 | 3 | temporary, synaptic, 5-turn lifespan | Marsh Metabolism (Provisional) |
| Bullfrog | 7 Food, 4 Synapse | 4 Food | 13 | 2 | 1 | 4 | temporary, synaptic, 6-turn lifespan | Marsh Longevity |
| Unke | 8 Food, 2 Silk, 5 Synapse | 4 Food, 1 Silk | 11 | 3 | 2 | 3 | temporary, synaptic, hero, 7-turn lifespan | Marsh Longevity |
| Caterpillar | 4 Food | 3 Food | 7 | 2 | 1 | 1 | terrain harvester | Available at start |
| Brimstone Butterfly | 5 Food, 2 Synapse | 2 Food | 7 | 4 | 1 | 3 | standard combatant | Directed Metamorphosis (Provisional) |
| Fire Moth | 6 Food, 3 Synapse | 3 Food | 8 | 3 | 2 | 4 | standard combatant | Directed Metamorphosis (Provisional) |
| Admiral | 8 Food, 2 Silk, 5 Synapse | 3 Food, 1 Silk | 11 | 4 | 2 | 4 | hero | Apex Metamorphosis |

### Deterministic development comparison

| Measure | Approximate turn/value |
|---|---:|
| First additional production | Turn 3 |
| First military recruit | Turn 3 |
| First researched upgrade | Turn 5 |
| First expansion operational | Turn 6 |
| Representative midgame army | 24 Food, 2 Silk, 17 Synapse; upkeep 11 Food, 1 Silk |

## Simulation assumptions

Timings assume an uncontested opening, one relevant construction started as soon as affordable, no neutral rewards, no combat losses, and one research producer. They are deterministic comparison markers rather than predicted player outcomes.
