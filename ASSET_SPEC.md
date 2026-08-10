# Custom Asset Spec — Slipframe

Authored USDZ/texture targets for Slipframe. Keep the listed dimensions, pivot, and readability rules so gameplay stays fair in mixed reality.

Art direction: **Synth Riders–adjacent neon corridor** — deep ink floors, cyan guide light, molten-gold collectibles, translucent hazard red. Avoid purple-gradient UI tropes.

---

## 1. Hazard Wall (`WallHazard.usdz`)

**Role:** Lane-blocking obstacle the player dodges with head/hands.

**Detailed look:**
- A thick rectangular energy barrier, ~0.70 m wide × 1.80 m tall × 0.70 m deep.
- Body is a semi-transparent crimson plasma slab (opacity ~0.4–0.5) with faint internal turbulence — soft vertical streaks and heat-haze distortion, not opaque plastic.
- Front face has a bright coral/peach emissive frame (~2–3 cm) on all four edges so the silhouette reads against passthrough at 6–8 m.
- Three thin vertical energy veins on the front face, pulsing slowly.
- Corner orbs (small glowing pips) at each front corner for craft detail.
- Optional subtle danger chevron watermark inside the slab (desaturated red, low contrast) — readable up close, not noisy at distance.
- Soft outer volumetric glow / aura slightly larger than the collision volume (visual only).

**Technical:**
- Pivot at geometric center.
- Collision should still match current kill-box sizing (code uses width/height/thickness constants).
- Prefer a single root with named children: `Body`, `Frame`, `Glow`.
- Material: translucent PBR + emissive; avoid heavy refraction (MR readability).

**Replace in code:** `GameVisualBuilders.makeWallSlab`.

---

## 2. Collectible Coin (`CoinGold.usdz`)

**Role:** Hand-collected score pickup.

**Detailed look:**
- Classic arcade coin disc, radius ~7 cm, thickness ~2 cm.
- Polished molten gold metal with a warm specular highlight streak.
- Embossed face: concentric rings + a simple centered star or runner glyph (keep silhouette clear at arm’s length).
- Soft yellow emissive core visible through a subtle rim light so coins “pop” in bright rooms.
- Optional tiny orbiting sparkle particle (can stay code-driven).
- Idle motion (code): gentle Y bob + Y-axis spin.

**Technical:**
- Pivot at center.
- Face should be visible when the disc’s flat side faces the player (±Z).
- Keep collect radius feel (~24 cm hand proximity in code).

**Replace in code:** `GameVisualBuilders.makeCoin`.

---

## 3. Track Floor Module (`TrackFloor.usdz` or tiled trim sheet)

**Role:** Fixed play corridor from stand line to portal.

**Detailed look:**
- Dark ink / charcoal metal plating with a faint cyan grid etched into the surface.
- Three lane grooves or inlays under the left/center/right paths, each with a soft neon core and wider dim under-glow.
- Side rails: dark brushed metal bars with a thin cyan LED strip on top.
- Occasional distance tick marks or rivet rows for parallax while obstacles approach.
- Slight edge bevel so the slab feels physical on the real floor, not a paper decal.

**Technical:**
- Authored for arbitrary length (tilable in Z) or one stretch mesh scaled in code.
- Width ~3.2 m; Y ≈ 0 at the walking surface.
- Avoid high-frequency normal maps that shimmer under head motion.

**Replace in code:** `GameVisualBuilders.makeTrack`.

**Catalog texture already shipping:** `TrackFloor`, `LaneStripe`.

---

## 4. Portal Aperture Frame (`PortalFrame.usdz`)

**Role:** Always-visible Synth Riders–style window at track end; obstacles emerge from it.

**Detailed look:**
- Rounded rectangular aperture ~3.6 m × 2.5 m, corner radius ~0.85 m.
- Layered neon rim: outer soft cyan bloom, mid saturated cyan band, inner near-white hot edge.
- Four corner spark nodes that feel machined, not pasted sprites.
- Subtle breathing pulse (scale or emissive intensity) — code already pulses the rim root.
- The portal *plane* itself stays a RealityKit `PortalMaterial` mesh; art is the surrounding frame only.

