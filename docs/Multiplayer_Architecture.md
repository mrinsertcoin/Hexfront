# Multiplayer Architecture

Milestone 18 adds a host-authoritative ENet foundation for two-computer development matches. Session registration and match configuration accept up to four human players; four-player game flow and start balancing remain Milestone 19 work.

## Authority and session lifecycle

`NetworkSession` is the only ENet owner. Offline games never create a network peer. A host owns `GameState`, `GameRules`, phase sequencing, player and neutral AI, world population, visibility, `CommandDispatcher`, and per-recipient observation publication. A client owns only its local identity, permitted snapshots, and presentation.

Each round follows `Enemy turn -> Simultaneous player turns -> Combat resolution`. Neutral controllers act first in the enemy turn, followed by ordered player-AI controllers. All connected human controllers then receive the same planning window and may submit commands concurrently. Ending movement marks only that player ready; combat begins after every living human is ready. Eliminated or disconnected humans cannot block the barrier.

The lifecycle is `Disconnected -> Connecting -> Lobby -> Loading -> Active`. Hosting binds UDP port **24567** by default. Joining performs an asynchronous compatibility handshake. The host maps ENet peer IDs to game player IDs explicitly; no rule assumes these numbers are equal. Lobby records support four participants, names, either playable faction, duplicate faction choices, ready state, and host identity.

The host announces one authoritative public match configuration. Terrain seed, size, population density, assignments, factions, teams, and controller kinds come from the host. World population uses an additional private seed which is never put in public match configuration. Clients acknowledge their first valid observation before the host enables commands.

Leaving closes the ENet peer and clears mappings, observations, sequence counters, and authority references. A lobby disconnect removes that registration. A match disconnect authoritatively eliminates that player, clears their pending combat orders, and continues without allowing the missing peer to block the round. Host loss gives clients an explicit session-ended state. Host migration, reconnect, and AI takeover are deliberately absent.

## Compatibility protocol

`NetworkProtocol.NETWORK_PROTOCOL_VERSION` versions message formats independently of `GAME_BUILD_VERSION`, `GAMEPLAY_DATA_VERSION`, and the `ContentRegistry` fingerprint. All four values must match before registration. Rejections distinguish protocol, build, gameplay-data, content, full-lobby, and already-started failures without exposing engine exceptions.

Connection and loading have bounded timeouts. Port binding and connection errors become UI messages. The selected UDP port is configurable in Host and Join screens.

## Commands and dispatch

`GameplayCommand` contains only `protocol_version`, `client_sequence`, `command_type`, and `parameters`. Parameters must recursively contain primitive values. Nodes, Resources, object references, client resources, HP, damage, and outcomes are rejected. The authenticated ENet sender selects the player through the host's peer/player map; commands contain no trusted player ID.

`CommandDispatcher` is the sole network-match mutation gateway. It resolves commands to existing `GameRules` methods, applies phase/readiness/defeat/ownership checks, and returns a bounded result. During simultaneous player turns, every living human who has not ended movement is actionable regardless of the presentation cursor. Each peer must send consecutive sequence numbers. Replays are identified and cannot repeat a mutation. Rejected rule diagnostics become the generic public message `Action could not be completed.` so hidden blockers and targets cannot leak through errors.

Current command inventory:

- Core: move, attack, end turn, recruit, start research, site interaction.
- Living Migration: choose nursery, internal construction, biological queue/deploy, caterpillar transformation, Spider construction/deploy, Mite deploy, ant-road construction, corpse consumption, disease selection.
- Baumeister: district construction, bridge extension, deployment toggle, healing, unit/structure/bridge repair, bridge damage, target designation, district support.

The host player's board submits through the same authenticated dispatcher used for remote players. Player AI and neutral AI use its authoritative-controller entry point. Neutral planning and execution run only on the host. Offline games retain their existing direct `GameRules` path and require no socket.

## Observation synchronization

After each accepted mutation, the host increments an authoritative synchronization revision and creates a separate snapshot for every registered player. `ObservationCodec` starts from that player's Milestone 17 `TeamObservation` and serializes only primitive records:

