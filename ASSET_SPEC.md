# Slipframe — Blender asset pipeline

The game now uses **67 authored USDZ assets** instead of building its artwork from Swift primitives. The editable source is `Art/Blender/Slipframe_ArtSource.blend`; the original user scene and verification sphere are preserved. The `Slipframe_ArtLibrary` scene organizes individual assets into collections. No manual saving or scene switching is required during MCP authoring.

## Visual direction

- **Ember Run:** chipped basalt, molten cracks, copper restraints, lava channels and a distant forge ring.
- **Summit Step:** irregular gray rock, snow-covered upper facets, alpine cliffs and warm trail markers.
- **Ghost Glass:** fractured translucent obstacles, suspended glass architecture and drifting fragments. No fog is added.
- **Low Crawl:** deep service housings, cooling vanes, overhead ribs and clearly marked duck clearance.
- **Storm Pass:** armored turbine machinery, wind-swept gantries, sparse rain and a slowly turning distant rotor.
- **Crystal Cave:** layered mineral rock, teal/rose/violet crystal growths and gently suspended crystals.

Both portal types use layered mechanical frames, inset luminous channels, fasteners, clamps and separately animated energy accents. Main and choice apertures are real RealityKit portals; choice portals show the destination's three-dimensional environment. The editor's portal-kit render is an asset review, not an in-game screenshot.

Shared track sections, rails, floor inserts, endcaps, the start pad, tokens, crystal halves, charged variants, the merged crystal, wind ribbon, effect shards and modifier glyphs are also authored assets. Six Blender renders supply the biome-selection cards; controls, labels and accessibility remain native SwiftUI.

The obsolete runtime mesh/texture authoring files, `ProceduralGeometry.swift` and `ProceduralTextures.swift`, were removed from the app and Xcode target. Their previous versions remain recoverable from Git.

## Source and runtime files

- `Art/Blender/Slipframe_ArtSource.blend`: editable source, with packed texture images.
- `Art/Blender/Textures/`: six portable baked base-color textures.
- `Endless Runner/ArtAssets/`: self-contained USDZ files plus `manifest.json`.
- `Art/Previews/`: wall lineup, portal kit and six environment review renders.
- `Endless Runner/Assets.xcassets/Biome_*.imageset/`: shipped menu thumbnails.
- `BiomeAssetCatalog.swift`: asynchronous prototype loading, cloning, role-based tinting and motion bindings.
- `GameVisuals.swift` / `GameVisualsObstacles.swift`: assembly and lightweight animation, not mesh-authoring code.

`ArtAssets` is an Xcode folder resource, so new exports retain their names and relative paths in the app bundle. The catalog preloads once before the world attaches. Spawning only clones cached mesh/material resources. Missing obstacles get visible fallback boxes and load failures are logged. Simple runtime planes remain for portal/effect infrastructure and fallbacks.

## Coordinate and gameplay contract

Blender source uses X right, Y forward into the course, Z up. USD export converts to **meters, Y up, forward -Z**. Mesh transforms, including the axis conversion, are baked into vertices and normals. Export removes only the source-library display offset.

- All three wall variants in every biome have a centered **0.70 × 1.80 × 0.70 m** envelope (game X/Y/Z).
- The centered duck hazard is **2.50 × 0.75 × 0.595 m**.
- The centered jump hazard is **2.50 × 0.14 × 0.22 m**.
- Portal masks lie in XY and face +Z, toward the player. Their edges overlap the opaque frame throat slightly to prevent seams.
- AABB collision, lane positions, duck/jump clearance, wind displacement and obstacle scheduling remain independent of art.
- Mesh names follow `assetID__role__materialKey`. Keep `tint_lane`, `tint_rim`, `tint_hot`, `ghost_body`, `ghost_edge`, `tint_pickup`, `tint_glyph`, `motion_rotor` and `motion_float` roles when editing.

## Animation and variation

These USDZ files intentionally contain **static authored geometry**. Swift/RealityKit animates named parts with transforms and opacity: two counter-rotating main-portal accents, choice-portal accents, the distant Storm rotor, floating Ghost/Crystal details, peripheral motes/rain and a short crystal-merge effect. This avoids depending on Blender shader nodes, constraints or simulation caches surviving export.

The rotor's authored pivot is game-space `(0, 4.2, -28)`. If moving it in Blender, update the corresponding `AuthoredMotion` pivot. Rigid portal frames and masks are not independently animated.

`SceneryVariation` has a separate deterministic stream, keyed by run, biome and visit. Natural decorative props use 86–112% overall scale, a small additional height adjustment, up to about 14° yaw and 2.6° lean. Imported bounds are grounded after transformation. All extra scenery remains outside the course; the worst-case inner edge checked against the current asset bounds is **2.00 m from center**, beyond the 1.60 m track edge.

Storm machinery uses much smaller variation; Low Crawl's structural cabinets remain aligned. Walls choose one of three authored variants but never receive random collision-changing scale or rotation. Daily scenery repeats for the same day and visit sequence without consuming the gameplay RNG.

Apple references: [USD entity loading](https://developer.apple.com/documentation/realitykit/entity/init(contentsof:withname:)), [portal worlds](https://developer.apple.com/documentation/realitykit/portalcomponent), [RealityKit transforms](https://developer.apple.com/documentation/realitykit/hastransform), [opacity](https://developer.apple.com/documentation/realitykit/opacitycomponent).

## Editing and exporting

1. Open the saved source and edit an asset's mesh/materials in its named collection. Leave each asset root's origin contract intact; rack positions are display-only.
2. Re-export with `Tools/Blender/export_from_source.py`. It scans existing collections and exports without rebuilding or discarding artist edits.
3. Run `Tools/Blender/validate_assets.py` in Blender's Python.
4. Re-render thumbnails with `Tools/Blender/render_previews.py`.
5. Build and test in Xcode.

Example terminal commands, with `blender` on PATH:

```sh
blender --background Art/Blender/Slipframe_ArtSource.blend --python Tools/Blender/export_from_source.py
blender --background --python Tools/Blender/validate_assets.py
blender --background Art/Blender/Slipframe_ArtSource.blend --python Tools/Blender/render_previews.py
```

`build_slipframe.py` is the initial library authoring script; it refuses to replace an existing library scene. `refine_slipframe.py` recreates the generated wall/scenery/portal collections for this refinement pass: **do not rerun it over subsequent hand edits**. Use `export_from_source.py` for normal artist work.

## Verification and handoff

Validated on Windows with Blender 5.2:

- All 67 packages open, contain their texture dependencies, use aligned uncompressed USDZ members, and have identity transforms / Y-up meter units.
- Mesh points and triangle indices are valid; aperture normals face the player.
- All 18 wall variants and both special hazards preserve their nominal envelopes.
- Decorative variation stays outside the playable corridor at its extreme settings.
- Total library: 139,988 triangles and approximately 22.98 MiB of USDZ packages. This is the whole library, not one frame's draw count.
- Blender review renders were inspected and refined.
- All 35 app/test Swift files passed the syntax-only parser; `git diff --check` passed.

XCTest coverage was added for loading all bundled art, wall bounds, grounding/clearance, repeatable scenery, gameplay RNG independence, fixed turbine pivots, portal-frame stability and rain-loop fading.

**Still requires Mac/Xcode and visionOS validation:** Swift type checking, XCTest execution, actual USDZ material import, main/choice portal clipping and crossing, Ghost transparency, launch latency and on-device frame time. Blender renders are art previews, not proof of device rendering. Test one run in each biome and a three-choice crossing before shipping.
