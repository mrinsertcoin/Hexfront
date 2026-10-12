# Terrain material library

Uploaded archives are retained under `source/archives`; their material preview renders are under `source/previews`. `source/.gdignore` excludes authoring archives/previews from runtime import. No source images were resized or painted over. The duplicate Ground082S archive is preserved too.

Source ZIP archives, alternate material PNGs and unused PBR channels are local
authoring assets excluded from Git. Only the five active `albedo.png` textures
listed below and their `.import` settings are versioned. A fresh clone contains
everything needed for current terrain rendering, but not the original archives
or optional PBR/alternate textures. Keep a separate backup of local source art;
it is not backed up by a push. Preview renders remain versioned for reference.

Extracted PNGs have consistent role names: `albedo`, `normal_gl`, `normal_dx`, `roughness`, `ao`, `height`, and optional `metalness` / `id_mask`.

| Original material | Organized location | Role |
| --- | --- | --- |
| Grass007 | `materials/grassland/grass` | Active grassland |
| Ground037 | `materials/grassland/moss` | Alternate moss |
| Ground082S | `materials/forest/soil` | Active forest floor |
| ScatteredLeaves008 | `materials/forest/leaves` | Alternate leaf litter |
| Ground080 | `materials/dryland/sand` | Active dryland |
| Ground109 | `materials/dryland/stony_soil` | Alternate dry ground |
| Rock051 | `materials/rocky/slate` | Active rocky terrain/cliff faces |
| Ground081 | `materials/rocky/rubble` | Alternate rocky ground |
| Gravel020 | `materials/rocky/coarse_gravel` | Alternate coarse gravel |
| Gravel022 | `materials/rocky/fine_gravel` | Alternate fine gravel |
| Ground023 | `materials/wetland/leaf_mud` | Active wetland |

Runtime imports use GPU compression and a 1024-pixel size limit. Production terrain blends the five active albedos with restrained biome tint using seamless triplanar coordinates. The supplied displacement maps are retained as source material, but do not perturb terraces: physical elevation comes exclusively from the four-layer terrain/ramp generator. Additional PBR channels are retained for future material tuning without adding expensive per-pixel displacement or changing ramp angles.

See [terraced terrain](../../docs/Terraced_Terrain.md) for generation, movement, grounding, settings and verification.
