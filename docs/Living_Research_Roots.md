# Living Migration — Root of Knowledge

Press **R** or the Research button. Select any root to inspect its effects and
prerequisites; only available research can start. Scroll both axes and use
the − / + controls to explore the large root canvas. The modal blocks world input.
Gold roots are ready, pale roots are growing, green roots are completed, and
grey roots are locked. A completed root lights its outgoing branches with a
slow sap pulse; animation pauses while hidden. The frame now uses the shared
[mythic engraved pattern](Mythic_UI_Frames.md) found on menus and city cards.
Titles and root names use bundled Cinzel Decorative (SIL OFL); body text stays
in the normal UI font. Small-scale node names retain a readable minimum size.

There is one initial root and fourteen prerequisite-dependent unlockables:

```text
Symbiotic Foundations (Tracking disease; faster nursery development)
├─ Ant Adaptation (Fire Ant)
│  ├─ Queen Signal (Ant Queen)
│  └─ Migration Networks (longer roads and Connection range)
│     └─ Silken Roots (+1 Silk per fed Spider per round)
├─ Marsh Metabolism (Dragonfly, Mosquito, Poison Dart Frog)
│  └─ Marsh Longevity (Bullfrog, Unke; longer marsh lifespan)
├─ Directed Metamorphosis (Brimstone Butterfly, Fire Moth)
│  └─ Apex Metamorphosis (Admiral; lower maturation requirement)
├─ Controlled Virulence (Weakening and Wasting diseases)
├─ Migration Efficiency (Mite every 2 rounds instead of 3)
│  └─ Synaptic Bloom (+1 Synapse per internal Synapse organ)
│     └─ Root Memory (+1 RP per internal Research organ per round)
└─ Regenerative Clearings (+1 harvest Food; faster terrain recovery)
   └─ Abundant Organs (+1 Food per internal Food organ per round)
```

Research grows at the end of the player's phase from internal Research organs.
The overlay shows authoritative progress and RP per round; it only emits intent,
with the existing GameRules / multiplayer dispatcher enforcing the command.
All prerequisites must be completed, one project can run at a time, and
completed research cannot restart. Locked inspection never emits a start command.
Unlocks remain per-player and use the existing research snapshot format.
New upgrade magnitudes are authored in LivingMigrationConfig and fingerprinted;
multiplayer build/data compatibility is bumped to reject older rules.

`tests/research_roots.gd` covers reachability, rejection without mutation,
completion, isolation, actual economy effects, RP output, node non-overlap,
selection, states, zoom and small-screen bounds. Run without `--headless` to
capture `.godot/research_roots_1280.png`.
