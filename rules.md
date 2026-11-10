# Rules of the game

The logic of Echo, in one place. If a feature breaks one of these rules, the feature is wrong, not the rule. Change a rule only when the designer says so, and update this file when they do.

This is a **horror story game**. You play a blind person in a house that is not entirely theirs to be alone in. **You never see with light. Everything you perceive arrives through four senses: sound, smell, touch, and the echo you make yourself, and all of it is drawn on a black screen.** The player never sees the lit world (the sighted view exists only so the developer can check what is there).

---

## 1. Sound is visual

> **If you can hear it, you can see it.**

- Everything that makes a sound is faintly visible: a weak, blurry, drifting cloud of dots on the thing that makes the sound. Never sharp. You aren't sure what it is, only that something is there.
- **Louder = brighter and more complete.** Quiet sounds show as a few scattered blobs; loud sounds fill in the whole shape. What you see is exactly as strong as what you hear.
- Sound sight is **never as clear as an echo scan** (rule 3).

### How loud something is by the time it reaches you

Every sound has its **own loudness**, and what reaches you is that loudness after four things:

1. **The object.** Each thing is different: the TV is by far the loudest, then the washing machine, then the dripping tap, the fan and the fridge, and the wall clock is barely a whisper. A fan in the next room and a TV in the next room do not sound alike.
2. **Distance.** You hear things well only when you are **close**. The level falls with the square of the distance, and past about 14 m there is nothing at all.
3. **What is in the way.** Every closed door, every wall and every floor between you and the sound cuts it down, and **they multiply**: two walls are far quieter than one. A closed door is about −18 dB, a wall about −28 dB, a floor between storeys about −26 dB. An open doorway or arch costs nothing. The sound takes the best route it can find (through an open door down the hall beats going through a wall).
4. **Its own pattern.** A ticking clock flickers with each tick. A TV that goes quiet between ads goes dark between ads.

What you **hear** follows the same numbers: quieter, and **duller** (muffled) the more is in the way. Standing right at a wall or a door, you hear a little of what is behind it. **Open the door and it floods in: louder, clearer, easier to see.** Close it and it drops away.

- **Very loud things still show a little through a wall** (the alarm clock): small and dim, but there.
- Long way round: sound coming up or down the stairwell is cut by about half a level on top of distance.
- **Short sounds** (a footstep, a door) leave a brief flash of whatever made them, with the same rules.

## 2. Footsteps

- A footstep is **just a bump**: the weight landing. No pings, no squeaks, no sound effects. People differ by **how heavy and how hard** the bump is, and by their rhythm, not by a special noise.
- **Close footsteps are clear and sharp. Farther ones are weaker.** From another room, muffled and faint.
- **From the floor above (or below) you still hear them, very weakly**: the floor carries them, dull and low. You can still tell **the hard knock of the wooden leg** from a shoe, weakly. As the person comes closer it becomes clearly a footstep, then clearly *whose* footstep.
- Footsteps are also **felt through the floor** as ripples, weakened by distance.

| Who | The bump | Shows as |
|---|---|---|
| **The bad person** | a **heavy, slow shoe**: his whole weight, heel then sole. Then the wooden right leg: it **drags a little, then lands with a hard, dry knock**. A marked limp, an uneven rhythm | the wooden leg and its step are **red**; the shoe step is white |
| **A stranger** | a heavy, slow shoe bump | white |
| **The friend** | a light, quick bump | **light green** |

- **Build changes the silhouette and the weight of the step.** Bigger or heavier people have a different outline and heavier steps. Everyone has a real human silhouette (that is how you read them).
- **The bad person's steps come through the floor.** Each one makes the dots jump, the more the closer he is (up to about 8 m), and the peg harder than the shoe.
- **Colour on a step means you know the person.** Only the bad person's right leg and the friend get a colour.

## 3. The echo (the tongue click)

