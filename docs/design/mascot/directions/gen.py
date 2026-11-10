"""Drafting tool for Page 10 Phase 1: writes each capybara direction as RML.

The RML it writes is the art (opens in the Rive editor, builds with the CLI).
After the user picks a direction, that direction's scene.rml becomes the
hand-edited source of truth and this script is retired for it.

Usage: python3 gen.py [--bg AARRGGBB] [outdir]   (bg is for headless renders only)
"""
import math
import os
import sys

# Mascot palette (foundation §2) + yuzu/leaf.
BODY, SHADE, SNOUT, NOSTRIL, FACE = "C6894F", "B27A42", "8B5E3E", "5C3B28", "3A2E22"
BODY_HI, BODY_LO = "D9A066", "A86F3B"
YUZU_HI, YUZU, YUZU_LO = "FFD36E", "EFA00B", "D68406"
LEAF_HI, LEAF_LO = "8DB255", "5E8A3A"
WHITE = "FFFFFF"
BLUSH = "E8946A"


def _col(c, a=255):
    return c if len(c) == 8 else f"{a:02X}{c}"


class Doc:
    def __init__(self):
        self.next_id = 100
        self.out = []

    def nid(self):
        self.next_id += 1
        return f"0:{self.next_id}"


def paint_xml(p, ox=0.0, oy=0.0):
    """ox/oy: shape position; gradients on primitives are in shape-local space."""
    kind = p[0]
    if kind == "solid":
        a = p[2] if len(p) > 2 else 255
        return f'<Fill name="F"><SolidColor colorValue="{_col(p[1], a)}" name="C"/></Fill>'
    if kind in ("lin", "rad"):
        tag = "LinearGradient" if kind == "lin" else "RadialGradient"
        x1, y1, x2, y2, stops = p[1:6]
        if len(p) > 6 and p[6] == "abs":
            x1, y1, x2, y2 = x1 - ox, y1 - oy, x2 - ox, y2 - oy
        s = "".join(f'<GradientStop colorValue="{_col(c)}" position="{pos}"/>' for pos, c in stops)
        return (f'<Fill name="F"><{tag} startX="{x1:.1f}" startY="{y1:.1f}" endX="{x2:.1f}" '
                f'endY="{y2:.1f}" name="G">{s}</{tag}></Fill>')
    if kind == "stroke":
        th, c, cap = p[1], p[2], (p[3] if len(p) > 3 else "round")
        return (f'<Stroke thickness="{th}" cap="{cap}" join="round" name="S">'
                f'<SolidColor colorValue="{_col(c)}" name="C"/></Stroke>')
    raise ValueError(kind)


