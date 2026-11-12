# Slipframe UI features

## How to play

- Six self-paced basics: track orientation, dodging, token collection and bonus, stepping away, choosing a rift, and starting a first run.
- One instruction per step, beside a deterministic miniature demonstration. Replay, pause, step backward, or choose a lesson. The animation holds its final pose until the player continues; there is no synthesized narration or automatic lesson advance.
- Scrub the demonstration to inspect a moment. Switching sections remembers the current lesson and step; Back at a lesson boundary returns to the previous lesson's final step. Readouts demonstrate token counts, shield state, distance rewards, and bonus drain. Each modifier and run mode has its own step.
- Closing a guide returns to the originating console page and preserves the selected biome. Choose a mode explicitly returns to setup.
- Optional guides cover all eight biomes, then difficulty, modifiers, and run modes. Biome cards open the corresponding lesson directly. Reduced Motion uses discrete setup, action, and result poses.
- The examples are demonstrations: no hand-tracking requirement, physical miniature interactions, live settings changes, or score submission.

## Run setup

- Start a run in the selected mode or play again after the previous run ends and the field clears.
- **Normal** starts in Ember Run. At each junction, the player moves into a lane to choose one of three destinations. Each choice has a biome, a difficulty, and an optional modifier for that visit.
- **Loop** lets the player choose one biome and play it continuously.
- **Playlist** lets the player choose one or more biomes and either pick the first biome or start at random. Subsequent biomes shuffle within the selection. If the selected starting biome is removed, the start returns to random. A playlist needs at least one biome to start.
- **Daily** gives players the same seeded biome sequence and obstacle patterns for the day. Players can check the challenge date, time until the next Eastern Time midnight, and their best score for the current day.
- Browse the biome roster and learn the mechanic each biome adds. Preview the starting environment while choosing a mode or biome.
- Consult the portal guide to learn how to select a destination, how difficulty affects the run, and what each modifier does.

## Run feedback and results

- Check the live score, token count, and current score bonus.
- Identify the active rift modifier and its effect, including whether Aegis has spent its shield.
- Get a brief biome-specific hint on entering Lattice Forge or Gyre Gate. Lattice Forge asks players to aim a hand to lock onto a shape and move their hand to guide it. Gyre Gate asks players to pass through hoops and time their movement through the rotating openings.
- Get a reminder to return to the play area after stepping outside it. Obstacles and music slow to a stop and resume when the player steps back in.
- Review the final score, token count, highest score bonus, close slips, rifts crossed, and performance grade. The grade uses peak bonus percentage plus four points per close slip and ten per rift crossed. Thresholds are 150 for S, 100 for A, 65 for B, and 30 for C, with D below 30.
- Find out when a run sets a new personal best for score or tokens.

## Leaderboards and sharing

- Browse separate score and token rankings for Normal, each Loop biome, and the current Daily challenge. Playlist runs are unranked.
- Compare Game Center results against all players or friends and check your own rank and ranked value.
- Keep independent local personal bests for score and tokens even when signed out of Game Center. Sign in to load online rankings and submit eligible results.
- See whether rankings are loading, empty, or unavailable.
- Share a recorded Daily best through Messages with the score and challenge date already filled in.

## Settings and privacy

- Show or hide the floor track between runs. The preference persists across launches and leaves the playable boundaries and collision rules the same.
- Show or hide wall and ceiling accents. Sparse lines are clipped to the actual triangles of detected, classified wall and ceiling planes; there is no rectangular-extent or synthetic-room fallback. Horizontal wall seams share world heights around corners. Broken contour arcs sit on the ceiling. A faint opacity wave climbs cached wall traces and reaches the ceiling arcs during transitions; its animation generates no meshes. New surfaces fade in, and decorations dim during play. Reduced Motion removes the echo and breathing animation. Passthrough remains clear.
- Open the privacy policy.