- Click (Space / left mouse) and a sound wave goes out **from your position**, in every direction at once, like a real sound: it reaches **near things first and farther things a moment later**. It is not a sweep across the screen: it spreads from where you stand.
- **The house has fixed dots.** Every surface carries its own dots, always in the same place: **scattered at random** over walls, floors, ceilings and furniture (never rows and columns), and **close, bright lines of dots on every edge and corner** (wall corners, door frames, table edges, shelves), so the structure of the house is what you see. An echo only decides which dots light up. **The dots are alive:** each has its own size (a few are much bigger and softer), drifts a little around its place and breathes in brightness.
- **Brightness is distance.** A dot lit by a scan is as bright as its distance from where you stood allows: near = bright, far = dim. Surfaces that faced you squarely are a little brighter; edges and corners are always the brightest.
- **The capture is instant.** The scan records the world exactly as it was at the moment of the click: a person walking shows in one pose, never smeared or with a tail. A door that was swinging shows where it was at that moment.
- **The reveal is one ring going out from you.** One wave leaves your feet and travels outward across the floor and up the walls; each dot lights as it reaches it and **stays lit**. No flash, no dimming afterwards: one clear scan, every time. **The echo only reaches about 4 m** (a few steps): beyond that, nothing comes back, and dots dim toward that edge. The ring is fast, like sound: about a third of a second to get there.
- The result is a **snapshot of where you stood**, fixed in the world: **turn your head and look around inside it**. It does not move with you.
- **Scans add up.** A new click does not wipe the old one: it scans again, and what it reaches lights up on top of what you already have (the last 4 scans are kept).
- Scans **hold while you stand still**. **The moment you press a movement key they fade**, gone about 0.6 s later, however far (or little) you walk. A scan made while you are already walking shows once, then fades.
- **You don't see through walls.** What you scanned stays where it is in the world; once you walk away, the walls, floors and closed doors between you and it hide it, as they would for anyone.
- **Shadows are not left black.** What was hidden behind something (from where you stood) is filled in by the wave bouncing, as **smaller, much dimmer dots**.
- **Everything you can interact with** (doors, the TV, the alarm clock, anything you can pick up) shows in **much better detail**: dots that follow its edges, rims and corners, so you can tell what it is from a few metres away.
- **Doors are always picked out clearly**, so you can find the way out.
- A short cooldown stops click-spamming (0.45 s).
- Materials are deliberately few (see rule 7): **solid** (default), **hollow** (dots breathe), **glass** (patchy, shimmering), and the **people** materials.
- The echo catches people as dense, unbroken white dots (never patchy), with a **clear outline of the body as seen from where you stood** (head, shoulders, arms, legs), so a person always reads as a person. Only the wooden leg is red in a scan. People show from your **latest scan only**, so you never see several copies of someone.

## 4. Smell is colour

- Food has a smell, and **smell is the only thing that has colour**: broccoli green, an apple red, fried chicken orange, a banana yellow.
- Smell shows as the **shape of the food in its colour**, and **steam rises from it**, animated, in the same colour. Clearer than sound but **only close up**, and not out of another room or floor.
- Nothing else is ever coloured, except people's steps (rule 2).

## 5. Touch is visual

> **What you touch, you see, for as long as you touch it.**

- Anything you touch shows as a **clean white outline** of the object (its silhouette and its edges). You are touching it, so you know exactly what it is. Then you let go and it is gone: you are not touching it any more.
- **What you hold** stays outlined in your hand (lower right, like a tool in a first-person game) until you put it down.
- **A door you open** is outlined while it swings, so you see the door opening; afterwards it disappears again.
- **The TV**: press E on it to turn it off (or on). You see it while you press it, and once it is off it makes no sound, so you stop seeing it as a sound too.
- **The alarm clock**: the same, you see it while you wind it.
- **Your reaching hand.** Within arm's reach (about 0.75 m) of a wall or a piece of furniture you are facing, your hand is on it: the **patch of surface under your hand** (about 0.75 m around it) shows as dots, with no echo needed, so you can feel your way along.
- **Your feet.** Each step shows the **patch of floor where you put your foot down** (and the foot of anything standing there) for a moment.
- **Bumping into things.** Walk into a wall or a piece of furniture and you feel it: the patch you hit shows for a couple of seconds, with a soft thud (which the bad person can hear from 3 m). Things you can use (a door, the TV, something to pick up) show whole, as their outline, while your hand is on them.
- Touched things have **no colour**: touching tells you the shape, not the smell.
- E opens and closes doors, picks up and puts down small things, and uses things (TV, alarm clock).

## 6. The house

- Two floors: living room, hallway, kitchen, laundry, back hall, bathroom, study, bedroom, workshop, and upstairs a corridor, landing, guest room, bathroom, kids' room, storage, master bedroom and office.
- Objects make physical sense: everything rests on something, hangs from a wall, or is mounted on a ceiling. Nothing floats and there is no random clutter.
- The house is never silent: TV, fan, fridge, clock, dripping tap, washing machine. They all show as faint shapes (rule 1) and help you orient.
- Doors make a sound (the same thump opening and closing, for now), and that sound is visible too.
- The **alarm clock** (living room coffee table): press E, it ticks for a few seconds, then rings very loudly. Wind it, go to another room, shut the door, and watch it through the wall.

## 7. Keep it minimal

