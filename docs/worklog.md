> Purpose: Running log of decisions, gotchas and architecture notes.

## 2026-11-08: Prototype 1 architecture

- **Scan = raycasts, not a render.** On scan, the camera pose is frozen and `scanner.gd` casts one ray per dot cell (213×120) row by row over 0.7 s from that pose. Results go into a float `Image` (R distance, G material, B facing, A reveal time) → `ImageTexture` → a fullscreen dot shader. *(Replaced on 2026-11-08 by the 360° world-space scan, see below.)* This makes the top-to-bottom sweep real and keeps the image frozen to the screen no matter how the player moves.
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
- Dev screenshot run: `godot --path . -- --autotest=<folder>` saves ~20 PNGs and quits (see CLAUDE.md for the other check modes).

## 2026-11-08: Iteration 1.3: sound is visual, 360° scan, human silhouette

- **New core rule: if you can hear it, you can see it.** `sound_sight.gd` gives every sound source a sparse cloud of surface points (MultiMesh, layer 12, `depth_test_disabled` so it shows through walls). Brightness = volume × distance falloff × muffling × the sound's own loudness envelope (RMS read from the original WAV, since imported WAVs are QOA-compressed). So the clock flickers per tick and the TV goes dark between ads. Footsteps flash the leg that stepped for ~0.7 s.
- **Scan is now 360° and world-space.** 6 × 100 × 100 rays on an equi-angular cube map (front face first), cast over 0.45 s; each hit is a MultiMesh dot (layer 11) with reveal time = start + distance / 9 m/s, so a wave visibly goes out from you. Dots keep their world position, so looking around shows the rest of the snapshot. Two dot clouds alternate: the old one fades in 0.6 s when you scan again. Outlines are computed per cube face from neighbour depth/angle jumps. Cost: fps drops to ~90 during the cast on an RTX 2060 Super (60k rays ≈ 0.33 s CPU total).
- Blind mode swaps to its own Environment (black background, linear tonemap, soft glow); sighted mode keeps the lit one.
- **Human body:** limbs and torso are lofted elliptical rings (`_loft` in `npc.gd`) with convex collision, on the same joint skeleton, so the walk/limp animation is unchanged. Proportions follow a reference silhouette (slim man, ~1.80 m). The peg leg stays.
- **Placement fixes:** door handles were offset in hinge coordinates while parented to the panel (floated ~1 m up, outside the door). Fixed, plus: tap, toilet paper, towel, office chair back, globe got proper supports; loose shoes, cardboard boxes, slippers, bucket and a crude "fallen chair" removed (read as random lumps in echo dots); shoes now on a bench. Ceiling lamps are flush and have no collision (a small lamp on a faintly echoing ceiling read as a floating object).

### Gotchas
- `SurfaceTool` triangles must be clockwise seen from outside (Godot front faces), or the mesh renders inside out.
- MultiMesh buffer layout (3D, custom data, no colors): 12 floats row-major transform (origin at 3, 7, 11) + 4 custom.
- Untyped loop variables (`for end in [0, n - 1]`) break `:=` inference; type them explicitly.

## 2026-11-09: Iteration 1.4: bigger house, more people, senses, sealed rooms

- **Scan perf:** the old scan wrote 48k dots into a MultiMesh buffer on the CPU (a ~5 ms upload spike). Now the scanner only writes distance/material/facing per ray into a 540x90 half-float texture, casting rays in a 2 ms/tick budget, coarse to fine (every 4th, then 2nd, then the rest). The vertex shader rebuilds each dot (direction from the cube face id, outline from 4 neighbour texels). Cooldown 1.5 s to 0.45 s. Raycasts cost ~4.4 us each (48k = ~210 ms of CPU spread over ~7 frames).
- **Rooms graph:** `house.rooms` (AABBs) + `passages` (room pairs, door or open). `connected(a, b)` is a flood fill through open passages. `sound_sight.occlusion()` returns 1 or 0.04. Ambient sources and footsteps both use it for volume (0.55 of the dB drop), low-pass cutoff (700 Hz when sealed) and visibility. The old per-door muffle code in `main.gd` is gone.
- **Smell:** food bodies are in group `smell` with meta `smell_color`; `sound_sight.add_smell` samples dense surface points and tints them. Range 5 m, fades with the square of closeness, 0 from a sealed room.
- **People:** `npc.gd` takes a config dict. Build via `height`/`girth` (limbs lengthen with height, widths scale with girth per part by a `fat` factor). Step sounds and colours per person; the peg is echo material 5 (red in scans) and its step tint is red; the friend is light green. Routes include heights, so the friend walks down the stairs.
- **Stairs:** 16 visible steps (layer 1, scanned) + an invisible ramp on physics layer 3 that the player walks on (player mask 0b101, `floor_snap_length` 0.35). Scan rays use mask 0b11, so they ignore the ramp. Verified by walking up with an autopilot: ends at y 2.71.
- **Doors** are echo material 6: always kept, brighter, steady dots, crisp outline. Handles are now at hand height; doors play creak/thump sounds and flash when heard.
- **Alarm clock** on the living-room coffee table: E winds it (6 s of ticking), then 5 s of loud ring. Used to test "loud sounds show a little through walls".
- **Held items:** shown lower right (hold point 0.21, -0.19, -0.5), sampled from all child meshes (a hammer = handle + head), colourless.
- Test scripts: `look_at` on the player tilts the whole body, so test targets must keep the player's height; teleporting must call `scanner.notify_moved()` or the old snapshot stays on screen.

