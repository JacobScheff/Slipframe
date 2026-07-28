# Endless Runner — Game Design Plan

VisionOS / RealityKit immersive game using hand tracking and body position. Simple core loop, clear feedback, room to grow.

---

## Core Loop

**Fantasy:** You’re flying/running forward through a lane. Red walls come at you — dodge with your body. Gold coins float nearby — grab them with your hands.

**Controls**

- **Dodge:** Your head/body position maps to left–right (and optionally slight up/down). Stand in place; lean or step side to side.
- **Collect:** Hands are the collectors. Reach into a coin’s volume to pick it up (no buttons).
- **No jump button** — keep it to 2 actions: move + reach.

**Why this works on Vision Pro:** Body dodge feels physical; hand grabs feel like magic. Two verbs, clear feedback.

---

## Playfield Layout

Think **3 lanes** (left / center / right), not a free 2D plane — easier to read and balance.

```
← left lane | center | right lane →
         YOU (head = lane position)
              ↓ world scrolls toward you
     [coin]     [red wall]     [coin]
```

- **Red walls:** Semi-transparent, full-height slabs that block 1–2 lanes. Collision = head (or torso proxy) enters wall volume → hit.
- **Coins:** Small glowing spheres slightly off the main path so you must *reach*, not just walk into them.
- **Scroll:** World moves toward the player along −Z (or player “runs” forward). Spawn ahead, despawn behind.

---

## Rules

| Rule | Suggestion |
|------|------------|
| Hit wall | Lose 1 life (3 lives) **or** instant run over |
| Miss coin | Nothing — optional, not punishing |
| Coin collect | +10 score, soft chime + particle pop |
| Survive | Score ticks up with distance |
| Speed | Starts calm; ramps every ~20–30s |
| Patterns | Wall → gap → coin stretch → double walls → speed bump |

**Win condition:** None — high score / personal best.

**Session length:** 30–90 seconds for a good first run is ideal.

---

## Obstacle & Coin Design

### Walls (danger)

- Transparent red (`opacity ~0.35–0.5`), soft emissive edge so they read in mixed reality.
- Variants: single-lane block, double-lane block, “gate” with a hole (optional later).
- Telegraph: spawn far enough ahead (~4–6 m) that you can react.

### Coins (reward)

- Float at hand height (~chest to shoulder).
- Place **beside** the safe lane so collecting means a deliberate reach without walking into a wall.
- Occasional “stretch coin” farther out for skill players.

### Fairness rule

Never put a required coin *inside* a wall’s kill volume. Coins always sit in a safe pocket.

---

## Feel & Feedback

- **Hit:** Brief red flash / haptic pulse / wall shatter + freeze-frame, then restart or life lost.
- **Coin:** Snap to hand → dissolve; score float-up.
- **Speed:** Subtle wind/whoosh that rises with difficulty.
- **UI:** Score + lives as a small world-anchored panel or follow-head HUD — don’t clutter the first view.

---

## Difficulty Curve

1. **Warm-up:** Only center/side single walls, coins near body.
2. **Mix:** Alternating left/right walls; coins opposite the safe lane.
3. **Pressure:** Faster scroll, tighter gaps, occasional double-threat (wall + far coin).
4. **Breathing room:** Every N obstacles, a short empty stretch so players recover.

---

## MVP Scope

Build this first:

1. Mixed immersive space, world scrolling toward player
2. Head X → lane position
3. Red wall spawn + head collision → game over
4. Hand joint collision with coins → score
5. Score + restart button

Skip for v1: jumps, enemies, power-ups, multiplayer, fancy menus.

---

## Post-Base Implementation

Features to build **after** the MVP loop is solid (scroll, walls, coins, score, restart). Do not block the base game on these.

### Near-miss reward

- When a wall passes the player without a hit, and the player’s head was within ~20 cm of the wall’s kill volume, award a small score bonus.
- Feedback: quick spark / soft “whoa” chime / brief score float (distinct from coin pickup).
- Goal: reward tight, skilled dodges so surviving close calls feels intentional, not lucky.

### Momentum coins

- Occasionally spawn a short arc/chain of coins that crosses lanes (e.g. 3–5 coins in sequence).
- Collecting them in a continuous streak builds a combo multiplier; breaking the chain resets it.
- Feedback: rising pitch on each grab in the chain; multiplier badge on the score HUD.
- Goal: break the “one coin at a time” rhythm and create short skill bursts.

### Environmental beats

About every **45 seconds**, the run switches to a different environment. The next environment is **chosen at random** (avoid immediately repeating the same one when possible).

Each environment has:

- Its own **color / ambience** (lighting, fog, accent tint on walls/coins)
- Its own **music** track (crossfade on switch, ~1–2s)
- One **special gameplay twist** so the switch is more than a reskin

#### Environments (roster)

The six biomes in the random pool:

1. Fog Hollow
2. Low Crawl
3. Ghost Glass
4. Ember Run
5. Storm Pass
6. Crystal Cave

