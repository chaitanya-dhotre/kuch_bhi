"""S1 Sticker, round 2: capybara features made explicit (user, 2026-11-09: "looks like a seal").

What makes a capybara read as one (from docs/Inspiration/Capybara):
  - a long, blunt, box-ended snout; the dark muzzle patch sits at the snout TIP, not mid-face
  - the eye is a small dot high and far back on the head; small round ear at the back top
  - a flat head top, no neck, a big bean/pear body, stubby feet with toe ticks
  - front view: wide flat head, eyes far apart at the sides, a tall muzzle block with
    two nostril slits and a split-lip mouth

Artboards: Sit (three-quarter body, profile head), Front, Head (profile bust, for <=56 dp),
Onsen (Head soaking with floating yuzus: the offline-banner idea). Drafting tool.

Usage: python3 gen_s1v2.py [--bg AARRGGBB] [outdir]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "directions"))
from gen import BODY, BODY_HI, SHADE, SNOUT, FACE, WHITE, BLUSH, YUZU, LEAF_HI, Doc, L  # noqa: E402
from gen_styles import INK, artboard, lined  # noqa: E402

WATER, WATER_LO = "A9DCD6", "7FC4BC"


def yuzu(cx, cy, r, leaf=True, name="Yuzu"):
    out = []
    if leaf:
        out.append(L(name + "Leaf", ("path", [(cx + 2, cy - r + 2, "c", 0), (cx + 9, cy - r - 9), (cx + 22, cy - r - 7, "c", 0),
                                               (cx + 13, cy - r + 1)]), lined(("solid", LEAF_HI))))
    out += [
        L(name, ("ell", cx, cy, r * 2.1, r * 1.9), lined(("solid", YUZU))),
        L(name + "Hi", ("ell", cx - r * 0.4, cy - r * 0.35, r * 0.5, r * 0.32), [("solid", WHITE, 200)], rot=-0.5),
    ]
    return out


def toes(x, y, n=2, gap=6):
    return [L(f"Toe{x}_{i}", ("path", [(x + (i - (n - 1) / 2) * gap, y - 5), (x + (i - (n - 1) / 2) * gap, y + 1)], False),
              [("stroke", 2.5, INK)]) for i in range(n)]


# ---- profile head (shared by Sit, Head, Onsen). Facing left; flip with scaleX -1 at runtime.
HEAD_FRONT = [(14, 120, "c", 12), (14, 88, "c", 12), (34, 74), (70, 66), (110, 60), (140, 66)]


KEY = "E8A21D"
# Eye rule (user, 2026-11-09): idle = relaxed curved-line eyes; doing something = round eyes;
# intense/focused work = narrowed eyes + a low brow.
EXPRS = ("chill", "active", "happy", "pet", "sleepy", "worried", "focused", "celebrate", "guard")


def corner(pts):
    return [(x, y, "c", 0) for x, y in pts]


def eye(name, ex, ey, expr, inner, k=1.0):
    """inner = -1 if the nose side is to the left, +1 if right (brows tilt toward it)."""
    lw = 4.5 * k
    def q(dx, dy, *rest):
        return (ex + dx * k, ey + dy * k) + tuple(rest)
    if expr == "chill":
        return [L(name, ("path", [q(-6, -1), q(0, 3), q(6, -1)], False), [("stroke", lw, FACE)])]
    if expr in ("happy", "pet", "celebrate"):
        return [L(name, ("path", [q(-6, 3), q(0, -4), q(6, 3)], False), [("stroke", lw, FACE)])]
    if expr == "sleepy":
        return [L(name, ("path", [q(-6, 3), q(6, 3)], False), [("stroke", lw, FACE)])]
    if expr in ("focused", "guard"):
        return [L(name, ("path", [q(-5, -1, "c", 1), q(5, -1, "c", 1), q(4, 4), q(0, 6), q(-4, 4)]),
                  [("solid", FACE)]),
                L(name + "Brow", ("path", [q(inner * 8, -6), q(-inner * 7, -11)], False), [("stroke", 3.5 * k, INK)])]
    if expr == "worried":
        return [L(name, ("ell", ex, ey, 10 * k, 11 * k), [("solid", FACE)]),
                L(name + "Glint", ("ell", *q(2, -2), 3 * k, 3 * k), [("solid", WHITE)]),
                L(name + "Brow", ("path", [q(inner * 8, -13), q(-inner * 7, -9)], False), [("stroke", 3.5 * k, INK)])]
    return [L(name, ("ell", ex, ey, 9 * k, 10 * k), [("solid", FACE)])]


def zzz(x, y):
    out = []
    for i, (dx, dy, k) in enumerate(((0, 0, 1.0), (14, -16, 0.75))):
        w = 12 * k
        out.append(L(f"Z{i}", ("path", corner([(x + dx, y + dy), (x + dx + w, y + dy), (x + dx, y + dy + w), (x + dx + w, y + dy + w)]),
                               False), [("stroke", 3.5, INK)], opacity=0.75))
    return out


def sweat(cx, cy):
    return [L("Sweat", ("path", [(cx, cy - 10, "c", 0), (cx + 6, cy + 2), (cx, cy + 8), (cx - 6, cy + 2)]),
              [("solid", WATER), ("stroke", 2.5, INK)])]


def sparkle(name, x, y, r=8):
    q = r / 4
    return L(name, ("path", corner([(x, y - r), (x + q, y - q), (x + r, y), (x + q, y + q), (x, y + r), (x - q, y + q),
                                    (x - r, y), (x - q, y - q)])), [("solid", YUZU), ("stroke", 2.5, INK)])


def profile_face(ox=0, oy=0, clip="Body", expr="chill", k=1.0):
    def p(x, y):
        return (x + ox, y + oy)
    mouth = {
        "happy": [L("Mouth", ("path", [(17 + ox, 122 + oy, "c", 2), (31 + ox, 122 + oy, "c", 2), (24 + ox, 131 + oy)]), [("solid", FACE)])],
        "worried": [L("Mouth", ("path", [p(16, 127), p(20, 124), p(24, 127), p(28, 124), p(32, 127)], False), [("stroke", 3, INK)])],
        "focused": [L("Mouth", ("path", [p(18, 126), p(30, 126)], False), [("stroke", 3, INK)])],
        "sleepy": [L("Mouth", ("ell", *p(24, 127), 6, 5), [("solid", FACE)])],
    }
    mouth["pet"] = mouth["celebrate"] = mouth["happy"]
    mouth["guard"] = mouth["focused"]
    big = expr in ("happy", "pet", "celebrate")
    return [
        L("Muzzle", ("rect", *p(26, 104), 54, 84, 24), [("solid", SNOUT)], clip=clip),
        L("Nostril", ("ell", *p(22, 94), 6, 10), [("solid", INK)], rot=0.35),
        *mouth.get(expr, [L("Mouth", ("path", [p(17, 125), p(24, 129), p(32, 124)], False), [("stroke", 3, INK)])]),
        L("Blush", ("ell", *p(78, 112), 24 if big else 18, 13 if big else 10), [("solid", BLUSH, 210 if big else 150)]),
        *eye("Eye", *p(72, 88), expr, -1, k),
    ]


def profile_props(expr, ox=0, oy=0):
    if expr == "sleepy":
        return zzz(120 + ox, 28 + oy)
    if expr == "worried":
        return sweat(160 + ox, 92 + oy)
    if expr in ("happy", "pet", "celebrate"):
        return [sparkle("Spark1", 160 + ox, 40 + oy), sparkle("Spark2", 44 + ox, 50 + oy, 6)]
    return []


def profile_ears(ox=0, oy=0):
    return [
        L("EarFar", ("ell", 154 + ox, 74 + oy, 14, 12), lined(("solid", SHADE)), rot=-0.5),
        L("Ear", ("ell", 138 + ox, 64 + oy, 20, 16), lined(("solid", SHADE)), rot=-0.4),
    ]


def sit(expr="chill"):
    sil = HEAD_FRONT + [(166, 86), (196, 124), (210, 168), (202, 202), (176, 216), (120, 220), (70, 216),
                        (50, 198), (46, 168), (54, 146), (40, 140), (26, 134)]
    return [
        *profile_ears(),
        L("Body", ("path", sil), lined(("solid", BODY))),
        L("Belly", ("ell", 92, 190, 70, 52), [("solid", BODY_HI, 150)], clip="Body"),
        L("Tick1", ("path", [(176, 118), (182, 124)], False), [("stroke", 2.5, INK)]),
        L("Tick2", ("path", [(186, 134), (192, 140)], False), [("stroke", 2.5, INK)]),
        L("Thigh", ("path", [(150, 212), (154, 184), (176, 168)], False), [("stroke", 3.5, INK)]),
        L("Foot", ("ell", 180, 214, 40, 14), lined(("solid", SHADE))),
        *toes(186, 214, 3),
        L("PawL", ("ell", 64, 212, 26, 16), lined(("solid", SHADE))),
        *toes(60, 212),
        L("PawR", ("ell", 96, 214, 26, 16), lined(("solid", SHADE))),
        *toes(92, 214),
        *profile_face(expr=expr),
        *yuzu(92, 46, 14),
        *profile_props(expr),
    ]


def head(expr="chill"):
    sil = HEAD_FRONT + [(162, 84), (172, 112), (164, 140), (130, 152), (70, 150), (40, 142), (26, 134)]
    return [
        *profile_ears(),
        L("Body", ("path", sil), lined(("solid", BODY))),
        *profile_face(expr=expr, k=1.4),
        *yuzu(92, 46, 14),
        *profile_props(expr),
    ]


def onsen(expr="chill", queued=3):
    """Head soaking in a round hot-spring pool; 3 queued messages = 3 small yuzus floating."""
    ox, oy = 10, 30
    steam = [L(f"Steam{i}", ("path", [(x, 40), (x + 6, 31), (x, 22), (x + 6, 13)], False), [("stroke", 3.5, INK, )], opacity=0.45)
             for i, x in enumerate((150, 170))]
    return [
        L("PoolBack", ("ell", 120, 168, 236, 70), lined(("solid", WATER_LO))),
        *profile_ears(ox, oy),
        L("Body", ("path", [(x + ox, y + oy) + tuple(rest) for x, y, *rest in
                            HEAD_FRONT + [(162, 84), (172, 112), (168, 150), (120, 170), (60, 166), (30, 150)]]),
          lined(("solid", BODY))),
        *profile_face(ox, oy, expr=expr, k=1.4),
        *yuzu(92 + ox, 46 + oy, 14),
        L("Water", ("path", [(4, 168), (40, 160), (80, 166), (120, 158), (160, 166), (200, 158), (236, 166),
                             (226, 196), (120, 212), (14, 196)]), [("solid", WATER), ("stroke", 4, INK)]),
        L("Ripple", ("path", [(40, 182), (60, 178), (80, 182)], False), [("stroke", 3, WATER_LO)]),
        *[part for i, (qx, qy) in enumerate(((156, 162), (184, 168), (210, 160))[:queued])
          for part in yuzu(qx, qy, 10, False, f"Q{i + 1}")],
        *steam,
    ]


def front(expr="active"):
    sil = [(120, 50), (158, 54), (174, 74), (178, 104), (176, 128), (190, 156), (200, 188), (188, 210),
           (156, 218), (120, 220), (84, 218), (52, 210), (40, 188), (50, 156), (64, 128), (62, 104), (66, 74), (82, 54)]
    happy = expr in ("happy", "pet", "celebrate")
    if expr == "celebrate":
        arms = [[(92, 150), (78, 130), (74, 110)], [(148, 150), (162, 130), (166, 110)]]
    elif expr == "guard":
        arms = [[(92, 150), (96, 170), (110, 178)], [(148, 150), (144, 170), (130, 178)]]
    else:
        arms = [[(92, 150), (90, 166), (102, 178)], [(148, 150), (150, 166), (138, 178)]]
    if happy:
        mouth = [L("Mouth", ("path", [(110, 120, "c", 3), (130, 120, "c", 3), (120, 134)]), [("solid", FACE)]),
                 L("Tongue", ("ell", 120, 132, 10, 6), [("solid", "E07A6A")], clip="Mouth")]
    elif expr == "worried":
        mouth = [L("Mouth", ("path", [(110, 125), (115, 122), (120, 125), (125, 122), (130, 125)], False), [("stroke", 3, INK)])]
    elif expr in ("focused", "guard"):
        mouth = [L("Mouth", ("path", [(112, 124), (128, 124)], False), [("stroke", 3, INK)])]
    else:
        mouth = [L("Mouth", ("path", [(110, 121), (115, 127), (120, 122), (125, 127), (130, 121)], False), [("stroke", 3, INK)])]
    props = []
    if expr == "celebrate":
        props = [sparkle("Spark1", 52, 64), sparkle("Spark2", 190, 70), sparkle("Spark3", 200, 126, 6)]
    elif happy:
        props = [sparkle("Spark1", 186, 72, 7)]
    elif expr == "worried":
        props = sweat(186, 86)
    elif expr == "sleepy":
        props = zzz(168, 30)
    key = []
    if expr == "guard":
        key = [L("KeyRing", ("ell", 104, 176, 22, 22), lined(("solid", KEY))),
               L("KeyHole", ("ell", 104, 176, 8, 8), [("solid", BODY_HI)]),
               L("KeyShaft", ("rect", 128, 176, 32, 7, 3), lined(("solid", KEY))),
               L("KeyTooth1", ("rect", 136, 183, 5, 8, 1.5), lined(("solid", KEY))),
               L("KeyTooth2", ("rect", 143, 183, 5, 6, 1.5), lined(("solid", KEY)))]
    return [
        L("EarL", ("ell", 78, 58, 20, 16), lined(("solid", SHADE)), rot=0.4),
        L("EarR", ("ell", 162, 58, 20, 16), lined(("solid", SHADE)), rot=-0.4),
        L("Body", ("path", sil), lined(("solid", BODY))),
        L("Belly", ("ell", 120, 190, 74, 50), [("solid", BODY_HI, 150)], clip="Body"),
        L("FootL", ("ell", 94, 214, 30, 15), lined(("solid", SHADE))),
        *toes(94, 214, 3),
        L("FootR", ("ell", 146, 214, 30, 15), lined(("solid", SHADE))),
        *toes(146, 214, 3),
        *key,
        L("ArmL", ("path", arms[0], False), [("stroke", 4, INK)]),
        L("ArmR", ("path", arms[1], False), [("stroke", 4, INK)]),
        L("Muzzle", ("rect", 120, 120, 60, 64, 24), [("solid", SNOUT)]),
        L("NostrilL", ("ell", 110, 103, 6, 9), [("solid", INK)], rot=-0.4),
        L("NostrilR", ("ell", 130, 103, 6, 9), [("solid", INK)], rot=0.4),
        L("Philtrum", ("path", [(120, 108), (120, 121 if not happy else 120)], False), [("stroke", 3, INK)]),
        *mouth,
        L("BlushL", ("ell", 82, 116, 22 if happy else 16, 12 if happy else 9), [("solid", BLUSH, 210 if happy else 150)]),
        L("BlushR", ("ell", 158, 116, 22 if happy else 16, 12 if happy else 9), [("solid", BLUSH, 210 if happy else 150)]),
        *eye("EyeL", 86, 96, expr, 1),
        *eye("EyeR", 154, 96, expr, -1),
        *yuzu(120, 26 if expr == "celebrate" else 36, 14),
        *props,
    ]


SHEET = [  # (artboard name, view fn, expr, kwargs)
    ("Head-chill", "head", "chill"), ("Head-active", "head", "active"), ("Head-happy", "head", "happy"),
    ("Head-sleepy", "head", "sleepy"), ("Head-worried", "head", "worried"), ("Head-focused", "head", "focused"),
    ("Front-active", "front", "active"), ("Front-pet", "front", "pet"), ("Front-celebrate", "front", "celebrate"),
    ("Front-guard", "front", "guard"), ("Front-worried", "front", "worried"),
    ("Sit-chill", "sit", "chill"), ("Sit-sleepy", "sit", "sleepy"), ("Sit-focused", "sit", "focused"),
    ("Onsen-chill", "onsen", "chill"), ("Onsen-happy", "onsen", "happy"),
    ("Onsen-q2", "onsen2", "active"), ("Onsen-q1", "onsen1", "active"), ("Onsen-q0", "onsen0", "happy"),
]


def main():
    args = sys.argv[1:]
    bg = None
    if args[:1] == ["--bg"]:
        bg, args = args[1], args[2:]
    root = args[0] if args else os.path.dirname(os.path.abspath(__file__))
    d = os.path.join(root, "s1v2")
    os.makedirs(d, exist_ok=True)
    doc = Doc()
    boards = [artboard(doc, "Sit", sit(), bg),
              artboard(doc, "Front", front(), bg, stage_x=320),
              artboard(doc, "Head", head(), bg, stage_x=640, group=(-8, 4, 1.32)),
              artboard(doc, "Onsen", onsen(), bg, stage_x=960)]
    with open(os.path.join(d, "scene.rml"), "w") as f:
        f.write('<!-- Page 10 Phase 1: S1 sticker round 2. Generated by ../gen_s1v2.py. -->\n'
                '<Rive version="1" kind="fragment">\n    ' + "\n    ".join(boards) + "\n</Rive>\n")
    with open(os.path.join(d, "rive.yaml"), "w") as f:
        f.write("name: capy-s1v2\n")

    d = os.path.join(root, "expressions")
    os.makedirs(d, exist_ok=True)
    doc = Doc()
    views = {"head": head, "front": front, "sit": sit, "onsen": onsen,
             "onsen2": lambda e: onsen(e, 2), "onsen1": lambda e: onsen(e, 1), "onsen0": lambda e: onsen(e, 0)}
    boards = []
    for i, (name, view, expr) in enumerate(SHEET):
        kw = {"group": (-8, 4, 1.32)} if view == "head" else {}
        boards.append(artboard(doc, name, views[view](expr), bg, stage_x=320 * (i % 6), **kw).replace(
            ' y="0" width', f' y="{320 * (i // 6)}" width', 1))
    with open(os.path.join(d, "scene.rml"), "w") as f:
        f.write('<!-- Page 10: expression sheet. Generated by ../gen_s1v2.py. -->\n'
                '<Rive version="1" kind="fragment">\n    ' + "\n    ".join(boards) + "\n</Rive>\n")
    with open(os.path.join(d, "rive.yaml"), "w") as f:
        f.write("name: capy-expressions\n")


if __name__ == "__main__":
    main()