## 2026-11-09: Iteration 1.5: ring scan from the view, acoustics, outline, steam

- **Scan reveal:** reveal time = angle from the view direction / PI x 1.4 s + distance / 45 m/s. (A first version used distance only, which lit the nearest surfaces first: floor, ceiling, then walls, exactly what the designer disliked. A second version with a faster 16 m/s distance term still let the far wall dead ahead arrive late.) The ring now crosses the view in ~0.5 s, centred where you look. Rays are cast bucketed by angle (48 buckets, coarse subset first inside each) so dots exist before the ring arrives. 72 rays per face = 31k rays, 3 ms budget per physics tick.
- **Acoustics:** `house._build_acoustics()` links every room pair that shares a wall (same floor) or lies above/below (floor slab), on top of the passages. `transmission(a, b)` is a label-correcting search for the best product of factors (closed door 0.12, wall 0.04, floor 0.05, stairwell 0.45). Sound level = db_to_linear(source dB) x (unit/d)^2 (cut to 0 past 14 m) x transmission. `AudioStreamPlayer3D` uses inverse-square attenuation and max_distance 14, volume drops by the transmission in dB, and a low-pass opens with sqrt(transmission). Sources now have honest loudness: TV -2 dB / unit 3.5, washer -7, drip -11, fan -14, fridge -16, clock -20. `check_acoustics.gd` prints the matrix (e.g. living to bedroom shut: -18 dB, to master upstairs: -25 dB).
- **Footsteps:** audio regenerated as plain bumps (heel thump; peg = higher/shorter thump + dull rap; friend = light short bump), unit size 1.2, inverse-square. Floor-borne steps (other storey) get at least 0.2 and a 1800 Hz low-pass; through a wall 600 Hz. `stepped` is emitted before `play()` so the volume is right from the first millisecond.
- **Held outline:** `live_layer.gd` collects every mesh edge with its face normals (object space); each frame it draws silhouettes (one face towards you, one away) and sharp edges (> ~37 degrees) on the visible side as white lines. No hidden-line pass.
- **Steam:** per food body, 8 puffs seeded on its top; the shader (`sound_blur.gdshader`, `steam` uniform) moves each up 34 cm over 5 s with sideways drift, grows it and fades it in and out. Level uses the smell level (linear in closeness, not squared) so steam carries a little further than the food itself.

## 2026-11-09: Iteration 1.6: wave from the listener, touch is visual, structure, shadows

