"""Style test for direction C (Sentinel): the same sitting capybara in two styles.

  s1-sticker : kawaii sticker style (the docs/Inspiration/Capybara look): one dark
               outline, flat fills, dot eyes, blush, crisp muzzle patch.
  s2-flat    : bold flat style (Duolingo-like): no outlines, chunky shapes, big
               white eyes, hard-edged cel shading, open smile.

Each gets two artboards: Sit (three-quarter, full body, ~120 px slots) and Head
(head + yuzu only, for 24-48 px slots). Drafting tool like ../directions/gen.py.

Usage: python3 gen_styles.py [--bg AARRGGBB] [outdir]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "directions"))
from gen import (BODY, BODY_HI, BODY_LO, SHADE, SNOUT, NOSTRIL, FACE, WHITE, BLUSH,  # noqa: E402
                 YUZU, YUZU_HI, YUZU_LO, LEAF_HI, LEAF_LO, Doc, L, shape)

INK = "5C3B28"      # outline = mascot nostril colour
TONGUE = "E07A6A"
OUT = 5             # outline width in a 240 box (~1.7 device px at 40 dp on the Redmi)


def artboard(doc, name, layers, bg=None, size=240, stage_x=0, group=None):
    """group = (x, y, scale): wraps the art in one Node so a crop reuses the same geometry."""
    aid, sty = doc.nid(), doc.nid()
    ids, xml = {}, []
    for lname, geom, paints, kw in layers:
        kw = dict(kw)
        if "clip" in kw:
            kw["clip"] = ids[kw["clip"]]
        sid, s = shape(doc, lname, geom, paints, **kw)
        ids[lname] = sid
        xml.append(s)
    art = "\n        ".join(reversed(xml))
    if group:
        gx, gy, gs = group
        art = (f'<Node x="{gx}" y="{gy}" scaleX="{gs}" scaleY="{gs}" name="Art" id="{doc.nid()}">\n        '
               f'{art}\n        </Node>')
    if bg:
        art += "\n        " + shape(doc, "BG", ("rect", size / 2, size / 2, size, size, 0),
                                    [("solid", bg[2:], int(bg[:2], 16))])[1]
    return (f'<Artboard x="{stage_x}" y="0" width="{size}" height="{size}" styleId="{sty}" name="{name}" id="{aid}">\n'
            f'        <LayoutComponentStyle name="Artboard Style" id="{sty}"/>\n        {art}\n    </Artboard>')


def lined(fill):
    return [fill, ("stroke", OUT, INK)]


# ---------------- S1 sticker ----------------

S1_HEAD = [(96, 50), (132, 55), (150, 78), (154, 106)]
S1_SIL = S1_HEAD + [(178, 130), (198, 166), (196, 198), (170, 212), (110, 214), (62, 210),
                    (44, 186), (44, 150), (42, 116), (48, 74), (68, 55)]
S1_HEADONLY = S1_HEAD + [(146, 130), (96, 142), (48, 130), (42, 112), (48, 74), (68, 55)]


def s1_yuzu(cx, cy, r):
    return [
        L("Leaf", ("path", [(cx + 2, cy - r + 2, "c", 0), (cx + 10, cy - r - 10), (cx + 24, cy - r - 8, "c", 0),
                            (cx + 14, cy - r + 1)]), lined(("solid", LEAF_HI))),
        L("Yuzu", ("ell", cx, cy, r * 2.1, r * 1.9), lined(("solid", YUZU))),
        L("YuzuHi", ("ell", cx - r * 0.4, cy - r * 0.35, r * 0.5, r * 0.32), [("solid", WHITE, 200)], rot=-0.5),
    ]


def s1_face():
    return [
        L("Muzzle", ("ell", 94, 108, 66, 46), [("solid", SNOUT)], clip="Body"),
        L("NoseL", ("ell", 85, 100, 7, 5), [("solid", INK)], rot=0.3),
        L("NoseR", ("ell", 103, 100, 7, 5), [("solid", INK)], rot=-0.3),
        L("Mouth", ("path", [(84, 114), (89, 119), (94, 115), (99, 119), (104, 114)], False), [("stroke", 3, INK)]),
        L("BlushL", ("ell", 55, 114, 16, 9), [("solid", BLUSH, 150)]),
        L("BlushR", ("ell", 136, 112, 16, 9), [("solid", BLUSH, 150)]),
        L("EyeL", ("ell", 62, 94, 10, 11), [("solid", FACE)]),
        L("EyeR", ("ell", 127, 92, 10, 11), [("solid", FACE)]),
    ]


def s1_ears():
    return [
        L("EarL", ("ell", 64, 60, 22, 18), lined(("solid", SHADE)), rot=0.4),
        L("EarR", ("ell", 136, 62, 22, 18), lined(("solid", SHADE)), rot=-0.4),
    ]


def s1_sit():
    return [
        *s1_ears(),
        L("Body", ("path", S1_SIL), lined(("solid", BODY))),
        L("BackShade", ("ell", 206, 176, 90, 130), [("solid", SHADE, 170)], clip="Body"),
        L("Thigh", ("path", [(156, 204), (160, 174), (184, 160)], False), [("stroke", 3.5, INK)]),
        L("Foot", ("ell", 176, 208, 36, 14), lined(("solid", SHADE))),
        L("PawL", ("ell", 80, 202, 22, 18), lined(("solid", SHADE))),
        L("PawR", ("ell", 110, 204, 22, 18), lined(("solid", SHADE))),
        *s1_face(),
        *s1_yuzu(98, 34, 15),
    ]


def s1_head():
    return [
        *s1_ears(),
        L("Body", ("path", S1_HEADONLY), lined(("solid", BODY))),
        *s1_face(),
        *s1_yuzu(98, 34, 15),
    ]


# ---------------- S2 flat (Duolingo-like) ----------------

S2_HEAD = [(98, 40), (140, 46), (162, 74), (166, 106)]
S2_SIL = S2_HEAD + [(184, 132), (202, 170), (198, 202), (170, 214), (108, 216), (58, 212),
                    (40, 186), (40, 150), (30, 108), (40, 64), (64, 44)]
S2_HEADONLY = S2_HEAD + [(154, 138), (98, 150), (44, 140), (30, 108), (40, 64), (64, 44)]


def s2_yuzu(cx, cy, r):
    return [
        L("Leaf", ("path", [(cx + 2, cy - r + 2, "c", 0), (cx + 12, cy - r - 12), (cx + 28, cy - r - 9, "c", 0),
                            (cx + 16, cy - r + 1)]), [("solid", LEAF_HI)]),
        L("LeafShade", ("path", [(cx + 2, cy - r + 2, "c", 0), (cx + 28, cy - r - 9, "c", 0), (cx + 16, cy - r + 1)]),
          [("solid", LEAF_LO)]),
        L("Yuzu", ("ell", cx, cy, r * 2.1, r * 1.95), [("solid", YUZU)]),
        L("YuzuShade", ("ell", cx + r * 0.55, cy + r * 0.6, r * 2.0, r * 1.7), [("solid", YUZU_LO)], clip="Yuzu"),
        L("YuzuHi", ("ell", cx - r * 0.42, cy - r * 0.42, r * 0.6, r * 0.4), [("solid", YUZU_HI)], rot=-0.5),
    ]


def s2_face():
    return [
        L("Muzzle", ("rect", 96, 120, 92, 52, 26), [("solid", SNOUT)]),
        L("MuzzleHi", ("ell", 96, 100, 60, 14), [("solid", "A47250")], clip="Muzzle"),
        L("NoseL", ("rect", 84, 106, 9, 6, 3), [("solid", NOSTRIL)], rot=0.25),
        L("NoseR", ("rect", 108, 106, 9, 6, 3), [("solid", NOSTRIL)], rot=-0.25),
        L("Mouth", ("path", [(82, 124, "c", 3), (110, 124, "c", 3), (96, 140)]), [("solid", FACE)]),
        L("Tongue", ("ell", 96, 138, 16, 10), [("solid", TONGUE)], clip="Mouth"),
        L("EyeWL", ("ell", 64, 84, 20, 24), [("solid", WHITE)]),
        L("EyeWR", ("ell", 128, 82, 23, 27), [("solid", WHITE)]),
        L("PupilL", ("ell", 66, 87, 13, 16), [("solid", FACE)]),
        L("PupilR", ("ell", 130, 85, 15, 18), [("solid", FACE)]),
        L("GlintL", ("ell", 68, 83, 4.5, 4.5), [("solid", WHITE)]),
        L("GlintR", ("ell", 133, 81, 5, 5), [("solid", WHITE)]),
        L("BlushR", ("ell", 150, 118, 18, 10), [("solid", BLUSH, 170)]),
    ]


def s2_ears():
    return [
        L("EarL", ("ell", 56, 50, 22, 18), [("solid", SHADE)], rot=0.45),
        L("EarR", ("ell", 146, 54, 24, 20), [("solid", SHADE)], rot=-0.45),
        L("EarRIn", ("ell", 146, 56, 12, 10), [("solid", SNOUT)], rot=-0.45),
    ]


def s2_sit():
    return [
        L("Shadow", ("ell", 120, 216, 170, 16), [("solid", FACE, 40)]),
        *s2_ears(),
        L("Body", ("path", S2_SIL), [("solid", BODY)]),
        L("BackShade", ("ell", 214, 178, 110, 150), [("solid", BODY_LO)], clip="Body"),
        L("TopHi", ("ell", 92, 52, 76, 20), [("solid", BODY_HI)], clip="Body"),
        L("Belly", ("ell", 108, 196, 92, 54), [("solid", BODY_HI)], clip="Body"),
        L("Foot", ("ell", 180, 210, 40, 16), [("solid", SHADE)]),
        L("PawL", ("rect", 82, 208, 28, 20, 10), [("solid", SHADE)]),
        L("PawR", ("rect", 116, 210, 28, 18, 9), [("solid", SHADE)]),
        *s2_face(),
        *s2_yuzu(100, 24, 16),
    ]


def s2_head():
    return [
        *s2_ears(),
        L("Body", ("path", S2_HEADONLY), [("solid", BODY)]),
        L("BackShade", ("ell", 196, 120, 80, 120), [("solid", BODY_LO)], clip="Body"),
        L("TopHi", ("ell", 92, 52, 76, 20), [("solid", BODY_HI)], clip="Body"),
        *s2_face(),
        *s2_yuzu(100, 24, 16),
    ]


STYLES = {
    # name: (sit, head, head-crop group (x, y, scale) mapping the head into the 240 box)
    "s1-sticker": (s1_sit, s1_head, (-20, 14, 1.45)),
    "s2-flat": (s2_sit, s2_head, (-18, 22, 1.4)),
}


def main():
    args = sys.argv[1:]
    bg = None
    if args[:1] == ["--bg"]:
        bg, args = args[1], args[2:]
    root = args[0] if args else os.path.dirname(os.path.abspath(__file__))
    for name, (sit, head, grp) in STYLES.items():
        d = os.path.join(root, name)
        os.makedirs(d, exist_ok=True)
        doc = Doc()
        boards = [artboard(doc, "Sit", sit(), bg), artboard(doc, "Head", head(), bg, stage_x=320, group=grp)]
        with open(os.path.join(d, "scene.rml"), "w") as f:
            f.write(f'<!-- Page 10 Phase 1 style test {name} (direction C). Generated by ../gen_styles.py. -->\n'
                    '<Rive version="1" kind="fragment">\n    ' + "\n    ".join(boards) + "\n</Rive>\n")
        with open(os.path.join(d, "rive.yaml"), "w") as f:
            f.write(f"name: capy-{name}\n")


if __name__ == "__main__":
    main()
