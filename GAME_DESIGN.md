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

#### Example environments

| Environment | Look / feel | Music mood | Special twist |
|-------------|-------------|------------|---------------|
| Fog Hollow | Darker, dense fog, muted colors | Low, tense drone | **Worse visibility** — walls appear later / harder to read at distance |
| Low Crawl | Cool blue, tight vertical space | Sparse, close percussion | **Low ceiling obstacles** — duck (lower head) to clear hanging barriers |
| Ghost Glass | Pale wash, soft light | Thin, eerie pad | **Harder-to-notice walls** — a few obstacles are much more transparent |
| Ember Run | Warm amber / orange glow | Driving, brighter beat | Baseline difficulty; clearer walls, standard visibility (breather biome) |

#### Switch rules

- Timer: ~45s per environment, then pick another at random.
- On switch: crossfade music, lerp ambience/fog/tint, keep player score/speed continuity (don’t reset the run).
- Telegraph briefly (e.g. 1s color wash or audio sting) so the change doesn’t feel like a glitch.
- Spawn rules for the new twist apply to newly spawned obstacles; don’t unfairly rewrite what’s already on top of the player.