##### Fog Hollow

- **Look / feel:** Darker, dense fog, muted greys and desaturated reds. Depth cues soften; distant geometry reads as silhouettes.
- **Music mood:** Low, tense drone — almost motionless, anxious underground atmosphere.
- **Special twist — worse visibility:** Spawn distance stays the same, but walls are more transparent and the environment uses fog cards + lower ambience brightness so reading obstacles is harder.
- **Gameplay notes:** Keep lane patterns fair (avoid surprise double-blocks while walls are hard to read). Coins stay at normal readability so rewards still pop through the fog.

##### Low Crawl

- **Look / feel:** Cool blue lighting, tight vertical space — the corridor feels lower and more enclosed.
- **Music mood:** Sparse, close percussion — intimate, cautious, body-aware.
- **Special twist — low ceiling obstacles:** Hanging barriers / low slabs require **ducking** (lowering the head) to clear, in addition to normal left/right lane dodges.
- **Gameplay notes:** Duck obstacles should be clearly silhouetted above the lane. Don’t stack duck-hazards with unfair side-walls in the same beat during early Low Crawl visits; mix in simple duck-only gates so the verb teaches cleanly.

##### Ghost Glass

- **Look / feel:** Pale wash, soft diffuse light, slightly ethereal. Surfaces feel thin and glassy.
- **Music mood:** Thin, eerie pad — fragile, haunted, spacious.
- **Special twist — harder-to-notice walls:** A subset of obstacles spawn much more transparent than normal red walls, so they are easier to miss visually.
- **Gameplay notes:** Not every wall should be ghosted — mix solid-readable walls with ghost walls so players stay alert. Ghost walls still use the same collision rules; only opacity/readability changes. Optional faint edge shimmer so skillful players can still learn to spot them.

##### Ember Run

- **Look / feel:** Warm amber / orange glow, clearer air, comfortable contrast. The “home” / breather biome.
- **Music mood:** Driving, brighter beat — confident runner energy.
- **Special twist — baseline clarity:** Standard visibility, clearer walls, no extra hazard verbs. Acts as a recovery biome between harsher twists.
- **Gameplay notes:** Ideal run opener. Use normal wall opacity and full telegraph distance. Good place for denser standard coins / momentum coin chains without competing biome gimmicks.

##### Storm Pass

- **Look / feel:** Cold steel blue, rain-streak atmosphere, unsettled sky/corridor energy.
- **Music mood:** Rolling thunder rhythm — pressure, gusts, weather you can feel.
- **Special twist — wind shove:** Occasional smooth horizontal drift shifts obstacle boxes (walls/coins/halves) — not the lanes or portal — so players must correct mid-approach.
- **Gameplay notes:** Telegraph wind shoves with a short audio whoosh + visual gust. Limit shove frequency so it doesn’t feel random-punishy; never shove when a wall is already imminent. Shoves should be correctable with a step/lean.

##### Crystal Cave

- **Look / feel:** Soft violet refracted light, mineral shimmer, magical cavern mood.
- **Music mood:** Chimey, crystalline — pretty, precise, slightly puzzle-like.
- **Special twist — half-crystal combine:** Normal touch-coins are replaced by **half-crystals** that must be fist-grabbed and merged across hands for a big payout.

**Half-crystal rules**

- Each spawned half is a **random type** (e.g. blue or red), each type with its own color.
- **Grab:** make a **fist** while the hand is on that half. Touching without a fist does nothing.
- **Drop:** release the fist — the held half disappears (nothing left on the floor).
- Each hand can hold **one** half at a time.
- When left and right hold **different** types, bring hands together to **combine** them into one crystal coin.
- A combined crystal is worth **5× a normal coin**, plays a short combine animation, then goes away.
- Same-type in both hands: no merge (optional soft reject feedback).

**Rare charged half:** about **1%** of halves spawn as a **charged** variant (distinct glow/pulse). Merge payouts vs a normal coin:
- no charged halves → **5×**
- one charged half → **10×**
- both charged → **1000×**

**Fairness notes for this biome:** prefer simpler / fewer walls while halves are in play so fist + combine remains readable mid-dodge. Combine distance should be generous (~15–20 cm between hands).

#### Switch rules

- Timer: each environment lasts for **its own music track length** (about ~45s; a few seconds of variance is fine). Missing tracks fall back to 45s.
- On switch: crossfade music (~1.25s), lerp ambience/fog/tint, keep player score/speed continuity (don’t reset the run).
- Telegraph briefly (e.g. 1s color wash or audio sting) so the change doesn’t feel like a glitch.
- Spawn rules for the new twist apply to newly spawned obstacles; don’t unfairly rewrite what’s already on top of the player.
- Drop any held Crystal Cave halves on environment exit (they vanish; no carry into the next biome).
- Audio files live in `Endless Runner/Music/` named by biome cue (`emberRun.m4a`, `fogHollow.m4a`, …).
