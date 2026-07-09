from pathlib import Path
from PIL import Image, ImageDraw

from font_edit import export_font
from schemas import ExportRequest, GlyphPatch, GlobalAdjustment, ColorSettings, ColorMode, TargetScope


def main():
    here = Path(__file__).resolve().parent
    candidates = [
        Path('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
        Path('/System/Library/Fonts/Supplemental/Arial.ttf'),
        Path('/Library/Fonts/Arial Unicode.ttf'),
        Path('/usr/share/fonts/fonts-go/Go-Mono.ttf'),
        Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
    ]
    font = next((p for p in candidates if p.exists()), None)
    if font is None:
        raise SystemExit('No test font found. Put any .ttf next to this script and edit smoke_test.py.')

    image_path = here / 'A_test_patch.png'
    img = Image.new('RGBA', (200, 200), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((20, 20, 180, 180), fill=(232, 131, 107, 255))
    draw.text((78, 82), 'A', fill=(255, 255, 255, 255))
    img.save(image_path)

    req = ExportRequest(
        output_family_name='FontGlyphEditorSmokeTest',
        adjustment=GlobalAdjustment(tracking=20),
        color=ColorSettings(mode=ColorMode.solid, scope=TargetScope.selected, selected_chars='B', solid_hex='#3366FF'),
        patches=[GlyphPatch(character='A', image_filename=image_path.name, scale=1.0)]
    )
    out = here / 'FontGlyphEditorSmokeTest.ttf'
    result = export_font(font, out, req, {image_path.name: image_path})
    print(result)
    print(f'Wrote: {out}')


if __name__ == '__main__':
    main()