- **Scan is a wave from the listener again, but done right.** Reveal = distance / 24 m/s only (the ring-from-the-view versions were rejected). What made the old distance wave look bad was casting: rays were cast in a fixed order, so dots appeared as they were cast, not as the wave arrived. Now 21.6k rays are cast in a random scatter (1 in 16 first, then 1 in 4, then the rest) under a 4 ms/tick budget, so a thin layer exists everywhere before the wave gets there. Full cast ~0.3 s.
- **One scan at a time:** `scan()` hides the previous clouds immediately (it used to fade them for 0.5 s).
- **Shadows:** 6 extra vantage points ~1.1 m around the head (pulled in by walls/people) each cast 2025 rays from their own slice of the scattered ray list; hits go into a third MultiMesh (the `echo_detail` shader at strength 0.2, size 0.7). Reveal time is the bounced path length / speed, so they arrive just behind the wave.
- **Structured detail for everything interactive** (group `interactive`: grabbables, doors, TV, alarm): `Outline.structure_points` puts dots along sharp edges (spacing >= 8 mm), sparser along curved edges, plus a thin surface fill, ~540 per object; only if a ray to the object's centre reaches it. Main-scan dots on interactive bodies get material id + 10 (always kept, brighter).
- **Touch is visual:** `live_layer.touch(obj, seconds)` draws the object's outline (silhouette + sharp edges) with a 0.3 s fade-out; doors (swing + 0.5 s), TV (+ stand + screen), alarm clock. Held things stay outlined.
- **Props:** `props.gd` builds realistic grabbables from lathed profiles and primitives (mug with inside and handle, bottle with neck, tumbler, remote with buttons, phone, keys on a ring, kitchen knife as a prism, soap, toothbrush cup, iron, ball, claw hammer). Each is one StaticBody3D with the origin at its base and trimesh collision per part.
- **Lighting removed:** lamps are fixtures only; the sighted debug view has one unshadowed DirectionalLight3D and ambient light (the player never sees it).
- **TV switch:** E on the TV/stand/screen; stops the sound (so the sound shape disappears), darkens the screen material (its own copy).


## 2026-11-09: Iteration 1.7: instant capture, rings, people outlines, one door sound

- **Instant capture.** The tail on moving people came from casting: ~33k rays at 4.6 us each over ~25 ticks (0.4-0.65 s) while people kept walking. Now `_freeze()` copies every person's body parts and every door panel (PhysicsServer3D bodies on layer 4, `body_attach_object_instance_id` = the original, so hits still read `echo_material`) and scan rays use mask world + layer 4; live doors are excluded by RID. `_thaw()` frees the copies when the cast is done. Checks made at the click (detail visibility, shadow vantage points) use `_live` (the live world, same instant).
- **Rings.** Reveal = click + 0.08 s + distance / 16 m/s (was 24, no delay). `rings(age)` in both dot shaders: a front and 3 fainter ripples 0.075 s apart, 0.022 s wide; a ring forces every ray's dot on (solid band) and adds brightness that doesn't depend on facing, so it shows on the grazing floor. Behind the rings the dots wait at ~30% and settle to full 0.35-0.9 s after the wave starts; without that the rings vanished into already-bright dots.
- **Budget 6 ms/tick + Jolt** (3.0 us/ray vs 4.6-5.5) so all main rays are cast before the rings reach anything past your feet. Jolt can't scale a sphere unevenly: the alarm bells now squash their mesh and use a matching convex hull.
- **People outlines:** `_build_people_detail` samples each body part's surface (cached, ~2600 pts/m^2, max 260), keeps points facing you; side-on ones (n.v < 0.35) are outline dots (material + 0.5: brighter, 1.5x size), the rest a 30% fill. A part is skipped if a ray to its centre hits something that isn't the same person. DETAIL_MAX 9000 -> 14000.
- **Doors:** one sound (`door_close.wav`) for opening and closing; the flash comes 0.3 s in, on the thump. `door_open.wav` deleted.

## 2026-11-09: Iteration 1.8: fixed dots, one ring, scans add up, no seeing through walls

- **Fixed dots.** The designer wanted the structure of the house clearer, corners highlighted, every object with fixed dots dimmed by distance. `world_dots.gd` builds them once at load from every static mesh (not interactive things, not people, not collision-less bodies): a world-anchored grid in each triangle's plane (13 cm, deduped by a 1.7 cm hash so coplanar boxes share one grid) and dots every 4.5 cm on sharp edges (faces > ~37 degrees apart, or open borders). ~275k dots (107k edge), 1.6 s. Triangle normals: Godot front faces wind clockwise, so outward = (c - a) x (b - a).
- **Lit by a shadow-map test.** Rays now only write distance into the cube-map texture. `echo_fixed.gdshader` maps each dot's direction from the scan origin into the cube (same equi-angular table) and lights it if its distance <= the ray's + tolerance (5 cm + distance x texel angle / facing). Per-ray dots are gone (`echo_points` deleted). Detail and people dots use the same test (lenient: max of the ray and its 4 neighbours), so only what the wave reached shows.
- **One ring, no flash/dim.** The designer disliked "all dots on screen, then they turn off" and the several rings. Now one front: a dot lights when distance / 16 m/s has passed and stays at its final brightness (x1.7 for ~0.05 s as the front passes). No settle.
- **Scans add up.** 4 slots (depth texture + detail + shadow clouds each); a click takes the oldest slot. People: one cloud, latest scan only (no ghost copies). Fade is per slot by the walk clock: `notify_moved(seconds)` from `main.gd` each walking frame; gone after 2.5 s of walking; standing still holds everything. Teleports in tests count as FADE_TIME.
- **No seeing through walls.** `main.gd::_build_occluders` gives every house mesh (not grabbables, not people) a black child on visual layer 13, which only the blind camera renders. `occluder.gdshader` pushes it back along the view ray (6 cm + 4% of distance, same pixels) so dots on its own surface aren't cut at grazing angles (they were half-circles on the ceiling); fixed dots on surfaces facing away from the camera are culled, which keeps the far side of thin walls hidden despite the push.
- Autotest additions: `16_second_scan_0.1s` (second click keeps the first), `17_hall_old_scan_hidden` (`place` moves without fading).

