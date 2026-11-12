# matte.py <renderdir> <outdir> [halo_px] (render.sh runs it): recover alpha from white/black renders, add a white die-cut halo,
# write transparent PNGs + a contact sheet on the app's light and dark chat backgrounds.
import sys, os
from PIL import Image, ImageChops, ImageFilter
src, out = sys.argv[1], sys.argv[2]; halo = int(sys.argv[3]) if len(sys.argv) > 3 else 0
os.makedirs(out, exist_ok=True)
names = sorted(f for f in os.listdir(f'{src}/white/out') if f.endswith('.png'))
tiles = []
for n in names:
    w = Image.open(f'{src}/white/out/{n}').convert('RGB'); b = Image.open(f'{src}/black/out/{n}').convert('RGB')
    wp, bp = w.load(), b.load(); W, H = w.size
    img = Image.new('RGBA', (W, H)); p = img.load()
    for y in range(H):
        for x in range(W):
            wr, wg, wb = wp[x, y]; br, bg_, bb = bp[x, y]
            a = 255 - max(0, min(255, ((wr - br) + (wg - bg_) + (wb - bb)) // 3))
            if a == 0: p[x, y] = (0, 0, 0, 0); continue
            p[x, y] = (min(255, br * 255 // a), min(255, bg_ * 255 // a), min(255, bb * 255 // a), a)
    if halo:
        al = img.getchannel('A').point(lambda v: 255 if v > 8 else 0).filter(ImageFilter.MaxFilter(2 * halo + 1)).filter(ImageFilter.GaussianBlur(1))
        base = Image.new('RGBA', img.size, (255, 255, 255, 0)); base.putalpha(al)
        img = Image.alpha_composite(base, img)
    bbox = img.getchannel('A').point(lambda v: 255 if v > 4 else 0).getbbox()
    img.save(f'{out}/{n}'); tiles.append((n, img, bbox))
# contact sheet: 2 rows (light FAF7F1, dark 171512)
T = 200; pad = 12
sheet = Image.new('RGB', (len(tiles) * (T + pad) + pad, 2 * (T + pad) + pad), (255, 255, 255))
for r, col in enumerate([(0xFA, 0xF7, 0xF1), (0x17, 0x15, 0x12)]):
    for i, (n, img, _) in enumerate(tiles):
        bgc = Image.new('RGBA', (T, T), col + (255,))
        bgc.alpha_composite(img.resize((T, T), Image.LANCZOS))
        sheet.paste(bgc.convert('RGB'), (pad + i * (T + pad), pad + r * (T + pad)))
sheet.save(f'{out}/_sheet.png')
for n, img, bb in tiles: print(n, bb)