def path_xml(pts, closed=True):
    """pts: (x, y) smooth, (x, y, 'c', radius) corner, (x, y, 's', tension) smooth."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    vs = []
    for i, p in enumerate(pts):
        x, y = p[0], p[1]
        kind = p[2] if len(p) > 2 else "s"
        if kind == "c" or (not closed and i in (0, n - 1)):
            r = p[3] if kind == "c" else 0
            vs.append(f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="{r}"/>')
            continue
        t = p[3] if len(p) > 3 else 1.0
        a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]
        rot = math.atan2(dy, dx)
        dist = math.hypot(dx, dy) / 6 * t
        vs.append(f'<CubicMirroredVertex x="{x:.2f}" y="{y:.2f}" rotation="{rot:.4f}" distance="{dist:.2f}"/>')
    cw = "true" if area > 0 else "false"
    return f'<PointsPath isClosed="{str(closed).lower()}" isClockwise="{cw}" name="Path">{"".join(vs)}</PointsPath>'


def shape(doc, name, geom, paints, rot=0.0, opacity=1.0, clip=None):
    """geom: ('path', pts[, closed]) | ('ell', cx, cy, w, h) | ('rect', cx, cy, w, h, r)."""
    sid = doc.nid()
    if geom[0] == "path":
        x = y = 0
        g = path_xml(geom[1], geom[2] if len(geom) > 2 else True)
    elif geom[0] == "ell":
        _, x, y, w, h = geom
        g = f'<Ellipse width="{w}" height="{h}" originX="0.5" originY="0.5" name="Path"/>'
    else:
        _, x, y, w, h, r = geom
        g = f'<Rectangle width="{w}" height="{h}" cornerRadiusTL="{r}" originX="0.5" originY="0.5" name="Path"/>'
    extra = f' rotation="{rot:.4f}"' if rot else ""
    extra += f' opacity="{opacity}"' if opacity != 1.0 else ""
    c = f'<ClippingShape sourceId="{clip}" name="Clip"/>' if clip else ""
    return sid, f'<Shape x="{x:.2f}" y="{y:.2f}"{extra} name="{name}" id="{sid}">{g}{"".join(paint_xml(p, x, y) for p in paints)}{c}</Shape>'


def artboard(doc, name, layers, bg=None, size=240, stage_x=0):
    """layers: back-to-front list of (name, geom, paints, kwargs). RML paints first-declared on top."""
    aid, sty = doc.nid(), doc.nid()
    ids, xml = {}, []
    if bg:
        xml.append(shape(doc, "BG", ("rect", size / 2, size / 2, size, size, 0), [("solid", bg[2:], int(bg[:2], 16))])[1])
    # clip sources must exist before reference: assign ids first
    for lname, geom, paints, kw in layers:
        kw = dict(kw)
        if "clip" in kw:
            kw["clip"] = ids[kw["clip"]]
        sid, s = shape(doc, lname, geom, paints, **kw)
        ids[lname] = sid
        xml.append(s)
    body = "\n        ".join(reversed(xml))
    return (f'<Artboard x="{stage_x}" y="0" width="{size}" height="{size}" styleId="{sty}" name="{name}" id="{aid}">\n'
            f'        <LayoutComponentStyle name="Artboard Style" id="{sty}"/>\n        {body}\n    </Artboard>')


def L(name, geom, paints, **kw):
    return (name, geom, paints, kw)


# ---------- shared pieces ----------

def yuzu(cx, cy, r, leaf_side=1, tilt=0.0):
    """Marigold yuzu with a leaf; r = radius. leaf_side 1 = leaf to the right."""
    lx, ly = cx + leaf_side * r * 0.35, cy - r * 0.95
    leaf = [(lx, ly, "c", 0), (lx + leaf_side * r * 0.55, ly - r * 0.62), (lx + leaf_side * r * 1.25, ly - r * 0.55, "c", 0),
            (lx + leaf_side * r * 0.75, ly - r * 0.05)]
    return [
        L("YuzuShadow", ("ell", cx, cy + r * 0.88, r * 1.5, r * 0.38), [("solid", "000000", 40)]),
        L("Yuzu", ("ell", cx, cy, r * 2.08, r * 1.92), [("rad", -r * 0.45, -r * 0.5, r * 0.75, r * 0.95,
                                                       [(0, YUZU_HI), (0.55, YUZU), (1, YUZU_LO)])], rot=tilt),
        L("YuzuDimple", ("ell", lx - leaf_side * r * 0.12, ly + r * 0.1, r * 0.3, r * 0.2), [("solid", YUZU_LO)]),
        L("Leaf", ("path", leaf), [("lin", lx, ly, lx + leaf_side * r * 1.2, ly - r * 0.6, [(0, LEAF_LO), (1, LEAF_HI)])]),
    ]


def ground(cx, y, w):
    return L("Shadow", ("ell", cx, y, w, w * 0.11), [("solid", FACE, 40)])


def body_grad(top, bottom):
    return ("lin", 0, top, 0, bottom, [(0, BODY_HI), (0.45, BODY), (1, BODY_LO)], "abs")


# ---------- Direction A: Loaf (anatomical, calm half-lids) ----------

def a_side():
    sil = [(30, 106, "c", 22), (62, 86), (108, 74), (160, 78), (200, 94), (216, 132),
           (206, 172), (178, 188), (112, 190), (68, 182), (32, 172, "c", 22)]
    snout = [(14, 50, "c", 0), (86, 50, "c", 0), (86, 192, "c", 0), (14, 192, "c", 0)]
    return [
        ground(124, 202, 190),
        L("LegFarBack", ("rect", 186, 190, 24, 26, 10), [("solid", BODY_LO)]),
        L("LegFarFront", ("rect", 96, 192, 22, 24, 10), [("solid", BODY_LO)]),
        L("Body", ("path", sil), [body_grad(76, 192)]),
        L("Snout", ("path", snout), [("lin", 24, 0, 84, 0, [(0, "FF" + SNOUT), (0.55, "E6" + SNOUT), (1, "00" + SNOUT)])], clip="Body"),
        L("LegBack", ("rect", 170, 194, 26, 22, 10), [("solid", SHADE)]),
        L("LegFront", ("rect", 76, 194, 24, 22, 10), [("solid", SHADE)]),
        L("Ear", ("ell", 128, 80, 22, 18), [("solid", SHADE)], rot=-0.4),
        L("EarInner", ("ell", 129, 82, 11, 9), [("solid", SNOUT)], rot=-0.4),
        L("Eye", ("path", [(82, 103, "c", 1), (106, 103, "c", 1), (103, 113), (94, 117), (85, 113)]), [("solid", FACE)]),
        L("Lid", ("path", [(79, 103), (94, 99), (109, 103)], False), [("stroke", 3.4, SNOUT)]),
        L("Nostril", ("ell", 40, 114, 10, 5), [("solid", NOSTRIL)], rot=-0.5),
        L("Mouth", ("path", [(34, 160), (42, 164), (50, 159)], False), [("stroke", 2.6, NOSTRIL)]),
        L("Cheek", ("ell", 98, 140, 26, 14), [("solid", BODY_HI, 110)]),
        *yuzu(104, 58, 17, 1, 0.1),
    ]


def a_tq():
    body = [(100, 96), (160, 84), (206, 102), (220, 144), (204, 182), (150, 194), (106, 188)]
    head = [(66, 58), (110, 54), (136, 76), (140, 116), (126, 150), (96, 170), (54, 172), (30, 150, "s", 0.8), (32, 100)]
    return [
        ground(126, 204, 200),
        L("LegFarBack", ("rect", 198, 190, 22, 24, 10), [("solid", BODY_LO)]),
        L("Body", ("path", body), [body_grad(84, 194)]),
        L("LegBack", ("rect", 172, 194, 26, 22, 10), [("solid", SHADE)]),
        L("EarFar", ("ell", 58, 62, 18, 16), [("solid", SHADE)], rot=0.5),
        L("EarNear", ("ell", 126, 64, 22, 18), [("solid", SHADE)], rot=-0.4),
        L("EarNearInner", ("ell", 126, 66, 11, 9), [("solid", SNOUT)], rot=-0.4),
        L("LegFront", ("rect", 84, 192, 28, 28, 12), [("solid", SHADE)]),
        L("LegFront2", ("rect", 118, 194, 26, 24, 11), [("solid", SHADE)]),
        L("Head", ("path", head), [body_grad(54, 172)]),
        L("Snout", ("ell", 58, 140, 104, 84), [("rad", 0, 0, 52, 0, [(0, "FF" + SNOUT), (0.6, "F0" + SNOUT), (1, "00" + SNOUT)])], clip="Head"),
        L("EyeFar", ("path", [(43, 94, "c", 1), (58, 94, "c", 1), (56, 102), (50, 105), (45, 101)]), [("solid", FACE)]),
        L("EyeNear", ("path", [(88, 92, "c", 1), (112, 92, "c", 1), (109, 102), (100, 106), (91, 102)]), [("solid", FACE)]),
        L("LidFar", ("path", [(42, 94), (50, 91), (59, 94)], False), [("stroke", 3, SNOUT)]),
        L("LidNear", ("path", [(87, 92), (100, 89), (113, 92)], False), [("stroke", 3, SNOUT)]),
        L("NostrilFar", ("ell", 40, 122, 7, 5), [("solid", NOSTRIL)], rot=0.4),
        L("NostrilNear", ("ell", 64, 124, 9, 5), [("solid", NOSTRIL)], rot=-0.3),
        L("Mouth", ("path", [(42, 156), (52, 160), (62, 156)], False), [("stroke", 2.6, NOSTRIL)]),
        L("Cheek", ("ell", 112, 130, 22, 12), [("solid", BODY_HI, 110)]),
        *yuzu(88, 42, 17, 1, 0.1),
    ]


# ---------- Direction B: Chibi (big head, glossy eyes, blush) ----------

def b_side():
    head = [(46, 80), (92, 50), (148, 58), (170, 96), (160, 140), (118, 160), (70, 156), (40, 130)]
    snout = [(14, 92, "c", 26), (80, 92, "c", 26), (80, 156, "c", 26), (14, 156, "c", 26)]
    body = [(120, 126), (168, 112), (206, 132), (208, 172), (176, 194), (128, 192), (106, 168)]
    return [
        ground(130, 204, 170),
        L("LegFarBack", ("rect", 188, 192, 20, 20, 9), [("solid", BODY_LO)]),
        L("Body", ("path", body), [body_grad(112, 194)]),
        L("LegBack", ("rect", 170, 196, 22, 18, 9), [("solid", SHADE)]),
        L("LegFront", ("rect", 124, 196, 22, 18, 9), [("solid", SHADE)]),
        L("Ear", ("ell", 142, 56, 26, 22), [("solid", SHADE)], rot=-0.5),
        L("EarInner", ("ell", 142, 58, 13, 11), [("solid", SNOUT)], rot=-0.5),
        L("Head", ("path", head), [body_grad(50, 160)]),
        L("Snout", ("path", snout), [("lin", 0, 92, 0, 156, [(0, "9C6B46"), (1, SNOUT)])]),
        L("SnoutHi", ("ell", 40, 104, 30, 10), [("solid", WHITE, 40)]),
        L("Nostril", ("ell", 26, 112, 8, 11), [("solid", NOSTRIL)], rot=0.2),
        L("Mouth", ("path", [(30, 138), (40, 144), (52, 139)], False), [("stroke", 3, NOSTRIL)]),
        L("Blush", ("ell", 112, 128, 24, 13), [("solid", BLUSH, 150)]),
        L("Eye", ("ell", 106, 96, 20, 23), [("solid", FACE)]),
        L("EyeGlint", ("ell", 110, 90, 8, 8), [("solid", WHITE)]),
        L("EyeGlint2", ("ell", 102, 102, 4, 4), [("solid", WHITE, 200)]),
        *yuzu(104, 38, 19, 1, 0.12),
    ]


def b_tq():
    head = [(112, 46), (162, 64), (182, 108), (172, 150), (128, 170), (76, 166), (40, 136), (42, 88), (70, 56)]
    snout = [(30, 114, "c", 28), (122, 114, "c", 28), (122, 172, "c", 26), (30, 172, "c", 26)]
    body = [(100, 150), (160, 140), (196, 162), (192, 194), (140, 202), (92, 196)]
    return [
        ground(120, 206, 172),
        L("Body", ("path", body), [body_grad(140, 202)]),
        L("LegBack", ("rect", 176, 198, 22, 16, 8), [("solid", SHADE)]),
        L("EarL", ("ell", 64, 60, 22, 20), [("solid", SHADE)], rot=0.5),
        L("EarR", ("ell", 160, 62, 26, 22), [("solid", SHADE)], rot=-0.5),
        L("EarRInner", ("ell", 160, 64, 13, 11), [("solid", SNOUT)], rot=-0.5),
        L("Head", ("path", head), [body_grad(46, 170)]),
        L("LegL", ("rect", 84, 200, 24, 16, 8), [("solid", SHADE)]),
        L("LegR", ("rect", 132, 202, 24, 16, 8), [("solid", SHADE)]),
        L("Snout", ("path", snout), [("lin", 0, 114, 0, 172, [(0, "9C6B46"), (1, SNOUT)])]),
        L("SnoutHi", ("ell", 70, 124, 52, 10), [("solid", WHITE, 40)]),
        L("NostrilL", ("ell", 52, 132, 7, 10), [("solid", NOSTRIL)], rot=0.3),
        L("NostrilR", ("ell", 86, 130, 8, 11), [("solid", NOSTRIL)], rot=-0.2),
        L("Mouth", ("path", [(58, 156), (70, 162), (84, 156)], False), [("stroke", 3, NOSTRIL)]),
        L("BlushL", ("ell", 42, 110, 14, 10), [("solid", BLUSH, 150)]),
        L("BlushR", ("ell", 156, 116, 24, 13), [("solid", BLUSH, 150)]),
        L("EyeL", ("ell", 66, 92, 15, 19), [("solid", FACE)]),
        L("EyeR", ("ell", 126, 90, 21, 24), [("solid", FACE)]),
        L("GlintL", ("ell", 69, 86, 6, 6), [("solid", WHITE)]),
        L("GlintR", ("ell", 130, 84, 8, 8), [("solid", WHITE)]),
        L("GlintR2", ("ell", 122, 97, 4, 4), [("solid", WHITE, 200)]),
        *yuzu(110, 30, 19, 1, 0.12),
    ]


# ---------- Direction C: Sentinel (sits upright, guardian pose, square silhouette) ----------

def c_side():
    body = [(76, 100), (130, 84), (180, 104), (214, 152), (208, 194), (150, 204, "s", 0.8),
            (96, 200), (72, 164), (68, 126)]
    head = [(30, 74, "c", 20), (80, 50), (130, 56), (146, 88), (126, 118), (74, 120), (34, 112, "c", 18)]
    snout = [(14, 40, "c", 0), (84, 40, "c", 0), (84, 130, "c", 0), (14, 130, "c", 0)]
    return [
        ground(146, 206, 150),
        L("LegFar", ("rect", 120, 188, 22, 36, 11), [("solid", BODY_LO)]),
        L("Body", ("path", body), [body_grad(86, 204)]),
        L("ThighLine", ("path", [(146, 196), (150, 160), (172, 136), (196, 140)], False), [("stroke", 3, "80" + BODY_LO)]),
        L("Foot", ("rect", 176, 202, 40, 12, 6), [("solid", SHADE)]),
        L("LegNear", ("rect", 96, 182, 24, 46, 12), [("lin", 0, -23, 0, 23, [(0, BODY), (1, SHADE)])]),
        L("Ear", ("ell", 128, 58, 22, 18), [("solid", SHADE)], rot=-0.4),
        L("EarInner", ("ell", 129, 60, 11, 9), [("solid", SNOUT)], rot=-0.4),
        L("Head", ("path", head), [body_grad(50, 120)]),
        L("Snout", ("path", snout), [("lin", 20, 0, 82, 0, [(0, "FF" + SNOUT), (0.55, "E6" + SNOUT), (1, "00" + SNOUT)])], clip="Head"),
        L("Eye", ("ell", 98, 78, 12, 13), [("solid", FACE)]),
        L("EyeGlint", ("ell", 100, 75, 4, 4), [("solid", WHITE)]),
        L("Nostril", ("ell", 38, 80, 10, 5), [("solid", NOSTRIL)], rot=-0.5),
        L("Mouth", ("path", [(34, 106), (42, 110), (50, 105)], False), [("stroke", 2.6, NOSTRIL)]),
        *yuzu(92, 34, 17, 1, 0.1),
    ]


def c_tq():
    body = [(92, 104), (150, 100), (184, 132), (194, 178), (172, 204), (120, 206, "s", 0.8), (74, 200), (62, 160), (70, 124)]
    head = [(70, 48), (120, 44), (150, 66), (156, 104), (138, 132), (100, 142), (60, 138), (34, 116, "s", 0.8), (38, 72)]
    return [
        ground(124, 208, 160),
        L("Body", ("path", body), [body_grad(100, 206)]),
        L("ThighLine", ("path", [(150, 198), (152, 166), (170, 146), (188, 150)], False), [("stroke", 3, "80" + BODY_LO)]),
        L("Foot", ("rect", 172, 204, 32, 10, 5), [("solid", SHADE)]),
        L("PawL", ("rect", 92, 196, 22, 34, 11), [("lin", 0, -17, 0, 17, [(0, BODY), (1, SHADE)])]),
        L("PawR", ("rect", 124, 198, 22, 32, 11), [("lin", 0, -16, 0, 16, [(0, BODY), (1, SHADE)])]),
        L("EarFar", ("ell", 62, 50, 18, 16), [("solid", SHADE)], rot=0.5),
        L("EarNear", ("ell", 138, 52, 22, 18), [("solid", SHADE)], rot=-0.4),
        L("EarNearInner", ("ell", 138, 54, 11, 9), [("solid", SNOUT)], rot=-0.4),
        L("Head", ("path", head), [body_grad(44, 142)]),
        L("Snout", ("ell", 62, 112, 100, 72), [("rad", 0, 0, 50, 0, [(0, "FF" + SNOUT), (0.6, "F0" + SNOUT), (1, "00" + SNOUT)])], clip="Head"),
        L("EyeFar", ("ell", 56, 80, 10, 12), [("solid", FACE)]),
        L("EyeNear", ("ell", 106, 78, 13, 14), [("solid", FACE)]),
        L("GlintFar", ("ell", 58, 77, 3.5, 3.5), [("solid", WHITE)]),
        L("GlintNear", ("ell", 109, 75, 4.5, 4.5), [("solid", WHITE)]),
        L("NostrilFar", ("ell", 42, 100, 7, 5), [("solid", NOSTRIL)], rot=0.4),
        L("NostrilNear", ("ell", 68, 102, 9, 5), [("solid", NOSTRIL)], rot=-0.3),
        L("Mouth", ("path", [(46, 128), (56, 132), (66, 128)], False), [("stroke", 2.6, NOSTRIL)]),
        *yuzu(96, 28, 17, 1, 0.1),
    ]


DIRECTIONS = {
    "a-loaf": (a_side, a_tq),
    "b-chibi": (b_side, b_tq),
    "c-sentinel": (c_side, c_tq),
}


def main():
    args = sys.argv[1:]
    bg = None
    if args[:1] == ["--bg"]:
        bg, args = args[1], args[2:]
    root = args[0] if args else os.path.dirname(os.path.abspath(__file__))
    for name, (side, tq) in DIRECTIONS.items():
        d = os.path.join(root, name)
        os.makedirs(d, exist_ok=True)
        doc = Doc()
        boards = [artboard(doc, "Side", side(), bg), artboard(doc, "ThreeQuarter", tq(), bg, stage_x=320)]
        with open(os.path.join(d, "scene.rml"), "w") as f:
            f.write(f'<!-- Page 10 Phase 1 direction {name}. Generated by ../gen.py. -->\n'
                    '<Rive version="1" kind="fragment">\n    ' + "\n    ".join(boards) + "\n</Rive>\n")
        with open(os.path.join(d, "rive.yaml"), "w") as f:
            f.write(f"name: capy-{name}\n")


if __name__ == "__main__":
    main()
