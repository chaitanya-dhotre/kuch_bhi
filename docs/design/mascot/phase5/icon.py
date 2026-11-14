"""Page 10 phase 5 (spec mascot.md §K6): launcher icon options from the Front and Sit views, headless.

    python3 docs/design/mascot/phase5/icon.py <scratch-dir> <out-dir>

Renders Front and Sit (chill) from mascot/capy on white and on black (CLI captures are opaque),
recovers the alpha, and writes for each option an adaptive-icon foreground (108 dp canvas, art inside the
66 dp safe circle), its masked previews (circle, squircle) at launcher sizes on a light and a dark
wallpaper, and the themed (monochrome) look. Writes <out-dir>/icon-options.png and fg-<option>.png.

    python3 docs/design/mascot/phase5/icon.py --ship <scratch-dir> android/app/src/main/res

5b (decision 8 = A, Front on bath teal): writes the adaptive icon into the Android res dir (foreground and
monochrome per density, legacy ic_launcher.png, mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_background in
values/colors.xml) and the AppLogoTile picture (assets/icons/app_logo.png, the launcher's visible 72 dp).
"""
import os, re, shutil, subprocess, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RIG = os.path.join(HERE, '..', '..', '..', '..', 'mascot', 'capy')
RIVE = os.path.expanduser('~/.rive/bin/rive')
PX = 864
FRAMES = {'front': ('Front', 'chill'), 'sit': ('Sit', 'chill')}

def render(tmp):
    for name, col in (('white', 'FFFFFFFF'), ('black', 'FF000000')):
        d = os.path.join(tmp, name)
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(RIG, os.path.join(d, 'rig'), ignore=shutil.ignore_patterns('build'))
        p = os.path.join(d, 'rig', 'scene.rml')
        s = open(p).read()
        bg = (f'<Shape x="120" y="120" name="BG"><Rectangle width="300" height="300" name="R"/>'
              f'<Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill></Shape>\n        ')
        s = re.sub(r'(\n        )(<StateMachine )', lambda m: m.group(1) + bg + m.group(2), s)
        open(p, 'w').write(s)
        cmds = ''.join(f'artboard {a}\ndata mood={m}\nadvance 30\nscreenshot out/{k}.png\n' for k, (a, m) in FRAMES.items())
        open(os.path.join(d, 'f.commands'), 'w').write(cmds)
        os.makedirs(os.path.join(d, 'out'), exist_ok=True)
        subprocess.run([RIVE, 'rig', '--commands=f.commands', f'--viewport={PX}x{PX}', '--fit=contain'],
                       cwd=d, check=True, capture_output=True)

