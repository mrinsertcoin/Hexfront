# Stylized environment kit

Runtime content is copied from `art_source/meshy_lods`; the game never loads from the source tree. Each accepted asset has the supplied 8,000 / 3,500 / 1,200 triangle LOD0/LOD1/LOD2 sequence and a clear runtime name.

| Source | Runtime asset | Category |
| --- | --- | --- |
| 005 | `forest_tree_canopy_01` | tree |
| 008 | `conifer_pair_01` | tree pair |
| 009 | `forest_tree_branching_01` | tree |
| 010 | `deadwood_01` | debris |
| 011 | `woodland_bush_01` | bush |
| 012 | `ground_cover_01` | ground cover |
| 013 | `boulder_01` | boulder |
| 017 | `rock_formation_01` | formation |

Candidates 001–004, 006–007, and 014–016 remain source-only. They were rejected because their isolated silhouette was unclear, combined unrelated terrain fragments, repeated an accepted form without useful variation, or did not survive decimation cleanly enough for tactical use.

The resolver grounds and centers each supplied mesh, normalizes metallic/roughness/normal response, and applies only restrained shared-palette tint. Scale remains a per-asset presentation setting. Trees, boulders, and formations cast shadows; smaller cover does not.