## 2026-11-10: Iteration 1.9: short echo, fade on key press, main menu

- **Echo range 14 m -> 3.5 m** (designer: a quarter). `MAX_RANGE` drives the ray length, the fixed/detail shaders (`max_dist`) and the brightness falloff (exp(-d / 0.45 range), smoothed to 0 over the last quarter). Wave 16 -> 6 m/s so the ring still visibly travels (~0.6 s to the edge). Sound range is unchanged (14 m).
- **Fade on key press**, not on walk time/distance: `scanner.start_fade()` on W/A/S/D press stamps every holding slot; gone 0.6 s later. While a key is held, `start_fade(true)` each frame catches scans made on the move once their wave is out (so they show once). Autotest `goto` now `clear()`s.
- **Main menu** (`scenes/menu.tscn` is the main scene now): Play -> Tutorial / Level 1 / Back, plus Quit. `Main.level` is a static var read in `main.gd::_ready`. Test args skip the menu. Esc twice in game -> menu.
- **Tutorial** = the house without people + `tutorial.gd` hints (scan, look 2.5 rad, move, scan again, door, grab). The autotest's scripted scans call `scanner.scan()` directly, so they don't advance hints.

## 2026-11-10: Iteration 2.0: living dots, a body that walks, the reaching hand

- Echo range 3.5 -> 4.0 m (designer: +15%). Design answers recorded in `rules.md` section 10.
- **Dots are not a grid any more.** `world_dots._fill` puts one dot anywhere inside each cell of the world-anchored grid (place = hash of the cell and plane, so coplanar surfaces agree and nothing doubles); edge dots get uneven spacing. 11 cm cells, ~380k dots, ~3.3 s to build. `echo_fixed.gdshader`: per-dot size (0.5-1.6x, 6% are big and soft), a 1.4 cm drift, brightness breathing; size is capped by distance so dots right at your face don't balloon.
- **Walking.** `player.gd`: 1.45 m/s walk, 3.3 m/s run (Shift), eased velocity, head dip 3.5 cm and 2.2 cm sway per step (1.7x running), lean into turns, `stepped` on each footfall -> soft non-positional step sound + a ripple at your feet.
- **Reaching hand.** A 0.75 m ray along the view; on a static surface the fixed dots within ~0.4 m of the hit light up (`touch_pos` / `touch` uniforms, eased in and out); on an interactive thing, `live.touch(body, 0.25)`.
- Not built yet from the answers: the bad person hearing you, getting caught, the key and escape door, breathing/heartbeat/fear, new people models, the staircase.

## 2026-11-10: Iteration 2.1: the stalker, the key and the front door

- Echo wave 6 -> 12 m/s (designer: about 2x, "the speed of sound, but not that fast").
- **Stalker** (`stalker.gd`): a brain on top of `npc.gd`. Hearing = distance <= radius x sqrt(transmission between the two rooms). States PATROL / INVESTIGATE / LISTEN (4 s) / RETURN. He only ever knows the last heard position, so standing still silent is how you hide. Pace 1.2 (heard), 1.65 (heard within 4.5 m); the step rhythm speeds up with the pace, which you can hear.
- **Navigation:** `NavigationServer3D.parse_source_geometry_data` + `bake_from_source_geometry_data` on the house's static colliders (mask world + stair ramps, doors and grabbables set to layer 0 during the parse), 0.1 m cells, ~75 ms. Agent radius 0.3 left the 1 m staircase unconnected (rail + open edge eat 0.3 each); 0.2 connects it. Path points are dropped to the floor with a ray (the mesh floats a cell above).
- **Caught:** within 0.85 m, same storey, clear ray. `live.touch(npc, 4)` draws his whole outline (touch is visual), camera turns to him and shakes, `scare.wav`, fade to black, reload. In test runs it quits instead.
- **Goal:** `Keys` moved to a random spot from `KEY_SPOTS` (each checked with a ray: must rest on a non-grabbable surface). `FrontDoor` (already in the south wall of the living room) is interactive with meta `exit`. Locked rattle (`door_locked.wav`) is a 9 m noise.
- Not built yet: breathing / heartbeat / fear effects, new people models, the staircase rebuild.

