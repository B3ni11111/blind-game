> Purpose: Plan and checklist for the first playable prototype (one room, echo scan, frozen afterimage, NPC footstep vibrations).

# Prototype 1: "First Scan"

**Goal:** walk around one dark room in first person, press a key to send out an echo, and see the room as a frozen dot image that stays on screen while you keep moving. Plus an unseen NPC whose footsteps show up as floor vibrations.

**Engine:** Godot 4.5.1 (GDScript). No sound in this phase.

---

## Core rules (decided)

1. **The screen is black by default.** You only see what the last scan captured.
2. **A scan is a snapshot, like a flashbang afterimage.**
   - When you scan, the game captures the room *from where you are standing and looking, at that moment*.
   - That image is drawn on screen as dots, revealed **top to bottom** like a scanline sweep.
   - The image is **frozen to the screen**. You can still walk and turn the mouse, but the picture does not change. It stays the old scan until it fades or you scan again.
   - You can't see where you're going while moving, only where you *were* looking.
3. **Distance = clarity.** Close surfaces get dense, bright, sharp dots. Far surfaces get sparse, dim dots that jitter or blur.
4. **Very limited materials. Everything is the same white dot except:**
   - **Solid** (default): wood, concrete, fabric, walls, all the same.
   - **Hollow**: a slightly different dot look (proposal: dots softly "breathe" or pulse).
   - **Glass**: a slightly different dot look (proposal: sparser dots that flicker or shimmer).
   - The difference is subtle and still monochrome. Later, the real difference comes from **sound**.
5. **The afterimage fades.** After a few seconds the scan fades back to black.
6. **NPC footsteps (not the player's scan).** An unseen NPC walks around the house. Each step makes a faint **vibration ripple on the floor** at its position. You see this live, even without scanning, but never the NPC itself.

## Open questions (default chosen, can change)

- **Scan cooldown:** default 1.5 s between scans, so you can't spam it.
- **Afterimage duration:** default ~4 s to fade fully.
- **Movement during the sweep itself:** default is that you *can* move. The image is frozen anyway.
- **Do NPC ripples also fade into the scan image?** Default: no. Ripples are a separate live layer.

---

## How it works (technical)

1. **Room:** simple greybox meshes (walls, floor, table, chairs, a couch, a door, a window = glass, a box/cabinet = hollow). No textures.
2. **Material tagging:** each mesh gets a tag: `solid` / `hollow` / `glass` (via a small script or groups).
3. **Scan capture:** a hidden `SubViewport` with a camera that copies the player camera **at the moment of the scan** and renders **once**. A special shader writes, per pixel: **distance** + **material ID** (not real colors).
4. **Dot renderer:** a fullscreen shader reads that frozen capture and draws it as a grid of dots:
   - dot size/brightness from distance, plus random jitter for far dots
   - a sweep line moving top to bottom reveals the dots
   - edge detection to make object outlines readable
   - hollow and glass get their small effect
   - an overall fade over time
5. **Player:** `CharacterBody3D` with WASD + mouse look. The real camera still moves (needed for walking and the next scan), but it renders **nothing visible**. The screen is only the dot overlay.
6. **NPC:** an invisible node walking a loop path through the room/hallway. Every step spawns a ripple: a faint expanding ring of dots on the floor, projected to the screen at the step's real position (this layer *is* live).
7. **Grab (stretch for this prototype):** look at a small object, press E to "hold" it. Shows it as a dense, clear dot shape near the bottom of the screen. Can be cut if time runs short.

## Controls

| Key | Action |
|---|---|
| WASD | Walk |
| Mouse | Turn (doesn't change the frozen image) |
| Space / Left click | Scan (echo) |
| E | Grab / drop (stretch) |
| Esc | Release mouse / quit |

## Steps

- [x] 1. Create the Godot project + folder structure
- [x] 2. Build the greybox room (living room + hallway + kitchen) with material tags
- [x] 3. Player controller (walk + look), screen black
- [x] 4. Scan capture: done with row-by-row raycasts from the frozen pose instead of a SubViewport (simpler, and the sweep is real)
- [x] 5. Dot overlay shader: dots by distance, top-to-bottom sweep, fade
- [x] 6. Hollow + glass dot effects, edge outlines (silhouettes + corners)
- [x] 7. NPC walker + floor vibration ripples
- [x] 8. (Stretch) Grab an object (mug, bottle)
- [x] 9. First tuning pass (verified with autotest screenshots)
- [x] 10. How to run it: open in Godot 4.5.1, press F5

## Iteration 1.1 (2026-11-08)

- [x] Presence silhouette visible in scans (solid, unbroken white dots); without scanning only footsteps
- [x] Bedroom off the hallway with a hinged door (E to open/close)
- [x] Tongue click on every scan
- [x] Ambient sounds, heard but not seen: TV ad (living room), fan (bedroom, muffled when the door is closed), fridge, clock
- [x] No minimap (decided against: too easy)
- [ ] Cinematic scenes: later (see ideas.md)
- [ ] Sounds verified by ear (the autotest can only check they load)

## Iteration 1.2 (2026-11-08)

- [x] Snapshot held until the player walks
- [x] Realistic human silhouette (jointed body, walk cycle, idle head turns)
- [x] Bad person: wooden right leg, slight limp, peg knock vs. shoe thud, different ripple
- [x] Blind / sighted toggle (Tab) with real lighting
- [x] New rooms: bathroom, study, laundry; much more furniture and objects everywhere
- [x] New sounds: dripping tap, washing machine, footsteps; muffled behind closed doors
- [ ] Sounds verified by ear

## Done when

You can launch it, walk blind, press Space, watch the room draw itself top to bottom in dots, turn around and still see that frozen image fade away, tell glass and hollow apart from everything else, and notice footstep ripples crossing the floor in the dark.
