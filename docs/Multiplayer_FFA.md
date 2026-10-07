# Four-Player Free-for-All

Milestone 19 extends the host-authoritative ENet prototype to two, three, or four human participants. Every participant owns one team, so all other player teams are hostile. The only normal multiplayer faction choices are **The Living Migration** and **Baumeister**; any number of players may choose the same faction.

## Lobby lifecycle

The host selects a capacity of 2–4 slots plus planet size, signed world seed, and population preset. Small is the default and Medium remains available. The host owns slot IDs, colors, faction assignments, readiness, and match configuration. A join beyond the selected capacity is rejected instead of replacing a participant.

Each row shows player name, faction, ownership color, ready state, connection state, and the host marker. Players explicitly toggle Ready. Changing a faction or changing the host configuration clears the affected readiness state. The match can start only after all occupied slots are ready. A pre-match disconnect frees the slot and republishes the authoritative lobby.

The four stable ownership accents are cyan, orange, green, and violet. They are separate from faction art and appear in the lobby, turn/player panels, selection rings, ownership markers, structures, and known-contact presentation. Player identity rather than faction identity controls hostility, resources, research, visibility, and entity ownership.

## Initialization and starts

`MatchConfig` carries primitive player IDs, names, factions, team IDs, controller kinds, and colors. `GameState` creates one independent `PlayerState`, controller, faction runtime, research state, economy, and visibility team for each assignment. Non-contiguous player IDs are supported.

The host generates terrain and private-seed world population before publishing recipient observations. Start placement first ranks valid land cells by the faction-specific suitability supplied by the generated world. It then selects starts deterministically using graph-distance maximin placement, balancing suitability with distance from every chosen start. Living Migration favors fertile/moist accessible terrain; Baumeister favors accessible, less-rough expansion terrain. The algorithm uses `PlanetGrid` distances and works for 2–4 starts.

Host diagnostics report each start cell, nearest-opponent graph distance, local suitability, nearby sites, and nearby hostile-neutral strength. These records stay in authoritative state and are not exposed in player snapshots.

## Turns, elimination, and victory

Human turns follow the exact lobby order. For four players the sequence is P1 → P2 → P3 → P4 → one neutral phase → next round. Missing slots do not exist in the order, and eliminated players are skipped. The HUD reports round, current player, color, faction, and whether the local player owns the turn. Rule validation rejects remote-turn commands even if a client UI attempts one.

A player survives while at least one faction entity tagged as a headquarters remains. This respects multiple Living Migration spider headquarters and multiple valid Baumeister headquarters instead of treating an ordinary structure loss as elimination. Elimination removes all remaining owned units, structures, roads, districts, and bridges; marks the public player record; prevents commands and observation updates; and emits a public elimination event. When exactly one non-neutral player remains, turn and neutral processing stop and the winner, faction, round, and elapsed duration are displayed.

The authoritative command dispatcher retains every current Living Migration and Baumeister action. Peer-to-player binding and normal rule ownership checks apply to movement, combat, research, recruitment, faction production/construction, diseases, roads, districts, bridges, healing, repair, designation, and site interaction. Equal faction IDs never imply alliance or shared state.

## Observation boundary

Each player is its own fog-of-war team. Recipient snapshots contain public player name, color, faction, connected/eliminated state, active turn, round, and result. Only the recipient gets their economy and research state. Unseen entities, hidden neutrals, undiscovered sites, enemy resources, and enemy research remain absent. The host still owns the complete simulation; clients submit primitive intentions and render recipient-specific snapshots.

## Disconnect policy

A mid-match participant disconnect pauses the authoritative tree and preserves their identity. The host may remove that participant, which applies normal elimination and resumes if the match can continue, or abort the match with a public reason. A host disconnect ends client sessions cleanly. Reconnection and host migration remain deferred.

## Automated verification and profiles

`tests/ffa.gd` covers 2–4 state creation, four graph-spaced starts, duplicate-faction isolation and hostility, non-contiguous IDs, exact turn/neutral order, eliminated-player skipping, entity cleanup, victory, public/private snapshot fields, independent visibility, lobby capacity/readiness/configuration, and disconnect removal. The existing faction and multiplayer suites cover the complete command inventory and detailed Living Migration/Baumeister rule seams.

`tests/ffa_network_integration.ps1` launches one host and three clients as four independent Godot processes on localhost. It verifies authoritative P1–P4 assignments, duplicate Living Migration and Baumeister selections, all-player readiness, sequential remote end-turn commands through the beginning of round two, recipient synchronization, and a controlled host abort. The legacy two-process test also remains active.

Measured on the development machine using Godot 4.6.2 Compatibility:

| Profile | Cells | Setup + round sample | Turn/neutral processing | Visibility refresh | Largest recipient snapshot | Static memory |
|---|---:|---:|---:|---:|---:|---:|
| Small / Standard | 2,562 | 1,999.73 ms | 77.45 ms | 4.78 ms | 18,723 bytes | 42.5 MB |
| Medium / Standard | 10,242 | 9,679.85 ms | 203.90 ms | 11.15 ms | 64,570 bytes | 98.9 MB |

The final Small graphical smoke test measured **125.2 FPS** over 180 rendered frames with 64 entities and 47 sites. These figures are development-machine observations, not platform guarantees.

## Manual four-computer procedure

1. Export the same build to four computers on one LAN and allow its UDP port through each firewall.
2. On one computer, choose Multiplayer → Host, select four slots, Small, a seed, and Standard population.
3. On the other three computers, join the host address and confirm all four named/color-coded rows appear identically.
4. Select a mix containing duplicate factions, toggle all players Ready, and start from the host.
5. Confirm each computer receives its own start and independent fog, then play several complete rounds.
6. Exercise faction production/research, discover neutral content and a site, and attack both a different-faction and same-faction opponent.
7. Eliminate one participant and confirm their entities disappear and their future turns are skipped.
8. Continue until one player remains; confirm the result screen, then abort/return cleanly.

This physical multi-computer procedure has **not** been executed for Milestone 19. Automated verification used four independent localhost processes.

## Current limitations

The client match presentation remains the development recipient-snapshot view rather than the final tactical renderer. There is no matchmaking, dedicated server, reconnection, host migration, spectator mode, team play, diplomacy, save/resume, chat, or turn timer. Lobby and match panels are functional development UI and do not represent the final visual design.
