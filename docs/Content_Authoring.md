# Gameplay content authoring

Hexfront gameplay definitions are typed Godot resources loaded by `ContentRegistry`. Runtime state stores stable definition IDs and resolves immutable data through the registry. Use lowercase `snake_case` IDs; treat an ID as permanent once saves or other content can reference it. Display names and descriptions may change without changing the ID.

Production definitions live under `res://content/`. Small validation examples that must never enter normal matches live under `res://content_dev/`, which is loaded only when explicitly requested by tests or tools. Directory and file names are organizational; the `id` inside each resource is authoritative. Registry discovery is recursive and sorted.

## Add a resource

Create `content/resources/<resource_id>.tres` using `scripts/content/resource_definition.gd`.

Required fields:

```ini
[resource]
script = ExtResource("1")
id = "energy"
display_name = "Energy"
description = "Stored electrical power."
sort_order = 20
```

Reference the new ID from faction `resource_ids`, starting-resource dictionaries, income dictionaries, and unit or structure cost dictionaries as needed.

## Add a unit

Create `content/units/<unit_id>.tres` using `scripts/content/unit_definition.gd`. Set `id`, `display_name`, `max_hp`, `movement`, `attack_range`, `attack_damage`, and a cost dictionary whose keys are existing resource IDs. `tags` and `visual_id` are optional presentation/capability hooks.

`upkeep` and `turn_production` are resource dictionaries processed exactly once at the owning turn start. `corpse_food_value` is the visible value retained by an eligible corpse. `temporary_lifetime_turns` enables an explicit finite owner-turn lifetime; zero means permanent. Capabilities such as `synaptic`, `morale_immune`, `disease_susceptible`, `road_bound`, and `mobile_headquarters` belong in `tags` and are queried by rules rather than faction names.

Add the unit ID to each owning faction's `unit_roster_ids`. Add it to `starting_unit_ids` only when it should spawn at match start. Technology definitions may reference it from `unlock_unit_ids`.

## Add a structure

Create `content/structures/<structure_id>.tres` using `scripts/content/structure_definition.gd`. Set `id`, `display_name`, `max_hp`, and costs. Set `can_recruit` only for a recruiter. Use tags for narrow rule capabilities such as `victory_objective`; a structure does not implicitly behave like Headquarters.

Add the structure ID to the faction's `structure_roster_ids`, and optionally to `starting_structure_ids` or a technology's `unlock_structure_ids`.

## Add a faction

Create `content/factions/<faction_id>.tres` using `scripts/content/faction_definition.gd`. A playable faction needs:

- a stable `id`, `display_name`, and `playable = true`
- existing IDs in `resource_ids`, `unit_roster_ids`, and `structure_roster_ids`
- `starting_resources` and `turn_resource_income` keyed by resource ID
- starting unit and structure IDs that are also present in its rosters
- technology IDs belonging to its research graph, if any

`visual_theme_id` and `music_id` select existing presentation data. Match setup discovers playable factions from the registry and stores their IDs.

## Add a technology

Create `content/technologies/<technology_id>.tres` using `scripts/content/technology_definition.gd`. Set `id`, `display_name`, `research_cost`, and any `prerequisite_ids`. Unlock arrays must reference existing unit or structure IDs. Modifier IDs must resolve to resources created with `scripts/content/modifier_definition.gd`; `unlock_tags` are stable capability IDs.

Add the technology ID to the relevant faction's `technology_ids`. Prerequisites must form a directed acyclic graph. The registry validates missing links, repeated prerequisites, self-dependencies, and cycles, and exposes a deterministic topological order.

Living Migration nursery recipes live in `content/biological_recipes/` and use `BiologicalRecipeDefinition`. Each recipe names one branch, resource costs, development and nutrient requirements, and valid outcome unit IDs. Diseases live in `content/diseases/` and define duration, disease-specific immunity, damage or damage reduction, and their research unlock tag. The faction's typed `LivingMigrationConfig` is embedded in `content/factions/living_migration.tres`; provisional tuning belongs there rather than in UI or rule code.

Baumeister districts live in `content/districts/` and use `DistrictDefinition`. Costs, upkeep, per-turn production, construction time, research unlock tag, and capability tags are authored there. Pillar/bridge, Integrity, maintenance, repair, weighted movement, designation, and hero-limit tuning belong in the typed `BaumeisterConfig` embedded in `content/factions/baumeister.tres`. Unit categories such as `biological`, `vehicle`, `infantry`, `engineer`, `artillery`, `anti_air`, and `hero` drive shared support and recruitment rules.

## Add a neutral group

Create `content/neutral_groups/<group_id>.tres` using `scripts/content/neutral_group_definition.gd`. Set `id`, `display_name`, one or more existing `unit_ids`, `relationship_policy` (`neutral` or `hostile`), and a nonnegative `difficulty`. Optional `spawn_tags` and `biome_affinities` are authoring inputs for future population rules.

Neutral spawning is currently disabled. Neutral actors will use the same unit definitions, runtime unit state, combat rules, and controller relationship system as playable units.

## Add a world site

Create `content/world_sites/<site_id>.tres` using `scripts/content/world_site_definition.gd`. Set `id`, `display_name`, tags, and the three explicit behavior flags:

- `blocks_movement`: central occupancy prevents a unit sharing the cell
- `selectable`: presentation may expose the site for inspection
- `interactable`: `SiteRules` returns the site as a possible interaction

Use this shared type for trade posts, deposits, ruins, landmarks, and later resource sites. Mutable ownership and interaction data belongs in `WorldSiteState.runtime_state`, never in the definition resource. `trade_post.tres` is the minimal production proof; population remains disabled by default.

## Validate content

Run the focused suites from the project root:

```powershell
godot --headless --path . --script tests/content_foundation.gd
godot --headless --path . --script tests/world_interaction.gd
```

`ContentRegistry.default()` validates production content on first use. Validation rejects malformed IDs, duplicate IDs, missing references, invalid rosters, negative values, bad unlock targets, invalid neutral compositions, and cyclic research graphs. The registry fingerprint covers gameplay-relevant fields and excludes display text.
