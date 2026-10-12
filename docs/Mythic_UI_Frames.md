# Mythic interface frames

`MythicFrame` is the shared border language: antique gold on deep green-black,
interwoven corner stems, tiny leaves, repeated edge knots and hexagonal world
seals. It uses code-native vector drawing rather than raster ornament assets.

All current frontend pages use the elaborate variant through `_menu_column`:
Main Menu, New Game, Options, Pause, multiplayer setup/lobby and session dialogs.
Research uses the same elaborate border for both factions. Unit/city selection,
context actions, the top bar, notifications and the world inspector use a
compact variant of the same motif. The network development screen is also framed.
Semantic status boxes and fullscreen blocking backdrops are not decorative pages.
Load Game remains the existing disabled placeholder; no save/load feature was added.

Menu titles reuse the bundled Cinzel Decorative font. Body text remains in the
standard font. Ornaments occupy the existing outer padding; research padding
is widened to reserve an 18-pixel engraved band.

The decoration is a Node2D, so containers do not allocate space to it and it
cannot consume mouse input or keyboard focus. It redraws only when resized;
there is no per-frame work, gameplay state or texture allocation. Applying it
twice is safe. Panels preserve their authored content margins and city width.

Use `MythicFrame.apply(panel)` for new pages, or `apply(panel, true)` for small
tactical cards. `tests/mythic_frames.gd` checks frontend coverage, viewport fit,
idempotence, unchanged minima, resize and faction research coverage. Existing
frontend and strategic graphical suites capture the complete presentation.