def matte(tmp, k):
    w = Image.open(f'{tmp}/white/out/{k}.png').convert('RGB')
    b = Image.open(f'{tmp}/black/out/{k}.png').convert('RGB')
    a = ImageChops.invert(ImageChops.subtract(w, b).convert('L'))  # alpha = 255 - (white - black)
    out = Image.merge('RGBA', (*b.split(), a))  # colour = black render / alpha (it is premultiplied over black)
    px, ap = out.load(), a.load()
    W, H = out.size
    for y in range(H):
        for x in range(W):
            al = ap[x, y]
            if al and al < 255:
                r, g, bb, _ = px[x, y]
                px[x, y] = (min(255, r * 255 // al), min(255, g * 255 // al), min(255, bb * 255 // al), al)
    return out.crop(out.getchannel('A').point(lambda v: 255 if v > 4 else 0).getbbox())

# Options: (key, frame, background, art's longer side as a share of the 108 dp canvas, nudge x, nudge y)
TEAL, CREAM = (0xA9, 0xDC, 0xD6), (0xFA, 0xF7, 0xF1)
OPTIONS = [
    ('A-front-teal', 'front', TEAL, 0.58, 0.0, 0.0),
    ('B-front-cream', 'front', CREAM, 0.58, 0.0, 0.0),
    ('C-sit-teal', 'sit', TEAL, 0.54, 0.0, 0.0),
    ('D-sit-cream', 'sit', CREAM, 0.54, 0.0, 0.0),
]
INK = (0x5C, 0x3B, 0x28)

def foreground(art, share, nx, ny, size=432):
    """Adaptive foreground: art centred (optically) in a size x size (108 dp) transparent canvas."""
    a = art.copy()
    k = size * share / max(a.width, a.height)
    a = a.resize((int(a.width * k), int(a.height * k)), Image.LANCZOS)
    fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    fg.alpha_composite(a, ((size - a.width) // 2 + int(nx * size), (size - a.height) // 2 + int(ny * size)))
    return fg

def mask(kind, size):
    m = Image.new('L', (size * 4, size * 4), 0)
    d = ImageDraw.Draw(m)
    if kind == 'circle':
        d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    else:  # squircle-ish: big rounded square (Samsung One UI)
        d.rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * 0.3), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def launcher(fg, bg, kind, size):
    """What a launcher shows: the middle 72 of 108 dp, masked."""
    full = Image.new('RGBA', fg.size, bg + (255,))
    full.alpha_composite(fg)
    c = fg.width * 18 // 108
    view = full.crop((c, c, fg.width - c, fg.width - c)).resize((size, size), Image.LANCZOS)
    view.putalpha(mask(kind, size))
    return view

def themed(fg, kind, size, dark):
    """Android 13 themed icon: the monochrome layer is the line art (outline, eyes, nostril: the dark ink
    pixels), shown in one tint on a tinted plate (the launcher picks both from the wallpaper)."""
    plate, tint = ((0x3A, 0x33, 0x2B), (0xF2, 0xD9, 0xB8)) if dark else ((0xF3, 0xE3, 0xCC), (0x5C, 0x3B, 0x28))
    return launcher(mono_layer(fg, tint), plate, kind, size)

def mono_layer(fg, tint=(255, 255, 255)):
    """The line art (dark ink pixels) as alpha; Android uses only the alpha of a monochrome layer."""
    ink = fg.convert('RGB').convert('L').point(lambda v: 255 if v < 110 else 0)
    mono = Image.new('RGBA', fg.size, tint + (0,))
    mono.putalpha(ImageChops.multiply(fg.getchannel('A'), ink))
    return mono

DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
ADAPTIVE = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by docs/design/mascot/phase5/icon.py in ship mode (mascot.md K6, option A). -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""

def ship(tmp, res):
    key, frame, bg, share, nx, ny = OPTIONS[0]  # A, Front on bath teal
    render(tmp)
    art = matte(tmp, frame)
    fg_big = foreground(art, share, nx, ny, 648)  # the asset crops 432 px out of this
    assert max(art.size) >= share * 648, f'render {max(art.size)} px is smaller than the biggest output; raise PX'
    mono_big = mono_layer(fg_big)  # threshold the ink at full size, then scale (thin lines survive mdpi)
    for d, k in DENSITIES.items():
        out = os.path.join(res, f'mipmap-{d}')
        os.makedirs(out, exist_ok=True)
        fg = foreground(art, share, nx, ny, round(108 * k))
        fg.save(f'{out}/ic_launcher_foreground.png', optimize=True)
        mono_big.resize(fg.size, Image.LANCZOS).save(f'{out}/ic_launcher_monochrome.png', optimize=True)
        launcher(fg_big, bg, 'squircle', round(48 * k)).save(f'{out}/ic_launcher.png', optimize=True)
    os.makedirs(os.path.join(res, 'mipmap-anydpi-v26'), exist_ok=True)
    open(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w').write(ADAPTIVE)
    p = os.path.join(res, 'values', 'colors.xml')
    s = open(p).read()
    line = '<color name="ic_launcher_background">#%02X%02X%02X</color>' % bg
    s = (re.sub(r'<color name="ic_launcher_background">[^<]*</color>', line, s) if 'ic_launcher_background' in s
         else s.replace('</resources>', f'    <!-- Launcher icon plate: bath teal (mascot.md K6) -->\n    {line}\n</resources>'))
    open(p, 'w').write(s)
    c = 648 * 18 // 108  # AppLogoTile shows what the launcher shows: the middle 72 of 108 dp
    asset = os.path.join(HERE, '..', '..', '..', '..', 'assets', 'icons', 'app_logo.png')
    fg_big.crop((c, c, 648 - c, 648 - c)).save(asset, optimize=True)
    print(res, os.path.normpath(asset))

def main(tmp, out):
    os.makedirs(out, exist_ok=True)
    render(tmp)
    arts = {k: matte(tmp, k) for k in FRAMES}
    cell, pad = 150, 18
    cols = ['design', 'circle 128', 'squircle 128', 'circle 64', 'squircle 48', 'themed light', 'themed dark']
    W = pad + len(cols) * (cell + pad)
    sheet = Image.new('RGB', (W, pad + len(OPTIONS) * 2 * (cell + pad)), (255, 255, 255))
    for r, (key, frame, bg, share, nx, ny) in enumerate(OPTIONS):
        fg = foreground(arts[frame], share, nx, ny)
        fg.save(f'{out}/fg-{key}.png')
        for half, wall in enumerate(((0xE8, 0xE4, 0xDC), (0x20, 0x22, 0x26))):
            y = pad + (2 * r + half) * (cell + pad)
            row = Image.new('RGB', (W, cell + pad), wall)
            sheet.paste(row, (0, y - pad // 2))
            design = Image.new('RGBA', fg.size, bg + (255,))
            design.alpha_composite(fg)
            d = ImageDraw.Draw(design)
            c = fg.width // 2
            rr = fg.width * 33 // 108
            d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=(220, 40, 40, 255), width=2)  # 66 dp safe zone
            tiles = [design.resize((cell, cell), Image.LANCZOS),
                     launcher(fg, bg, 'circle', 128), launcher(fg, bg, 'squircle', 128),
                     launcher(fg, bg, 'circle', 64), launcher(fg, bg, 'squircle', 48),
                     themed(fg, 'circle', 96, False), themed(fg, 'circle', 96, True)]
            for i, t in enumerate(tiles):
                x = pad + i * (cell + pad) + (cell - t.width) // 2
                sheet.paste(t, (x, y + (cell - t.height) // 2), t if t.mode == 'RGBA' else None)
    sheet.save(f'{out}/icon-options.png')
    print(f'{out}/icon-options.png')

if __name__ == '__main__':
    if sys.argv[1] == '--ship':
        ship(sys.argv[2], sys.argv[3])
    else:
        main(sys.argv[1], sys.argv[2])