- Visual language: **monochrome dots**. Colour is allowed only for smell (rule 4) and the wooden leg / friend's steps (rule 2).
- **Models are built realistically, but graphics don't matter.** The player never sees textures, colours or lighting: only the **structure** of things (their real shape) shows up, in dots and outlines. So models use flat colours and simple materials, no real lighting: no lamps that light rooms, no shadows. Small things you can pick up get the most careful shapes (a mug with an inside and a handle, a hammer with a claw, keys on a ring), because in an echo the shape is all you get.
- Echo materials: 1 solid, 2 hollow, 3 glass, 4 person, 5 wooden leg, 6 door. Don't add more without the designer asking.
- The controls are always on screen at the bottom.
- **Tab** shows a debug view (flat, with one light and no shadows) so the developer can see the house. It's not part of the world's logic.

## 8. Your body

- **You walk slowly and carefully** (about 1.5 m/s). **Shift runs** (3.3 m/s): fast, but loud.
- The view is a head on a body: it **dips and sways with each step**, leans a little when you turn, and takes a moment to get going and to stop.
- **Your own footsteps are heard and seen**: a soft bump and a faint ripple at your feet when you walk, louder and stronger when you run.
- **Fear follows how close the bad person is.** Nothing beyond about 9 m; most of it comes in the last few metres; full when he is a step away. A wall, a closed door or a floor between you takes some of it off. It is worse while he is coming for a sound. It rises quickly and settles slowly.
- **Your heartbeat** starts when he is near and speeds up as he closes in (about 62 to 150 beats a minute).
- **Fear shows:** the dots tremble and the edges of the view close in, pulsing with each heartbeat. This is the only warning you get that does not need a click.

## 9. Menu and levels

- The game opens on a **main menu**: Play, then pick a level. Esc twice in the game returns to the menu.
- **Tutorial**: the house with nobody else in it. One hint at a time teaches the click, looking around, walking (and the fade), clicking again, doors and picking things up.
- **Level 1**: you start in the living room, by the locked front door. The bad person is alone in the house with you, hunting by ear (rule 10). Hide (rule 11), find the keys and get out through the front door (rule 12).

## 10. The bad person hunts by ear (Level 1)

- **He looks for you by sound, and only by sound.** He never knows where you are, only where the last thing he heard came from.
- **What he can hear, and from how far in open air:** your tongue click (8 m), running (9 m), careful walking (2.5 m), a door you open or close (7 m), the locked front door rattling (9 m), the alarm clock ringing (16 m: a lure). Standing still is silent.
- **What is in the way counts**, with the same numbers as your own hearing: a closed door, a wall or a floor between you shortens how far a sound carries (a closed door to about a third, a wall to a fifth).
- **When he hears something he goes there**, round the furniture, through doorways, up the stairs. He **hurries if it was close** (within 4.5 m): then he is faster than your careful walk. He **opens closed doors** in his way, and you hear them.
- **At the place he stands and listens** for about 4 seconds, then goes back to his round.
- **His round is simple and far from you.** He starts upstairs, at the far end of the corridor, and stays there for the first 18 seconds: you hear him above you first. Then, in a loop of about a minute and a half: the landing, down the stairs, through the back hall to the kitchen, the hallway (outside the bedroom), and back up. He stops for a few seconds at each. **He never comes into the living room** (where you start, by the front door) unless he hears something.
- **Level 1 has only him in it** (no stranger, no friend).
- **If he comes within reach (0.85 m) with nothing between you, he has you.** Touch is visual: for a moment you see all of him, outlined, right in your face. Then black, "He found you.", and the level starts again.
- So: click as little as you dare, move away from where you clicked, then stand still while he passes.

## 11. Hiding

- **E on a wardrobe gets you inside it; E on a bed gets you under it.** E again and you are out, where you stood before. (Four wardrobes, and every bed.)
- Hidden, you can look and click, not move. You see only through the crack: an upright slit from a wardrobe, a low flat slit from under a bed.
- **Hidden, he cannot find you**, even standing right next to you... **unless he hears a sound come from your hiding place.** Getting into a wardrobe is heard from 4 m, sliding under a bed from 2 m, and a click from inside from 5 m (muffled). If he heard it, he knows: he comes, opens it, and has you.
- So hide before he is close, and then be silent. Your heart will tell you how near he is.

## 12. The key and the front door (Level 1)

- **The front door** (living room, south wall) is the way out, and it is locked. Trying it without the key rattles it loudly.
- **The keys** are left in one of several places in the house, different each time. Pick them up (E) and carry them to the front door: E on the door with the keys in your hand and you are out.

## 13. Decided by the designer, not built yet (2026-11-10)

- **People are not mannequins.** Clothes, hair, hands and shoes (a different outline per person), correct proportions, a natural walk, and a cleaner outline with less fill.
- **The house:** keep the rooms; rebuild the staircase properly and fix furniture that sits in odd places.

## 14. Not yet (ideas that follow the rules but aren't built)

- A story where you must tell people apart by build and step sound alone.
- Cinematic scenes (see `docs/ideas.md`).
- The echo wave itself being weakened by closed doors.
- The story: this is the sandbox; the horror is still to be written on top of these rules.
