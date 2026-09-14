# Visual Asset Pipeline — Slipframe

Slipframe ships **zero authored art assets** (no USDZ, no PNG). Every mesh,
material, and surface texture is generated procedurally at runtime in Swift.
This keeps the "Xenotech Rift" look — irregular, hand-torn geometry and
etched alien plating — perfectly consistent across every biome and lets any
palette/shape tweak land in code instead of a re-export pipeline.

Art direction: **Xenotech Rift** — the portal is a literal tear in reality,
its edges jagged and shard-fringed with energy tendrils leaking into the
room. Obstacles read as alien-machined debris (a different silhouette
language per biome), crystals are faceted cut gems, and the HUD reads as
synthetic instrumentation (glass panels, gradient hairlines, corner-bracket
reticles) rather than a stock rounded card.

---

## 1. Geometry toolkit — `ProceduralGeometry.swift`

Shared deterministic mesh-building primitives used by every visual builder:

- `RadialNoise` — cheap seeded angular noise (summed sine harmonics) used to
  perturb outlines so nothing reads as a perfect circle/rectangle.
- `jaggedOutline` — a closed irregular polygon (radius-per-angle around the
  origin) — the "torn reality" silhouette reused by the portal rift, shatter
  panes, and obstacle clusters.
- `filledPolygon` — flat fan-triangulated mesh from a 2D outline (portal
  aperture, rim layers, rings).
- `extrudedPolygon` — flat-shaded prism extruded from a 2D outline along Z
  (obstacle chunks, rail vertebrae, shatter pane bodies).
- `edgeShard` — a single thin outward-tapering shard between two boundary
  points (the rift's torn-edge debris fringe).
- `bipyramid` / `crystalHalf` — faceted full/half gem meshes (Crystal Cave
  spires and the hand-held collectible crystal halves).

All builders are seeded (`SeededGenerator`, shared with `DailyChallenge`) so
a given spawn looks identical on replay while still reading as hand-cut
rather than stamped out.

**Collision stays decoupled:** every obstacle's hit-test is a plain AABB
(`WallCollision.swift`) sized independently from its jagged visual mesh, so
shapes can be as irregular as the art direction wants without ever touching
gameplay fairness.

---

## 2. Mesh builders — `GameVisuals.swift` / `GameVisualsObstacles.swift`

| System | Builder | Notes |
|---|---|---|
| Portal rift | `GameVisualBuilders.makePortalRim` | Layered jagged bloom/mid/hot rim bands, torn-edge shard fringe, crackling energy tendrils arcing into the room. |
| Portal tunnel | `GameVisualBuilders.makePortalInterior` | 26 m deep void with receding jagged rift echoes, alien monolith silhouettes, and ambient drifting motes (`RiftMoteComponent`, animated in `GameWorld.animateRiftMotes`). |
| Portal aperture | `GameWorld.buildPortal` | The `PortalComponent` plane itself is a jagged `filledPolygon`, not a rounded rect — same seed as the rim's hot inner edge so they stay concentric. |
| Obstacles (per biome) | `GameVisualsObstacles.makeBiomeObstacle` | Dispatches per `EnvironmentID`: Ember Run (magma obelisk cluster), Summit Step (rock outcrop), Storm Pass (levitating debris + sparks), Low Crawl (rib lattice fence), Crystal Cave (geode spire cluster), Ghost Glass (jagged shatter pane). |
| Duck / jump hazards | `makeDuckTendrilCurtain` / `makeSummitSpikeRidge` | Bespoke silhouettes instead of a shared bar. |
| Data Token | `GameVisualBuilders.makeCoin` | Glowing octahedron / diamond + neon facet wireframe + pulsing core + aura. |
| Crystal halves | `ProceduralGeometry.crystalHalf` | Faceted half-gem (spawn, held, and merge burst all share this mesh). |
| Track | `GameVisualBuilders.makeTrack` | Etched-plating floor, neon lane guides, segmented alien conduit rails (`makeConduitRail`). |
| Start pad | `GameVisualBuilders.makeStartMarker` | Jagged calibration sigil instead of a rounded rect. |
| Rift junction gates | `GameVisualBuilders.makeJunctionPortal` | Three clean, wordless destination apertures. Biome identity is drawn inside; difficulty uses 1–3 warning diamonds; modifiers use coin, shield, bolt, magnet, target, and lock glyphs. |

---

## 3. Surface textures — `ProceduralTextures.swift`

Every texture the materials use is drawn at launch with Core Graphics
(`CGContext` + `CGPath`/`CGGradient`) and wrapped in a `TextureResource` —
no imagesets, no shipped PNGs:

| Texture | Used by | Look |
|---|---|---|
| `trackFloor()` | `GameMaterials.trackFloor` | Etched xenotech hull plating — jittered panel grid, glowing seams, rivet glints, grain. |
| `coinFace()` | `GameMaterials.coinMetal` | Embossed alien rune disc — concentric grooves, rim tick marks, hexagonal sigil + spokes. |
| `portalGlow()` | `GameMaterials.portalRimBloom` | Alien corona bloom — cyan-to-violet radial falloff, jagged energy ring, outward streaks. |
| `laneStripe()` | `GameMaterials.laneCore` | Energized conduit — bright core gradient + segmented circuit-tick bands. |
| `startPad()` | `GameMaterials.startPad` | Warm calibration glow glyph with etched circuit arcs. |

`GameMaterials.warmTextures()` generates each texture once and caches the
result; biome retinting (`GameWorld.applyPalette`) recolors the *tint*
passed into `trackFloor(tint:)` / `laneCore(tint:)` rather than discarding
the texture for a flat fill.

---

## 4. HUD chrome — `XenotechPanel.swift`

Every world-anchored SwiftUI panel (`PlayHUDView`, `LevelSelectView`,
`LeaderboardPanelView`, `TutorialOverlayView`) shares one modifier,
`.xenotechPanel(primary:secondary:cornerRadius:)`:

- Tinted glass fill + `glassBackgroundEffect(in:)` on a `RoundedRectangle`
  (the only shapes visionOS renders with proper specular glass edges).
- A gradient hairline border blending the panel's two accent colors.
- `XenotechCornerBrackets` — four L-shaped reticle marks just inside the
  bounds, the shared "alien instrumentation" framing motif tying every
  panel back to the game's identity.

---

## 5. Adding a new biome obstacle

1. Add a case to `EnvironmentID` / `EnvironmentCatalog` as usual.
2. Add a builder function to `GameVisualsObstacles.swift` (or reuse
   `makeJaggedShardCluster` with new parameters) returning an `Entity`
   named `"wallSlab"`.
3. Wire it into `GameVisualBuilders.makeBiomeObstacle`'s switch.
4. Leave `WallCollision.swift` untouched — the AABB is sized from the
   `width`/`height`/`depth` constants only, not the mesh.

## 6. Regenerating a texture

Edit the matching function in `ProceduralTextures.swift` — every draw call
is deterministic Core Graphics, so tweaking a gradient stop or line width is
a normal code change with no export/re-import step.