## 2026-11-10: Iteration 2.2: breathing and fear

- `fear.gd`: level = ((9 - d) / 7.8) ^ 1.6, x (0.3..1 by sqrt of the transmission between the rooms), x 1.2 while he investigates; rises 1.1/s, falls 0.22/s. (A plain smoothstep from 10 m saturated at 3.7 m: no gradation left for the last metres.)
- Breath loop always on (-30 dB calm, -8 dB and 1.6x pitch at full fear; running adds exertion). Heartbeat one-shot at 62..150 bpm once level > 0.06.
- Seen: `tremble` uniform in both dot shaders (a 22 Hz shake, up to 5 cm), and a vignette whose dark ring closes in with fear and pulses inward on each beat. Forced to 1 when caught.
- Fear is off in the look-and-feel test runs (no bad person passed in), on in `--stalker`.

## 2026-11-10: Iteration 2.3: no breathing, hiding, heavier steps, wider touch, a simple Level 1

- **Breathing removed** (designer didn't like it). Heartbeat, tremble and vignette stay (designer likes them a lot).
- **Hiding.** Wardrobes (name contains "Wardrobe") and bed frames ("BedFrame*") get meta `hide` and join `interactive`; mattress / duvet / pillow / headboard point to their frame (`hide_ref`). Beds were solid boxes on the floor: frames now sit on 0.3 m legs. Entering: collision mask 0, tween to the middle of the wardrobe (eye 1.5) or under the frame (eye 0.17), facing where you came from; leaving tweens back there. `hide_mask.gdshader` leaves an upright or a flat slit. From inside a solid box the occluder's back faces are culled and rays start inside the shape, so you see and scan the room as if the wardrobe were not there: the slit is what sells it.
- **Hidden and safe unless heard:** `stalker.player_hidden` blocks the normal catch; a noise he hears while you are hidden (`_noise` -> `knows_hide`) lets him catch within 1.6 m with no line-of-sight test. Cleared when you get out.
- **His steps:** new `step_bad.wav` (58 Hz heel + 74 Hz sole, 0.4 s), `step_peg.wav` now drags 0.1 s then knocks with a 310 Hz wood resonance; step interval 0.6 -> 0.74, limp 0.16 -> 0.27, louder. Each step sets `_shock` (by closeness, up to 8 m) which drives the dot tremble and a tiny camera dip. The drag bends rule 2 ("just a bump"); the rule text now says so.
- **Touch patches:** `echo_fixed` takes 8 touches (xyz + strength, radius each). 0 = hand (0.75 m, was 0.42). Footfalls add a 0.6 m patch for 1.3 s; `player.bumped` (slide collision, wall-like normal, walking into it, 0.45 s cooldown) adds 0.85 m for 1.8 s + a thud heard from 3 m.
- **Level 1 map:** designer: "I'm in the living room and suddenly he came... it should be very simple". In real play only the bad person exists (`_solo()`), he starts upstairs (5.5, F, 0) and waits 18 s, and his round (`BAD_ROUND`, walked on the navmesh by `stalker.patrol`) never enters the living room. The old three-people setup with fixed waypoints remains for `--autotest` / `--features` / `--model`.
- Hunt pace now needs the noise to be on his storey (3 m straight through the floor used to count as "close").

### Where this stands (for picking up later)
Built and passing scripted runs, not yet played by hand, not committed: everything above plus iterations 1.7 to 2.2.
Still to do from the designer's answers (rules.md section 13): new people models (clothes, hair, hands, proportions, natural walk, cleaner outline), rebuild the staircase and fix oddly placed furniture.
Open questions to the designer: voiceover (whose voice, which language), the story, real sounds via ElevenLabs.
