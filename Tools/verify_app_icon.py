"""Validate visionOS icon packaging and create review-only composites.

Requires Pillow. These previews are never referenced by the asset catalog.
"""
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Endless Runner/Assets.xcassets/AppIcon.solidimagestack'
OUT = ROOT / 'Art/AppIcon'
SIZE = 1024


def circle(image):
    mask = Image.new('L', (SIZE, SIZE))
    ImageDraw.Draw(mask).ellipse((0, 0, SIZE - 1, SIZE - 1), fill=255)
    result = image.copy()
    result.putalpha(mask)
    return result


def main():
    stack = json.loads((CATALOG / 'Contents.json').read_text())
    assert [layer['filename'] for layer in stack['layers']] == [
        name + '.solidimagestacklayer' for name in ('Front', 'Middle', 'Back')]
    layers = []
    for name in ('Back', 'Middle', 'Front'):
        directory = CATALOG / (name + '.solidimagestacklayer') / 'Content.imageset'
        entry, = json.loads((directory / 'Contents.json').read_text())['images']
        assert entry['idiom'] == 'vision' and entry['scale'] == '2x'
        assert {p.name for p in directory.glob('*.png')} == {entry['filename']}, 'Unreferenced icon artwork'
        image = Image.open(directory / entry['filename'])
        assert image.size == (SIZE, SIZE), (name, image.size)
        if name == 'Back':
            assert image.mode == 'RGB', 'Background must be completely opaque'
        else:
            assert image.mode == 'RGBA'
            alpha = image.getchannel('A')
            assert alpha.getextrema() == (0, 255)
            bounds = alpha.getbbox()
            assert bounds[0] >= 40 and bounds[1] >= 40
            assert bounds[2] <= SIZE - 40 and bounds[3] <= SIZE - 40
            # Foreground silhouettes stay within the circular mask even under
            # a deliberately generous 24 px review parallax displacement.
            pixels = alpha.load()
            shift = 24 if name == 'Front' else 12
            for y in range(bounds[1], bounds[3]):
                for x in range(bounds[0], bounds[2]):
                    if pixels[x, y] > 16:
                        for direction in (-1, 0, 1):
                            dx = x - 511.5 + direction * shift
                            dy = y - 511.5 - direction * shift / 2
                            assert dx * dx + dy * dy < 512**2, (name, x, y)
        layers.append(image.convert('RGBA'))
        print(name, image.size, image.mode, 'OK')

    def composite(offset=0):
        result = layers[0].copy()
        for index, layer in enumerate(layers[1:], 1):
            result.alpha_composite(layer, (offset * index, -offset * index // 2))
        return result

    OUT.mkdir(parents=True, exist_ok=True)
    composite().convert('RGB').save(OUT / 'composite.png')
    circle(composite()).save(OUT / 'preview.png')
    # Small-size and displaced-layer review, not a simulation of Apple's UI.
    sheet = Image.new('RGB', (1320, 630), '#111b26')
    draw = ImageDraw.Draw(sheet)
    for i, offset in enumerate((-12, 0, 12)):
        icon = circle(composite(offset)).resize((360, 360), Image.Resampling.LANCZOS)
        sheet.paste(icon, (30 + i * 440, 30), icon)
        draw.text((40 + i * 440, 405), ['Left parallax', 'Rest', 'Right parallax'][i], fill='#b8cbd8')
    for x, size in [(50, 64), (190, 128), (430, 192)]:
        icon = circle(composite()).resize((size, size), Image.Resampling.LANCZOS)
        sheet.paste(icon, (x, 435), icon)
        draw.text((x + size + 12, 480), str(size) + ' px', fill='#b8cbd8')
    sheet.save(OUT / 'review.png')
    # Verify foreground movement reveals different background content.
    assert ImageChops.difference(composite(-12), composite(12)).convert('RGB').getbbox()
    print('Circular safe area, transparency, references, and displaced composites OK')


if __name__ == '__main__':
    main()
