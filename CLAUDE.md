# Echo (working title)

**Read `rules.md` first: it holds the game's logic and wins any argument with the code.**

A first-person horror game where you play as a blind person. The screen is black. **Sound is visual**: anything you can hear, you can faintly see (a weak, blurry shape), as strong as it sounds. A tongue click sends an echo out from you along your view as a ring that spreads over everything around you (360°): it captures a sharper dot snapshot of the room. You can look around inside the snapshot while you stand still; it fades the moment you press a movement key. The echo reaches 4 m. Distance controls clarity. Materials are intentionally limited: solid (default), hollow, glass. The "bad person" (wooden right leg, slight limp) is heard and felt through footsteps, and seen only as a silhouette in scans. Tab switches to a sighted view (real lighting) for comparison.

## Stack

- Godot 4.5.1, GDScript, Jolt Physics (raycasts ~40% cheaper than Godot Physics)
- Visuals are shader-driven: scan dots and sound shapes are MultiMesh billboards on their own visual layers (11 and 12), rendered only in blind mode. No textures, greybox geometry.
- Sound is placeholder synth (`tools/gen_audio.gd`).

## Rules

- Keep the visual language minimal: monochrome dots, no per-material colors beyond solid/hollow/glass.
- **If you can hear it, you can see it.** Every sound source (ambient objects, people's steps) is always faintly visible as a blurry, low-resolution shape whose brightness follows how loud it is at the listener. Never as sharp as an echo scan.
- **Sound level = the object's own loudness x distance (inverse-square, 14 m limit) x what is in the way.** Closed doors (0.12), walls (0.04) and floors (0.05) multiply along the best route through the house: `house.transmission(room_a, room_b)`. Heard volume, muffling and the visual all use it. Footsteps from another floor are floor-borne (min 0.2), dull but the peg's knock survives. Don't hand-tune per door; change the factors or the source's own dB.
- **Footsteps are plain bumps** (no pings or squeaks); people differ by weight, hardness and rhythm.
- **Smell is colour.** Only food has colour (broccoli green, apple red, fried chicken orange), shown up close. The only other colours: the bad person's wooden leg and steps (red) and the friend's steps (light green).
- **Touch is visual**: what you touch shows as a clean white outline while you touch it (held things stay; a door while it swings; the TV, the alarm clock when pressed). `live_layer.touch(obj, seconds)`. Food gives off animated coloured steam.
- **Looks don't matter, structure does.** The sighted view is a debug view: flat colours, one unshadowed `DirectionalLight3D`, no lamp lighting. Models must have realistic *structure*; small grabbable things are built in `scripts/props.gd` (lathed mugs/bottles, claw hammer, keys...). Everything interactive is in group `interactive` (`house.interactive()`, `house.grabbable()`, doors).
- **The scan is an instant, 360° snapshot from where you stood**, revealed by one ring going out from you; dots stay lit (no flash, no dimming). It's fixed in the world: looking around shows other parts of it. Scans add up (no reset) and fade the moment a movement key is pressed. Walls hide what's behind them from where you are now.
- Objects must make physical sense: everything rests on something, hangs from a wall or sits on the ceiling. Run `tools/check_placement.gd` after adding furniture.
- The bad person must read as a real human silhouette (that's how the player identifies people). Future people can differ in build and step sound.

## Code map

- `scripts/menu.gd` (`scenes/menu.tscn`, the main scene): main menu, Play -> Tutorial / Level 1; sets `Main.level` and loads `scenes/main.tscn`. Test runs skip it
- `scripts/stalker.gd`: the bad person's mind (Level 1 only, off in look-and-feel test runs): hears noises (`main.gd::_noise(pos, radius)` -> `hear()`, shortened by `house.transmission`), walks there on a navigation mesh baked at start (`bake()`, agent radius 0.2 so the 1 m stairs connect), opens doors, listens, goes back to his round (`patrol`: `main.gd::BAD_ROUND`, starts upstairs); hiding: `player_hidden` / `knows_hide`; `caught` signal -> `main.gd::_caught`. `npc.gd::follow(path)` / `pace` / `arrived` drive the body
- `scripts/fear.gd`: your heartbeat and the fear `level` (0..1, from the bad person's distance and what is between you); `main.gd` passes it to `scanner.set_tremble` and `shaders/vignette.gdshader` (edges close in, pulse with `beat`)
- `scripts/tutorial.gd`: the tutorial's hints, one at a time (`main.gd::_tut(what)` advances them)
- `scripts/main.gd`: hiding (`_setup_hiding`: wardrobes and bed frames get meta `hide`; `_enter_hide` / `_leave_hide`; `shaders/hide_mask.gdshader`), touch patches (`scanner.set_touch` for the hand, `scanner.add_touch` for footfalls and bumps, 8 slots in `echo_fixed`), `_solo()` (real play and `--stalker`: only the bad person exists), the goal (`_setup_goal`: keys at a random checked spot, `FrontDoor` is the exit, `_try_exit`, `_escape`), endings (`_update_ending`), and it wires everything, input, grab/drop, `--autotest` screenshot run; `static var level` ("tutorial": no people)
- `scripts/house.gd`: greybox level built in code (boxes/cylinders tagged with echo material)
- `scripts/player.gd`: first-person walker: slow walk, Shift run, head bob / sway / lean, `stepped` signal for your own footfalls (`main.gd::_on_own_step`). `main.gd::_update_reach` is the reaching hand (`scanner.set_touch`)
- `scripts/scanner.gd`: the echo. 360° rays (cube map, 21.6k, 6 ms budget per physics tick, random scatter, coarse first) only measure depth into a small cube-map texture per scan. The house's fixed dots (`scripts/world_dots.gd`: scattered surface dots (one per jittered grid cell) + bright lines on sharp edges, ~380k, built at load; the shader gives each its own size, drift and shimmer) are lit on the GPU by a shadow-map test against the last 4 scans (they add up), at distance / 12 m/s (one ring from the listener), range 4 m (`MAX_RANGE`). Scans fade the moment a movement key is pressed (`start_fade()`, 0.6 s). Capture is instant: people and doors are copied into frozen bodies on physics layer 4 for the cast. Plus a detail pass for group `interactive`, people silhouettes (latest scan only) and dim shadow-fill dots from 6 extra vantage points
- `shaders/echo_fixed.gdshader` (the house's fixed dots), `shaders/echo_detail.gdshader` (interactive things, people's silhouettes, shadow fill; same depth test), `shaders/occluder.gdshader` (the blind view draws the house black so scanned dots behind walls are hidden; `main.gd::_build_occluders`, visual layer 13)
- `scripts/sound_sight.gd` + `shaders/sound_blur.gdshader`: the senses that aren't the echo: blurry shapes of sound sources (loudness envelope from the WAVs, occlusion by sealed rooms), smell colours, tinted footstep flashes
- `scripts/props.gd`: realistic small grabbable things; `scripts/outline.gd`: mesh edges (touch outline + structure dots)
- `scripts/house_upstairs.gd`: the east wing (back hall, stair hall, workshop), the stairs and the whole upstairs floor; `house.gd` holds the room graph (`rooms`, `passages`, `connected`, `room_at`)
- `scripts/live_layer.gd`: live footstep ripples + held-object touch dots
- `scripts/npc.gd`: one script for every person (`setup({...})`: build, gait, step sounds and colours, route, peg leg). Smooth lofted human body on a joint skeleton (layer 2, echo material 4; wooden leg 5). Built in `main.gd::_build_people`: bad person, stranger, friend
- `scripts/house.gd` also holds the palette, ceiling lights, doors (`door()`, `toggle_door()`), and reusable furniture (`chair`, `table`, `shelf`, `plant`, ...)
- `tools/gen_audio.gd`: synthesizes placeholder sounds into `audio/` (`godot --headless --path . --script res://tools/gen_audio.gd`)
- `audio/`: tongue click, fan, TV ad, fridge, clock, drip, washer, step_foot, step_peg, step_friend, door_close (used for opening too), step_bad (the bad person's shoe), door_locked, scare, heartbeat, alarm_tick, alarm_ring (replace with real recordings using the same names)

## Echo materials

1 solid (default), 2 hollow, 3 glass, 4 person, 5 wooden leg, 6 door. Don't add more without the user asking.

## Testing

Godot is on the PATH as `godot` (winget install, 4.5.1).

- `godot --path . -- --autotest=<folder>`: scripted session, saves screenshots to check the look. Add `--level=tutorial` for the tutorial.
- `godot --path . -- --stalker=<folder>`: he hears a click, investigates, listens, returns; the locked door, the keys, the escape (printed lines). Add `--catch` to stand still and get caught (saves `s02_caught.png`), `--hide` for a wardrobe, under a bed and being found there, `--patrol` to print where his round takes him.
- `godot --path . -- --menu-shot=<folder>`: screenshots of the main menu and the level list.
- `godot --path . -- --tour=<folder>`: sighted photo tour of every room (4 directions, doors open), half-size PNGs.
- `godot --path . -- --model=<folder>`: the three people standing in a row, front/side/back, sighted and scanned.
- `godot --path . -- --features=<folder>`: food smell, hammer in hand, walking up the stairs, the alarm through a sealed wall, the three people's steps, door highlight.
- `godot --headless --path . --script res://tools/check_placement.gd`: lists floating objects.
- `godot --headless --path . --script res://tools/check_acoustics.gd`: prints how much sound survives between rooms (doors shut / open).
- `godot --headless --path . --script res://tools/bench_rays.gd`: raycast cost.
- `godot --headless --path . --script res://tools/bench_dots.gd`: how many fixed echo dots the house gets, and the build time.

## Docs map

- `rules.md`: the game's logic. Read before changing any behaviour.
- `README.md`: what the game is + how to play the prototype
- `docs/worklog.md`: decisions and gotchas
- `docs/ideas.md`: brainstorming sandbox (don't act on it)
- `docs/temporary/prototype-plan.md`: plan and checklist for Prototype 1
