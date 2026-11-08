> Purpose: Running log of decisions, gotchas and architecture notes.

## 2026-11-08: Prototype 1 architecture

- **Scan = raycasts, not a render.** On scan, the camera pose is frozen and `scanner.gd` casts one ray per dot cell (213×120) row by row over 0.7 s from that pose. Results go into a float `Image` (R distance, G material, B facing, A reveal time) → `ImageTexture` → `shaders/echo_dots.gdshader`. This makes the top-to-bottom sweep real and keeps the image frozen to the screen no matter how the player moves.
- **Reveal time is the absolute game clock**, so a new scan wipes over the old fading one row by row instead of clearing it.
- **Materials** are `meta("echo_material")` on each StaticBody3D: 1 solid, 2 hollow, 3 glass. Nothing else is distinguished, on purpose.
- **Readability comes from echo strength, not uniform dots:** brightness falls with distance (`exp(-d/4)`) and with grazing angle (`facing^2`); outlines from distance jumps and facing jumps stay bright. Without this the first version looked like grey static.
- **Live layer** (`live_layer.gd`, `_draw`) is separate from the frozen scan: footstep ripples and the held object's touch-dots move with the camera.
- The player camera has `cull_mask = 0` (renders nothing). F1 turns it on for debugging.

## 2026-11-08: Design decisions

- **No minimap.** The character knows their house from memory, but a map would make it too easy. Orientation comes from scans, sounds and the player's own memory.
- **The presence shows up in scans** as a silhouette (frozen like everything else). Without scanning, only its footstep ripples are visible.
- **Ambient sounds are heard, never seen:** TV ad, bedroom fan, fridge hum, hallway clock. They're positional (3D), so they help you orient.

- **Snapshot holds until the player walks** (turning doesn't count). `scanner.notify_moved()` sets `fade_begin`; leftovers of the previous scan fade fast under the new sweep (`old_fade`).
- **The presence is "the bad person":** wooden right leg below the knee, slight limp. Shoe thud vs. peg knock, and different floor ripples.
- **Sighted mode (Tab)** shows the real house; blind mode keeps `cull_mask = 0` so lighting costs nothing there.

## Gotchas

- Shadowed omni lights are expensive here (9 of them = ~15 fps sighted). Only the main living-room light casts shadows (dual paraboloid). Back to 60 fps.
- Scan raycasts cost ~5.5 µs each (~7 ms/frame during a sweep). Fine as is.
- Autotest screenshots can lag one step behind right after toggling sighted mode (first-time shader compile hitch). Leave ~0.3 s before a shot.

- Godot type inference: members typed as a base class (e.g. `CharacterBody3D`) lose script properties, so `:=` fails. Type them with the preloaded script const instead (`var player: Player`).
- The grain hash on `UV` made visible vertical stripes. Hash `FRAGCOORD` instead.
- Dev screenshot run: `godot --path . -- --autotest=<folder>` saves 7 PNGs (sweep, scan, turned, fading, footsteps, holding, debug) and quits.