- public phase, round, winner, player/faction assignments, actionable players, and players already ready;
- that player's resources and research;
- that player's detailed owned entities and faction state;
- visible entities, explored/visible/detection masks;
- immutable historical contacts and discovered sites;
- permitted discovery/loss IDs and events.

It never serializes `GameState`, global unit/site dictionaries, enemy economies, hidden production, or hidden neutral activity. Unseen entities are absent from the actual message. Contacts retain their last observed snapshot and do not follow hidden HP, position, or death.

Snapshots support initial load and full resynchronization. Clients ignore duplicate and outdated revisions, detect gaps, request a current full snapshot, and accept it as an explicit resynchronization. Correctness currently takes priority over delta compression. Turn-based outcomes are logical records rather than streamed transforms.

The remote development view lists owned and observed entities, contacts, sites, resources, phase/readiness state, connection state, and synchronization revision. It enables End Turn and its JSON command composer whenever the local player is in the actionable-player set, independent of other humans' readiness. The host retains the normal tactical board. A full remote tactical interaction layer and network movement/combat animation are deferred; client presentation still receives only permitted state.

## Automated verification

`tests/multiplayer.gd` covers compatibility mismatches, four-player-ready duplicate factions, primitive command validation, explicit peer/player mapping, ownership and turn enforcement, representative movement, recruitment, research, Living Migration production, Baumeister construction, site interaction, replay protection, missing command sequences, serialized hidden-information absence, immutable contacts, snapshot round trips/resynchronization, repeated hosting, lobby and active-match disconnects, host loss, and loading timeout.

`tests/network_integration.ps1` launches two independent Godot processes on localhost. It verifies ENet registration, ready/lobby flow, duplicate faction selection, loading acknowledgment, per-client initial observation, host turn transfer, remote movement, replay rejection, remote end turn, host observation, and clean disconnect. This is part of `tests/run_all.ps1`.

Automated localhost processes validate the network stack but cannot prove router, firewall, Wi-Fi, or two-machine behavior. That physical workflow remains a manual test.

## Two-computer Windows test

1. Put the same Hexfront build/content on both computers and allow its executable through Windows Defender Firewall for **Private networks** and UDP.
2. On the host, open **Multiplayer -> Host Game**, enter a name and UDP port `24567`, choose either faction, and create the lobby.
3. Find the host's LAN IPv4 address with `ipconfig`. If testing over the internet, manually forward the selected UDP port; NAT traversal is not implemented.
4. On the second computer, open **Multiplayer -> Join Game**, enter the host IPv4 address, port `24567`, name, and either faction. Selecting the same faction as the host is valid.
5. Both players mark Ready. The host selects **Start Development Match**. Wait until both connection indicators say Connected.
6. On the host tactical board, test normal movement/combat. On the remote development view, choose a command type and enter its stable-ID parameters as JSON, for example `move` with `{"unit_id": 3, "destination": 41}`, then send it. Use the displayed owned entity/cell IDs. Test End Turn with its dedicated button.
7. Move an enemy into and out of observation. Confirm it appears as a current entity and then only as a last-known contact; inspect the remote log/snapshot in a debug build if performing a protocol audit.
8. Close the client during the lobby, reconnect, then close it during a match. Confirm the host reports the player eliminated and the match continues without waiting for their movement phase.
9. Close the host. Confirm the client reports `Host disconnected. Session ended.` and returns through the frontend safely.

## Current limitations

This friend-hosted alpha foundation has no matchmaking, NAT traversal, encryption/identity service, dedicated server, host migration, persistent reconnect, spectators, chat, replay, or bandwidth deltas. Public terrain generation remains deterministic from the public terrain seed; population placement uses a private host seed, but this milestone does not claim comprehensive anti-cheat protection. The remote client UI is a development observation/command interface rather than the final tactical board. Four-player registration exists, while full four-player lobby flow and starting-position balance are deferred to Milestone 19.
