# Slipframe — Blender asset pipeline

The game now uses **77 authored USDZ assets** instead of building its artwork from Swift primitives. The editable source is `Art/Blender/Slipframe_ArtSource.blend`; the original user scene and verification sphere are preserved. The `Slipframe_ArtLibrary` scene organizes individual assets into collections. No manual saving or scene switching is required during MCP authoring.

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

Five biomes now have three decorative prop silhouettes each (the original plus `_1` and `_2`). Seeded shuffled groups use every silhouette without adjacent duplicates, including at group boundaries. The two sides are staggered in depth instead of forming matching rows. New variants fit inside the original prop bounds, preserving the existing clearance limits. Low Crawl keeps its aligned original cabinetry.

## Background visibility and depth pass

The September 21 recording exposed unreadable rock faces under the portal's isolated lighting. Background meshes now use private copies of their materials with four directional emission levels, with stronger warm/cool separation for Summit. This fill travels through USD Preview Surface without adding runtime lights or changing shared portal/obstacle materials.

All six environments replace their flat backdrop boxes with inward-facing, opaque sky domes with baked gradients. Three separated skyline layers, continued roads that blend into the terrain, and distant biome structures hide the old 27 m stage ending. No translucent fog is used. Source environment racks are spaced 350 m apart to keep their sky domes separate.

`refine_backgrounds.py` incrementally applies this pass once, preserving existing scene art except the backdrop boxes. Its guard prevents accidental reapplication. `refresh_distance()` rebuilds only the horizon/road additions, and `export()` updates only background/prop packages and their manifest records. Portal assets, hazard assets, collision, and teleportation logic are unchanged.

`render_backgrounds.py` makes emission-only EEVEE reviews with no physical lights or environment fill and updates the six menu cards. The new `*-background.png` previews are the current background reviews; the older lit studio renders remain as historical art references. These reviews still do not replace RealityKit/on-device validation.

The second pass, `polish_backgrounds.py`, adds uneven cliff profiles, snow ledges, rubble, smaller distant sunlight, trail cables/pennants, forge vents, glass fragments, service panels, wind vanes, and mineral seams. New low scenery stays beyond 1.85 m from center. Existing animated rotor geometry and its pivot remain untouched.

Background surface detail uses small baked linear-emission textures to retain the first pass's visibility under isolated portal lighting. They must export as USD UV textures with `sourceColorSpace = raw`; treating these linear values as sRGB would darken the rocks. The package validator checks this contract. The second-pass script is guarded against accidental reapplication; `surface_relief(force=True)` refreshes only its own textures when tuning the art.

### Player-distance correction

`refine_portal_composition.py` restores the ten deformed original rock/mineral meshes exactly from the committed `b4933e4` source, retaining their visibility materials. It removes the added floating-looking Summit shelves and adds grounded, substantial snow-capped buttresses, basalt formations, crystal clusters, glass pillars, turbine supports and service cabinets. These additions sit outside the 1.85 m corridor and are composed for the restricted main-portal sightline, not a free-orbit camera. The original large structures, gameplay code, animated turbine pivot and portal/teleportation assets are preserved. This one-time correction is guarded; normal edits should use the saved source.

The apparent disappearance of original cliffs in the library was also traced to **Local View**: old meshes were excluded while new additions were included. Local View is now disabled, and creating a review scene exits it to prevent partial assemblies. A recoverable pre-correction source copy is retained as `Art/Blender/Slipframe_ArtSource.blend20260921-pre-portal-composition`.

`render_portal_reviews.py` uses the actual authored elliptical opening (1.84 m horizontal / 1.28 m vertical radii), an opaque review-only surround, and portal-plane clipping of disposable review meshes. It renders all six environments at the default 8 m distance, plus Summit at 3.5 and 10 m and small lateral/height offsets. First-hit ray checks verify that original structures and new landmarks are visible at 8 m and at 10 m with centered and ±0.6 m lateral positions, rather than merely lying inside a theoretical cone. Review masks and clipped copies are never exported. These checks verify geometry/composition, not RealityKit lighting or headset performance.

The saved Blender file opens in `PortalReview_summitStep_8m`; select another `PortalReview_<biome>_8m` scene in the top-right scene selector to review it. `Slipframe_ArtLibrary` remains the editable source; review geometry is disposable. Current clipped previews are `Art/Previews/<biome>-portal-8m.png`. Generate them with `blender --background Art/Blender/Slipframe_ArtSource.blend --python Tools/Blender/render_portal_reviews.py`.

Apple references: [USD entity loading](https://developer.apple.com/documentation/realitykit/entity/init(contentsof:withname:)), [portal worlds](https://developer.apple.com/documentation/realitykit/portalcomponent), [RealityKit transforms](https://developer.apple.com/documentation/realitykit/hastransform), [opacity](https://developer.apple.com/documentation/realitykit/opacitycomponent).

## Editing and exporting

`vary_game_objects.py` is a guarded one-time pass that replaces wall variants 1/2 with distinct front assemblies and adds two variants each for duck gates, jump gates, tokens and all four crystal-half states. Spawn selection hashes the separate cosmetic seed; all authored wall/hazard bounds remain exact, and pickup variants retain the original asset envelope. The runtime preload list explicitly enumerates all 91 packages (never random selection during enumeration). `render_object_variations.py` renders the actual source variants side by side and creates the `ObjectVariationReview` scene.

Ghost Glass walls, props and elevated scenery now use near-invisible materials: ordinary bodies at 0.012 opacity, spectral walls at 0.004 at runtime, and faint edges no higher than 0.035. The floor and sky retain their existing appearance. Runtime handling applies transparent PBR materials to all ghost wall/prop parts and does not overwrite the edges with opaque unlit materials. The exporter explicitly preserves `SF_NearInvisible_*` opacity in USD Preview Surface because the tested Blender 5.2 exporter otherwise wrote opacity 1 for the blended material. Package validation checks the resulting opacity and ghost material bindings. This is a Blender/USD check; final RealityKit rendering still needs device verification.

The source before this pass is recoverable from `Art/Blender/Slipframe_ArtSource.blend20260921-pre-object-variants`.

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

- All 91 packages open, contain their texture dependencies, use aligned uncompressed USDZ members, and have identity transforms / Y-up meter units.
- Mesh points and triangle indices are valid; aperture normals face the player.
- All 18 wall variants and both special hazards preserve their nominal envelopes.
- Decorative variation stays outside the playable corridor at its extreme settings.
- Total library after the object-variation pass: 170,237 triangles and approximately 31.99 MiB of USDZ packages. Each environment remains below 25,000 triangles (15,629–23,592). This is the whole library, not one frame's draw count.
- Blender review renders were inspected and refined.
- All 35 app/test Swift files passed the syntax-only parser; `git diff --check` passed.

XCTest coverage was added for loading all bundled art, wall bounds, grounding/clearance, repeatable scenery, gameplay RNG independence, fixed turbine pivots, portal-frame stability and rain-loop fading.

**Still requires Mac/Xcode and visionOS validation:** Swift type checking, XCTest execution, actual USDZ material import, main/choice portal clipping and crossing, Ghost transparency, launch latency and on-device frame time. Blender renders are art previews, not proof of device rendering. Test one run in each biome and a three-choice crossing before shipping.
