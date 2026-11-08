# Echo (working title)

A first-person horror game where you play as a blind person. The screen is black. You "see" only through echo scans: a frozen dot image of the room captured at the moment you scan, drawn top to bottom, held while you stand still and fading once you walk. Distance controls clarity. Materials are intentionally limited: solid (default), hollow, glass. The "bad person" (wooden right leg, slight limp) is heard and felt through footsteps, and seen only as a silhouette in scans. Tab switches to a sighted view (real lighting) for comparison.

## Stack

- Godot 4.5.1, GDScript
- Visuals are shader-driven (SubViewport capture + fullscreen dot shader). No textures, greybox geometry.
- Sound comes in a later phase.

## Rules

- Keep the visual language minimal: monochrome dots, no per-material colors beyond solid/hollow/glass.
- The scan image is frozen to the screen. Camera movement never changes what's displayed until the next scan.

## Code map

- `scripts/main.gd`: wires everything, input, grab/drop, `--autotest` screenshot run
- `scripts/house.gd`: greybox level built in code (boxes/cylinders tagged with echo material)
- `scripts/player.gd`: first-person walker, camera renders nothing
- `scripts/scanner.gd`: frozen-pose row-by-row raycast scan → data texture
- `shaders/echo_dots.gdshader`: turns scan data into the dot afterimage
- `scripts/live_layer.gd`: live footstep ripples + held-object touch dots
- `scripts/npc.gd`: the bad person: jointed human body (layer 2, echo material 4), peg leg, limp walk cycle, footstep sounds + `stepped(pos, peg)`
- `scripts/house.gd` also holds the palette, ceiling lights, doors (`door()`, `toggle_door()`), and reusable furniture (`chair`, `table`, `shelf`, `plant`, ...)
- `tools/gen_audio.gd`: synthesizes placeholder sounds into `audio/` (`godot --headless --path . --script res://tools/gen_audio.gd`)
- `audio/`: tongue click, fan, TV ad, fridge, clock, drip, washer, step_foot, step_peg (replace with real recordings using the same names)

## Echo materials

1 solid (default), 2 hollow, 3 glass, 4 presence. Don't add more without the user asking.

## Testing

`godot --path . -- --autotest=<folder>` runs a scripted 8 s session and saves screenshots to check the look.

## Docs map

- `README.md`: what the game is + how to play the prototype
- `docs/worklog.md`: decisions and gotchas
- `docs/ideas.md`: brainstorming sandbox (don't act on it)
- `docs/temporary/prototype-plan.md`: plan and checklist for Prototype 1
