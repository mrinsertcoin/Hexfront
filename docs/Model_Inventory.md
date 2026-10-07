# Hexfront Model Inventory

This inventory records Milestone 21A's recursive audit of `assets/factions/swarm/units/`. Model profiles are presentation-only resources loaded by `VisualMap`; gameplay definitions and stable unit IDs remain authoritative in `content/units/`.

## Living Migration roster mapping

| Gameplay unit | Stable visual ID | Authored source | Profile transform (scale, Y rotation, height) | Runtime result |
|---|---|---|---|---|
| Living Spider | `living_spider` | `spider/source/spider.glb` | 0.72, 180 degrees, 0.00 | Textured model; skin and 66-bone armature preserved |
| Mite | `mite` | `mite/source/mite.glb` | 0.18, 180 degrees, 0.11 | Textured static model |
| Worker Ant | `worker_ant` | `worker_ant/source/worker_ant.glb` | 0.38, 180 degrees, 0.21 | Textured static model |
| Fighter Ant | `fighter_ant` | `warrior_ant/source/warrior_ant.glb` | 0.42, 180 degrees, 0.32 | Clear role match; textured static model |
| Fire Ant | `fire_ant` | `fire_ant_flamethrowers/source/fire_ant_flamethrowers.glb` | 0.38, 180 degrees, 0.24 | Armed version selected for the ranged roster role |
| Ant Queen | `ant_queen` | `queen_ant/source/queen_ant.glb` | 0.50, 180 degrees, 0.37 | Textured static model |
| Dragonfly | `dragonfly` | `dragonfly/source/dragonfly.glb.glb` | 0.46, 180 degrees, 0.36 | Textured static model; source filename retained |
| Mosquito | `mosquito` | `mosquito/source/mosquito.glb` | 0.34, 180 degrees, 0.27 | Textured static model |
| Poison Dart Frog | `poison_dart_frog` | None | n/a | Existing generated placeholder retained |
| Bullfrog | `bullfrog` | None | n/a | Existing generated placeholder retained |
| Unke | `unke` | None | n/a | Existing generated placeholder retained |
| Living Caterpillar | `living_caterpillar` | `caterpillar/source/caterpillar.glb` | 0.45, 180 degrees, 0.20 | Textured static model |
| Brimstone Butterfly | `brimstone_butterfly` | None | n/a | Existing generated placeholder retained |
| Fire Moth | `fire_moth` | `firefly/source/firefly.glb` | 0.48, 180 degrees, 0.37 | Clear fiery winged role match; source name documented |
| Admiral | `admiral` | `admiral/source/admiral.glb` | 0.52, 180 degrees, 0.47 | Textured static model |

`fire_ant/source/fire_ant.glb` is also registered as the presentation-only ID `fire_ant_unarmed_variant`. It is not a gameplay unit and does not change the Fire Ant roster entry. There are no unmapped runtime GLBs in the audited tree. `firefly/source/firefly_rigged.blend` and its duplicated source textures are authoring sources, not runtime resources.

## Source model statistics

Statistics come from `tools/inspect_swarm_models.gd` after Godot import. Triangle counts describe the source assets and are not balance data.

| Source model | Triangles | Texture set | Rig / animation | GLB size | Review note |
|---|---:|---|---|---:|---|
| Admiral | 157,550 | 3 x 2048 | Static | 24.0 MB | Heavy for a tactical unit |
| Caterpillar | 148,756 | 3 x 2048 | Static | 23.8 MB | Heavy for a tactical unit |
| Dragonfly | 116,072 | 3 x 2048 | Static | 23.5 MB | Heavy for a tactical unit |
| Fire Ant | 263,886 | 3 x 2048 | Static | 28.6 MB | Unassigned variant; very heavy |
| Fire Ant with flamethrowers | 540,140 | 3 x 2048 | Static | 40.4 MB | Highest geometry cost; optimization recommended before production armies |
| Firefly / Fire Moth | 170,396 | 3 x 2048 | Static | 26.0 MB | Heavy for a tactical unit |
| Mite | 393,976 | 3 x 2048 | Static | 32.1 MB | Very heavy relative to its small screen size |
| Mosquito | 163,212 | 3 x 2048 | Static | 23.4 MB | Heavy for a tactical unit |
| Queen Ant | 333,362 | 3 x 2048 | Static | 31.8 MB | Very heavy |
| Spider | 10,231 | 3 x 4096 | 1 skin, 66 bones, no clips | 30.5 MB | Efficient geometry; high texture memory; armature retained |
| Warrior / Fighter Ant | 316,438 | 3 x 2048 | Static | 30.8 MB | Very heavy |
| Worker Ant | 256,800 | 3 x 2048 | Static | 28.5 MB | Very heavy |

All twelve GLBs contain one mesh and one material. The imported materials and textures are preserved; team identity remains on the existing external ownership ring instead of overwriting authored PBR materials. No animation clips were found, so Milestone 21A does not add or fabricate animation.

## Validation and review workflow

- `tests/model_assets.gd` rejects missing profiles, duplicate IDs, broken model paths, failed instantiation, accidental gameplay IDs, and changed roster mappings.
- `tests/swarm_models_graphical.gd` builds a normal spherical match, places all 15 roster units together, checks profile transforms, radial placement, ownership markers, movement compatibility, removal and respawn, and saves `.godot/21a_swarm_roster.png`.
- `tools/preview_swarm_assets.gd` saves a neutral raw-source contact sheet at `.godot/swarm_asset_inventory.png`.
- `tools/inspect_swarm_models.gd` recursively reports source bounds, triangles, materials, textures, skins, bones, and animation clips.

The model profiles affect only nodes under each entity's `ModelRoot`. Logical cell IDs, movement, combat, fog, network observations, selection, health, and faction content remain independent of these resources.
