"""Page 10 phase 4 (spec mascot.md §J): sticker art from the capybara rig.

    python3 docs/design/mascot/stickers/apply_stickers.py <out-dir>

For every sticker writes <out-dir>/<id>/rig (a patched copy of mascot/capy) and
<out-dir>/<id>/frame.commands (the data values + one screenshot). The patches are
sticker-only shapes (raised forelegs, heart, joy tears, speed lines, confetti) and a 24-unit
margin round each artboard so the white die-cut edge is never clipped. Nothing here goes
into assets/mascot/capy.riv: stickers ship as still images (render.sh + matte.py).
"""
import math, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RIG = os.path.join(HERE, '..', '..', '..', '..', 'mascot', 'capy')
INK, BODY, SHADE, BLUSH, WATER, RIPPLE, YUZU, LEAF = (
    'FF5C3B28', 'FFC6894F', 'FFB27A42', 'FFE8946A', 'FFA9DCD6', 'FF7FC4BC', 'FFEFA00B', 'FF8DB255')
M = 24  # margin (artboard units) for the die-cut edge

def path(pts, closed=False):
    v = ''.join(f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="0"/>' for x, y in pts)
    return f'<PointsPath isClosed="{"true" if closed else "false"}" isClockwise="true" name="Path">{v}</PointsPath>'

def curve(pts):
    """pts: (x, y, rot, dist) with dist 0 = corner."""
    v = ''.join(
        f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="0"/>' if d == 0 else
        f'<CubicMirroredVertex x="{x:.2f}" y="{y:.2f}" rotation="{r:.4f}" distance="{d:.2f}"/>'
        for x, y, r, d in pts)
    return f'<PointsPath isClosed="true" isClockwise="true" name="Path">{v}</PointsPath>'

def stroke(w, c=INK):
    return f'<Stroke thickness="{w}" cap="round" join="round" name="S"><SolidColor colorValue="{c}" name="C"/></Stroke>'

def fill(c):
    return f'<Fill name="F"><SolidColor colorValue="{c}" name="C"/></Fill>'

def shape(name, body, x=0, y=0, rot=0, sc=1):
    return (f'<Shape x="{x}" y="{y}" rotation="{rot}" scaleX="{sc}" scaleY="{sc}" name="{name}">'
            f'{body}</Shape>')

def ellipse(w, h, x=0, y=0, r=0):
    return (f'<Ellipse x="{x:.2f}" y="{y:.2f}" width="{w}" height="{h}" originX="0.5" originY="0.5" '
            f'rotation="{r}" name="Path"/>')

def arm(side, base, paw, core=13, line=22):
    """A raised foreleg, drawn IN FRONT of the body like the feet: a short body-colour stub with the ink
    outline, ending in a small shade-colour paw with two toe ticks across its tip. A body-colour joint at the
    base hides the outline's rounded end, so the leg grows out of the body instead of sitting on it."""
    s = 1 if side == 'R' else -1
    bx, by, px, py = s * base[0], base[1], s * paw[0], paw[1]
    a = math.atan2(py - by, px - bx)
    ux, uy, nx, ny = math.cos(a), math.sin(a), -math.sin(a), math.cos(a)
    tip = [(px + ux * 6 + nx * d, py + uy * 6 + ny * d) for d in (-4, 4)]
    toes = ''.join(path([(x - ux * 4, y - uy * 4), (x + ux * 1, y + uy * 1)]) for x, y in tip)
    leg = path([(bx, by), (px, py)])
    # first child draws in front: toe ticks, paw, core, joint, outline
    return (shape(f'StPawToes{side}', toes + stroke(2.5)) +
            shape(f'StPaw{side}', ellipse(line - 5, line, px + ux * 2, py + uy * 2, round(a, 4)) + fill(SHADE) + stroke(4)) +
            shape(f'StArmCore{side}', leg + stroke(core, BODY)) +
            shape(f'StArmJoint{side}', ellipse(line + 2, line + 2, bx, by) + fill(BODY)) +
            shape(f'StArmLine{side}', leg + stroke(line)))

HEART = curve([(0, -6, 0, 0), (9, -14, 0, 5), (17, -3, 1.5708, 6), (0, 16, 0, 0),
               (-17, -3, -1.5708, 6), (-9, -14, 0, 5)])

def heart(name, x, y, sc):
    return shape(name, HEART + fill(BLUSH) + stroke(4.5), x, y, 0, sc)

TEAR = curve([(0, -9, 0, 0), (6, 3, 1.5708, 3), (0, 9, 3.1416, 2), (-6, 3, -1.5708, 3)])

def tear(name, x, y, rot):
    return shape(name, TEAR + fill(WATER) + stroke(2.5), x, y, rot)

def confetti():
    bits = [(-92, -150, 0.5, YUZU), (-70, -196, -0.4, LEAF), (88, -186, 0.3, BLUSH),
            (98, -132, -0.6, WATER), (-100, -108, 0.2, BLUSH), (66, -214, 0.8, YUZU)]
    return ''.join(shape(f'StConf{i}', f'<Rectangle width="10" height="6" cornerRadiusTL="2" '
                         f'originX="0.5" originY="0.5" name="Path"/>' + fill(c) + stroke(2.5), x, y, r)
                   for i, (x, y, r, c) in enumerate(bits))

def motion(side_x, y0):
    """Two short wave arcs beside a raised paw."""
    return ''.join(shape(f'StWave{i}', path([(side_x + 10 * i, y0 - 8 - 6 * i), (side_x + 14 + 10 * i, y0 - 2 - 6 * i),
                                             (side_x + 12 + 10 * i, y0 + 10 - 6 * i)]) + stroke(3.5)) for i in (0, 1))

SPEED = ''.join(shape(f'StSpeed{i}', path([(x0, y), (x0 + ln, y)]) + stroke(5))
                for i, (x0, y, ln) in enumerate([(100, -150, 18), (106, -110, 22), (100, -70, 16)]))
DUST = ''.join(shape(f'StDust{i}', ellipse(w, w * 0.8) + fill('FFE9D9C4') + stroke(3.5), x, y)
               for i, (x, y, w) in enumerate([(100, -8, 20), (120, -18, 12)]))

GIFT = (shape('StGiftHi', ellipse(8, 5, -6, -5, -0.5) + fill('C8FFFFFF'), 0, -60) +
        shape('StGiftLeaf', curve([(-9, 5, 0, 0), (-3, -5, -0.4229, 3.66), (9, -3, 0, 0), (1, 4, 2.7, 3.2)]) + fill(LEAF) + stroke(3), 12, -79) +
        shape('StGift', ellipse(33, 30) + fill(YUZU) + stroke(5), 0, -60))

HI_ARM = arm('R', (50, -64), (76, -90))                  # hi: one foreleg raised from the side edge
CHEER = arm('R', (50, -70), (76, -100)) + arm('L', (50, -70), (76, -100))  # celebrate: both up from the side edges

# id, artboard, data lines, front-of-Breathe props, hide built-in arms
STICKERS = [
    ('hi', 'Front', ['mood=active'], motion(90, -104) + HI_ARM, True),
    ('lol', 'Front', ['mood=happy'], tear('StTearL', -52, -112, 0.5) + tear('StTearR', 52, -112, -0.5), False),
    ('sorry', 'Front', ['pose=pet', 'mood=worried'], '', False),
    ('love', 'Front', ['pose=pet', 'mood=happy'], heart('StHeart', 0, -60, 1.25) + heart('StHeart2', 78, -170, 0.7), False),
    ('thanks', 'Front', ['pose=pet', 'mood=happy'], GIFT, False),
    ('sleepy', 'Sit', ['mood=sleepy'], '', False),
    ('on-my-way', 'Sit', ['mood=active'], '', False),
    ('chill', 'Onsen', ['mood=chill', 'queued=2'], '', False),
    ('guarding', 'Front', ['pose=guard', 'mood=focused'], '', False),
    ('celebrate', 'Front', ['mood=happy'], confetti() + CHEER, True),
]
PLACE_PROPS = {'on-my-way': SPEED + DUST}  # Sit: under Place, so the hop does not move them

def artboard_span(s, name):
    a = s.index(f'name="{name}"', s.index('<Artboard'))
    a = s.rindex('<Artboard', 0, a)
    return a, s.index('</Artboard>', a)

def patch(src, sid, ab, front, hide):
    s = src
    # margin round every artboard: bigger box, origin moved in by M
    s = re.sub(r'<Artboard ([^>]*?)width="240" height="240"',
               lambda m: f'<Artboard {m.group(1)}width="{240 + 2 * M}" height="{240 + 2 * M}" '
                         f'originX="{M / (240 + 2 * M):.5f}" originY="{M / (240 + 2 * M):.5f}"', s)
    a, b = artboard_span(s, ab)
    part = s[a:b]
    if front:  # first child of Breathe draws in front
        part = re.sub(r'(<Node name="Breathe" id="[^"]+">)', lambda m: m.group(1) + front, part, count=1)
    if hide:
        part = re.sub(r'(name="Arm[LR]Line"[^>]*>\s*<PointsPath.*?<Stroke thickness=")4"',
                      r'\g<1>0"', part, flags=re.S)
    if sid == 'chill':  # the steam squiggles read as '$$' inside the die-cut edge
        part = part.replace('name="Steam"', 'scaleX="0" scaleY="0" name="Steam"', 1)
    if sid in PLACE_PROPS:
        part = re.sub(r'(<Node x="120" y="220" name="Place" id="[^"]+">)',
                      lambda m: m.group(1) + PLACE_PROPS[sid], part, count=1)
    return s[:a] + part + s[b:]

def main(out):
    src = open(os.path.join(RIG, 'scene.rml')).read()
    for sid, ab, data, front, hide in STICKERS:
        d = os.path.join(out, sid)
        shutil.rmtree(d, ignore_errors=True)
        shutil.copytree(RIG, os.path.join(d, 'rig'), ignore=shutil.ignore_patterns('build'))
        open(os.path.join(d, 'rig', 'scene.rml'), 'w').write(patch(src, sid, ab, front, hide))
        hop = ['data hop=1', 'advance 11'] if sid == 'on-my-way' else []
        cmds = [f'artboard {ab}'] + [f'data {x}' for x in data] + ['advance 40'] + hop + [f'screenshot out/{sid}.png']
        open(os.path.join(d, 'frame.commands'), 'w').write('\n'.join(cmds) + '\n')
    print(' '.join(s[0] for s in STICKERS))

if __name__ == '__main__':
    main(sys.argv[1])