**Technical:**
- Pivot at aperture center.
- Frame should leave the inner rounded rect fully open (no mesh covering the portal plane).
- Keep GPU cost modest — bloom via emissive meshes, not giant transparent cards.

**Replace in code:** `GameVisualBuilders.makePortalRim`.

**Catalog texture already shipping:** `PortalGlow`.

---

## 5. Portal Tunnel Interior (`PortalTunnel.usdz`)

**Role:** World seen *through* the portal (`WorldComponent` target).

**Detailed look:**
- Closed dark tunnel box so passthrough does not leak through the aperture.
- Receding neon rings / ribs that shrink with depth.
- Floor chevrons pointing toward the player (content streaming outward).
- Cyan floor rails and a distant hot glow / vanishing-point light.
- Mood: cool void, slight fog falloff, no busy props that distract from emerging walls/coins.

**Technical:**
- Built in portal-local space; depth ~10–12 m behind the aperture.
- Unlit / emissive friendly — portal interiors are often dim.

**Replace in code:** `GameVisualBuilders.makePortalInterior`.

---

## 6. Start Stand Zone (`StartPad.usdz`)

**Role:** Shows where to stand before pressing Start.

**Detailed look:**
- Soft warm cream/amber glowing pad on the floor (~2.4–2.6 m wide).
- Crisp stand line across the pad.
- Center tick marking the midline.
- Two or three forward-pointing chevrons toward the portal (−Z) so orientation is obvious at a glance.
- Keep it quiet — readable, not a UI billboard.

**Technical:**
- Pivot on floor at stand line (z = 0).
- Very low height; must not trip visual “collision” with feet passthrough.

**Replace in code:** `GameVisualBuilders.makeStartMarker`.

**Catalog texture already shipping:** `StartPad`.

---

## 7. VFX: Coin Collect Burst

**Role:** Feedback when a hand grabs a coin.

**Detailed look:**
- 8–12 small gold/cyan sparks exploding outward with short gravity falloff (~0.3 s).
- Optional soft radial flash (gold, additive) lasting 1–2 frames.

**Replace in code:** `GameVisualBuilders.makeCollectBurst` / `VisualFXController`.

---

## 8. VFX: Wall Hit Flash

**Role:** Pain feedback on head/hand wall contact.

**Detailed look:**
- Brief crimson wash plane near the hit (~0.25 s), slight scale-up.
- Optional shatter shards of the wall frame flying outward (future).

**Replace in code:** `GameVisualBuilders.makeHitFlash`.

---

## 9. HUD / Brand chrome (2D)

**Role:** World-anchored play panel.

**Detailed look:**
- Frosted glass panel with cyan→gold hairline gradient stroke.
- Rounded display type; score/coins in accent chips (cyan / gold).
- Start button tinted cyan; Restart tinted hazard red after a hit.

Already implemented in `PlayHUDView`. Optional future: custom SF Symbol replacements or a small wordmark SVG for “Slipframe”.

---

## 10. App Icon layers (visionOS solid image stack)

**Back:** Dark ink rounded field with faint cyan grid.
**Middle:** Neon rounded portal aperture facing camera, soft bloom.
**Front:** Gold coin disc slightly offset + thin red hazard slab silhouette for game identity.

---

## Delivery checklist for artists

| Asset | Format | Scale | Pivot | Notes |
|-------|--------|-------|-------|-------|
| WallHazard | USDZ | meters | center | Translucent + emissive frame |
| CoinGold | USDZ | meters | center | Disc faces ±Z |
| TrackFloor | USDZ / trim | meters | floor Y=0 | Tilable in Z |
| PortalFrame | USDZ | meters | aperture center | Hollow center |
| PortalTunnel | USDZ | meters | aperture center | Behind −Z |
| StartPad | USDZ | meters | stand line | Flat on floor |
| CollectBurst | USDZ or particles | — | — | Short-lived |
| HitFlash | material / mesh | — | — | Additive red |

When dropping in USDZ files, load via `Entity(named:in:realityKitContentBundle)` (or app bundle) and swap the corresponding `GameVisualBuilders` factory while keeping gameplay transforms/collision constants unchanged.
