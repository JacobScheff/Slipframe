# Slipframe app icon

The icon is a bold emblem using the game's real `rift_frame` and the azure body
of its `crystal_combined` Blender mesh. One large faceted crystal sits in front
of a tilted mechanical rift, with sapphire/navy depth and cyan/violet lighting.
The gameplay crystal's small coral inlay and orbit are omitted for clarity.
Icon-only bevels and material tuning give the facets clean studio highlights.
There are no generated illustrations, text, baked sparkles, or pre-applied
circular masks in the shipped artwork.

## visionOS layers

The existing `AppIcon.solidimagestack` remains the build target's app icon.
All three images use one camera and a 1024 × 1024 canvas:

- **Back:** opaque RGB sapphire/navy backdrop with a subtle light falloff.
- **Middle:** transparent RGBA tilted mechanical rift.
- **Front:** transparent RGBA large azure crystal with polished facets.

The operating system supplies circular masking, focus lighting, and layer
parallax. PNG supports the required transparency; the old stack instead had
inconsistent image dimensions (1024 × 1024, 2016 × 1024, and 576 × 576).
The replacement fixes those dimensions and provides coherent separated art.

Apple references:
- [Configuring an icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Layered images in visionOS](https://developer.apple.com/design/human-interface-guidelines/images)

## Rebuild and review

From the repository root, using Blender 5.2 and Python with Pillow:

```sh
blender --background --python Tools/Blender/render_app_icon.py
python Tools/verify_app_icon.py
```

The renderer only reads `Art/Blender/Slipframe_ArtSource.blend`. It writes the
three shipped PNGs, their image-set references, and an editable, self-contained
`Slipframe_AppIcon.blend` here. To reproduce edits, change the render script.
No source game mesh or runtime gameplay asset is modified.

`composite.png`, `preview.png`, and `review.png` are review artifacts only. The
last shows small sizes and illustrative layer offsets; it does not reproduce
the system compositor. The square composite must never replace a shipped layer.

Validation checks image size, layer order, asset references, opacity, transparent
margins, circular safe area, and sample parallax displacements. Final asset-catalog
compilation and actual Home View focus behavior require Xcode and Vision Pro.
