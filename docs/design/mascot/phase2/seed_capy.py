"""One-time seed for mascot/capy/scene.rml (Page 10 phase 2, spec §C).

Pulls the S1 art from docs/design/mascot/styles/gen_s1v2.py and adds the rig: groups, Sit bones + skin,
mood face sets, view model `Capy`, converters and one state machine per artboard. After seeding, the RML
is the source of truth and is hand-edited. Kept for provenance only: re-running it OVERWRITES
mascot/capy/scene.rml and loses every hand edit.

Usage: python3 seed_capy.py <out_dir> [--bg AARRGGBB]
"""
import math
import os
import sys

REPO = os.path.expanduser("~/kuch_bhi/docs/design/mascot")
sys.path.insert(0, os.path.join(REPO, "styles"))
sys.path.insert(0, os.path.join(REPO, "directions"))
import gen_s1v2 as g  # noqa: E402
from gen import paint_xml, BODY, BODY_HI, SHADE, SNOUT, FACE, WHITE, BLUSH, YUZU, LEAF_HI  # noqa: E402
from gen_styles import INK, lined  # noqa: E402

MOODS = ["chill", "active", "happy", "sleepy", "worried", "focused"]
POSES = ["none", "pet", "celebrate", "guard"]
BLINKERS = ("active", "worried")

# ---------------------------------------------------------------- ids
VM, VMI = "0:40", "0:39"
P = dict(mood="0:41", pose="0:42", still="0:43", reducedMotion="0:44", pet="0:45", holding="0:46",
         hop="0:47", wave="0:48", celebrate="0:49", lookX="0:50", queued="0:51", flush="0:52")
MOOD_ENUM, POSE_ENUM = "0:60", "0:70"
MOOD_V = {m: f"0:{61 + i}" for i, m in enumerate(MOODS)}
POSE_V = {p: f"0:{71 + i}" for i, p in enumerate(POSES)}
_next = [100]


def nid():
    _next[0] += 1
    return f"0:{_next[0]}"


def f(v):
    return f"{v:.4f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


# ---------------------------------------------------------------- tree
class N:
    """A Node / Shape / Bone. `at` = origin in art space; children are placed relative to it."""

    def __init__(self, name, at=(0, 0), kids=(), tag="Node", attrs=None, inner="", local=None, art_root=False):
        self.name, self.at, self.kids, self.tag = name, at, list(kids), tag
        self.attrs, self.inner, self.local, self.art_root = dict(attrs or {}), inner, local, art_root
        self.id, self.parent = nid(), None
        for k in self.kids:
            k.parent = self

    def origin_for_kids(self):
        return (0, 0) if self.art_root else self.at

    def loc(self):
        if self.local is not None:
            return self.local
        p = self.parent.origin_for_kids() if self.parent else (0, 0)
        return (self.at[0] - p[0], self.at[1] - p[1])

    def xml(self, ind=8):
        pad = " " * ind
        a = {}
        if self.tag in ("Node", "Shape", "RootBone"):
            x, y = self.loc()
            if abs(x) > 1e-6:
                a["x"] = f(float(x))
            if abs(y) > 1e-6:
                a["y"] = f(float(y))
        a.update(self.attrs)
        a["name"], a["id"] = self.name, self.id
        attrs = " ".join(f'{k}="{v}"' for k, v in a.items())
        body = (self.inner and [pad + "    " + self.inner] or []) + [k.xml(ind + 4) for k in self.kids]
        if not body:
            return f"{pad}<{self.tag} {attrs}/>"
        return f"{pad}<{self.tag} {attrs}>\n" + "\n".join(body) + f"\n{pad}</{self.tag}>"

    def walk(self):
        yield self
        for k in self.kids:
            yield from k.walk()


def path_xml(pts, closed=True, ox=0, oy=0, weight=None):
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    vs = []
    for i, p in enumerate(pts):
        x, y = p[0] - ox, p[1] - oy
        kind = p[2] if len(p) > 2 else "s"
        w = weight(i) if weight else None
        if kind == "c" or (not closed and i in (0, n - 1)):
            r = p[3] if kind == "c" else 0
            inner = f'<Weight values="{w[1]}" indices="{w[0]}"/>' if w else ""
            vs.append(f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="{r}">{inner}</StraightVertex>' if w else
                      f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="{r}"/>')
            continue
        t = p[3] if len(p) > 3 else 1.0
        a, b = pts[(i - 1) % n], pts[(i + 1) % n]
        rot = math.atan2(b[1] - a[1], b[0] - a[0])
        dist = math.hypot(b[0] - a[0], b[1] - a[1]) / 6 * t
        if w:
            cw = (f'<CubicWeight values="{w[1]}" indices="{w[0]}" inValues="{w[1]}" inIndices="{w[0]}" '
                  f'outValues="{w[1]}" outIndices="{w[0]}"/>')
            vs.append(f'<CubicMirroredVertex x="{x:.2f}" y="{y:.2f}" rotation="{rot:.4f}" distance="{dist:.2f}">{cw}'
                      f'</CubicMirroredVertex>')
        else:
            vs.append(f'<CubicMirroredVertex x="{x:.2f}" y="{y:.2f}" rotation="{rot:.4f}" distance="{dist:.2f}"/>')
    return vs, area > 0


def geom_xml(geom, ox, oy, rot=0.0):
    r = f' rotation="{rot:.4f}"' if rot else ""
    if geom[0] == "path":
        vs, cw = path_xml(geom[1], geom[2] if len(geom) > 2 else True, ox, oy)
        closed = geom[2] if len(geom) > 2 else True
        return f'<PointsPath isClosed="{str(closed).lower()}" isClockwise="{str(cw).lower()}" name="Path">{"".join(vs)}</PointsPath>'
    if geom[0] == "ell":
        _, cx, cy, w, h = geom
        return f'<Ellipse x="{cx - ox:.2f}" y="{cy - oy:.2f}" width="{w}" height="{h}" originX="0.5" originY="0.5"{r} name="Path"/>'
    _, cx, cy, w, h, rad = geom
    return (f'<Rectangle x="{cx - ox:.2f}" y="{cy - oy:.2f}" width="{w}" height="{h}" cornerRadiusTL="{rad}" '
            f'originX="0.5" originY="0.5"{r} name="Path"/>')


def bbox_center(geom):
    if geom[0] in ("ell", "rect"):
        return geom[1], geom[2]
    xs, ys = [p[0] for p in geom[1]], [p[1] for p in geom[1]]
    return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2


def S(name, items, at=None, clip=None, extra="", opacity=None):
    """Shape from one or more L tuples (all drawn with the first item's paints)."""
    if not isinstance(items, list):
        items = [items]
    paints = items[0][2]
    kw = items[0][3]
    if at is None:
        at = bbox_center(items[0][1])
    paths = "".join(geom_xml(it[1], at[0], at[1], it[3].get("rot", 0.0)) for it in items)
    paint = "".join(paint_xml(p) for p in paints)
    op = opacity if opacity is not None else kw.get("opacity", 1.0)
    attrs = {"opacity": f(float(op))} if op != 1.0 else {}
    c = f'<ClippingShape sourceId="{clip.id}" name="Clip"/>' if clip else ""
    return N(name, at, tag="Shape", attrs=attrs, inner=paths + paint + c + extra)


def pick(layers, *names, prefix=False):
    out = []
    for lay in layers:
        if (lay[0].startswith(names) if prefix else lay[0] in names):
            out.append(lay)
    return out


def by_name(layers, name):
    return [lay for lay in layers if lay[0] == name][0]


# ---------------------------------------------------------------- animation
EASE = '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>'
OUT = '<CubicEaseInterpolator x1="0.2" y1="0.6" x2="0.4" y2="1"/>'
PROP = {"x": 13, "y": 14, "rot": 15, "sx": 16, "sy": 17, "op": 18}


class Anim:
    def __init__(self, name, frames, loop=False):
        self.name, self.frames, self.loop, self.id, self.keys = name, frames, loop, nid(), []

    def key(self, node, prop, kfs, rel=True):
        """kfs: [(frame, value[, interp])]; x/y values are offsets from the node's local position."""
        base = 0.0
        if rel and prop in ("x", "y"):
            base = node.loc()[0 if prop == "x" else 1]
        self.keys.append((node.id, PROP[prop], [(k[0], k[1] + base, k[2] if len(k) > 2 else "ease") for k in kfs]))
        return self

    def hold(self, node, prop, value, rel=True):
        return self.key(node, prop, [(0, value, "hold")], rel)

    def xml(self, ind=8):
        pad = " " * ind
        lp = ' loopValue="loop"' if self.loop else ""
        objs = {}
        for oid, pk, kfs in self.keys:
            kf = []
            for fr, v, it in kfs:
                if it == "ease":
                    kf.append(f'<KeyFrameDouble value="{v:.4f}" frame="{fr}" interpolationType="cubic">{EASE}</KeyFrameDouble>')
                elif it == "out":
                    kf.append(f'<KeyFrameDouble value="{v:.4f}" frame="{fr}" interpolationType="cubic">{OUT}</KeyFrameDouble>')
                else:
                    kf.append(f'<KeyFrameDouble value="{v:.4f}" frame="{fr}" interpolationType="{it}"/>')
            objs.setdefault(oid, []).append(f'<KeyedProperty propertyKey="{pk}">{"".join(kf)}</KeyedProperty>')
        body = "".join(f'\n{pad}    <KeyedObject objectId="{oid}">{"".join(v)}</KeyedObject>' for oid, v in objs.items())
        tail = f"\n{pad}" if body else ""
        return f'{pad}<LinearAnimation duration="{self.frames}"{lp} name="{self.name}" id="{self.id}">{body}{tail}</LinearAnimation>'


# ---------------------------------------------------------------- state machine
def _cmp(bind, key, rhs):
    return (f'<TransitionViewModelCondition><TransitionPropertyViewModelComparator><{bind}>'
            f'<DataBindContext sourcePathIds="{VM}-{key}" propertyKey="{ {"BindablePropertyBoolean": 634, "BindablePropertyEnum": 637, "BindablePropertyTrigger": 686}[bind] }"/>'
            f'</{bind}></TransitionPropertyViewModelComparator>{rhs}</TransitionViewModelCondition>')


def c_bool(prop, v):
    return _cmp("BindablePropertyBoolean", P[prop], f'<TransitionValueBooleanComparator value="{str(v).lower()}"/>')


def c_enum(prop, vid):
    return _cmp("BindablePropertyEnum", P[prop], f'<TransitionValueEnumComparator value="{vid}"/>')


def c_trig(prop):
    return _cmp("BindablePropertyTrigger", P[prop], "<TransitionValueTriggerComparator/>")


def tr(to, conds=(), duration=0, exit_end=False):
    a = f' duration="{duration}"' if duration else ""
    if exit_end:
        a += ' enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"'
    return f'<StateTransition stateToId="{to}"{a}>{"".join(conds)}</StateTransition>'


class Layer:
    def __init__(self, name):
        self.name, self.id, self.states, self.any, self.entry = name, nid(), [], [], None

    def state(self, anim, reset=False):
        sid = nid()
        self.states.append([sid, anim, reset, []])
        return sid

    def add(self, sid, t):
        [s for s in self.states if s[0] == sid][0][3].append(t)

    def xml(self, ind):
        pad = " " * ind
        out = [f'{pad}<StateMachineLayer name="{self.name}" id="{self.id}">',
               f'{pad}    <AnyState x="0" y="-150">{"".join(self.any)}</AnyState>',
               f'{pad}    <ExitState x="160" y="-150"/>',
               f'{pad}    <EntryState x="0" y="0">{tr(self.entry)}</EntryState>']
        for i, (sid, anim, reset, ts) in enumerate(self.states):
            r = ' reset="true"' if reset else ""
            out.append(f'{pad}    <AnimationState x="{180 + 180 * (i % 4)}" y="{120 * (i // 4)}" animationId="{anim.id}"{r} '
                       f'id="{sid}">{"".join(ts)}</AnimationState>')
        out.append(f"{pad}</StateMachineLayer>")
        return "\n".join(out)


def loop_or_still(layer_name, loop_anim, still_anim):
    """Idle/Props: loop unless still or reducedMotion."""
    L_ = Layer(layer_name)
    a = L_.state(loop_anim)
    s = L_.state(still_anim)
    L_.entry = a
    L_.add(a, tr(s, [c_bool("still", True)]))
    L_.add(a, tr(s, [c_bool("reducedMotion", True)]))
    L_.add(s, tr(a, [c_bool("still", False), c_bool("reducedMotion", False)], 200))
    return L_


def enum_layer(name, prop, anims, values, default):
    L_ = Layer(name)
    ids = {k: L_.state(a) for k, a in anims.items()}
    L_.entry = ids[default]
    for k, sid in ids.items():
        L_.any.append(tr(sid, [c_enum(prop, values[k])], 150))
    return L_


def action_layer(rest, hold, oneshots):
    """oneshots: {trigger prop: anim}. Ignored under reducedMotion (F3: jump to the end pose = rest)."""
    L_ = Layer("Action")
    r = L_.state(rest)
    L_.entry = r
    h = L_.state(hold)
    L_.add(r, tr(h, [c_bool("holding", True), c_bool("reducedMotion", False)], 0))
    L_.add(h, tr(r, [c_bool("holding", False)], 220))
    for prop, anim in oneshots.items():
        s = L_.state(anim, reset=True)
        L_.any.append(tr(s, [c_trig(prop), c_bool("reducedMotion", False)], 60))
        L_.add(s, tr(r, [], 150, exit_end=True))
    return L_


# ---------------------------------------------------------------- shared art helpers
def yuzu_node(cx, cy, r=14, name="Yuzu", leaf=True):
    parts = g.yuzu(cx, cy, r, leaf, name)
    kids = [S(p[0], p, at=(cx, cy) if p[0] == name else None) for p in reversed(parts)]
    return N(name + "Node", (cx, cy), kids)


def face_group(mood, layers, props, eye_at, brow_merge=True, extra=()):
    """One mood's face set: props, brows, an Eyes node (blink pivot), mouth."""
    eyes = [lay for lay in layers if lay[0].startswith("Eye") and not lay[0].endswith(("Brow", "Glint"))]
    glints = [lay for lay in layers if lay[0].endswith("Glint")]
    brows = [lay for lay in layers if lay[0].endswith("Brow")]
    mouth = [lay for lay in layers if lay[0] in ("Mouth", "Tongue")]
    kids = []
    for p in props:
        if p[0] == "Z0":
            continue
        if p[0] == "Z1":
            z = [x for x in props if x[0] in ("Z0", "Z1")]
            kids.append(N("Zz", bbox_center(z[0][1]), [S("Z1", z[1]), S("Z0", z[0])]))
        else:
            kids.append(S(p[0], p))
    kids += list(extra)
    if brows:
        kids.append(S("Brows", brows, at=eye_at))
    eye_kids = []
    if glints:
        eye_kids.append(S("Glints", glints, at=eye_at))
    eye_kids.append(S("Eye", eyes, at=eye_at))
    kids.append(N("Eyes", eye_at, eye_kids))
    for m in mouth:
        kids.append(S(m[0], m))
    return N("Face_" + mood, eye_at, kids, attrs={} if mood == "chill" else {"opacity": "0"})


# ---------------------------------------------------------------- artboards
class Board:
    def __init__(self, name, stage_x, bg):
        self.name, self.stage_x, self.bg = name, stage_x, bg
        self.id, self.sty, self.sm = nid(), nid(), nid()
        self.anims, self.layers, self.root = [], [], []

    def anim(self, name, frames, loop=False):
        a = Anim(name, frames, loop)
        self.anims.append(a)
        return a

    def xml(self):
        art = "\n".join(n.xml(8) for n in self.root)
        if self.bg:
            bgs = S("BG", ("BG", ("rect", 120, 120, 240, 240, 0), [("solid", self.bg[2:], int(self.bg[:2], 16))], {}))
            art += "\n" + bgs.xml(8)
        sm = (f'        <StateMachine name="Capy" id="{self.sm}">\n' + "\n".join(L_.xml(12) for L_ in self.layers) +
              "\n        </StateMachine>")
        anims = "\n".join(a.xml(8) for a in self.anims)
        return (f'    <Artboard x="{self.stage_x}" y="0" width="240" height="240" defaultStateMachineId="{self.sm}" '
                f'viewModelId="{VM}" viewModelInstanceId="{VMI}" styleId="{self.sty}" name="{self.name}" id="{self.id}">\n'
                f'        <LayoutComponentStyle name="Artboard Style" id="{self.sty}"/>\n{art}\n{sm}\n{anims}\n    </Artboard>')


def mood_anims(b, groups, blush_shapes, blush_scale=(1.33, 1.3)):
    out = {}
    for m in MOODS:
        a = b.anim("mood_" + m, 1)
        for k, grp in groups.items():
            a.hold(grp, "op", 1.0 if k == m else 0.0)
        for bl in blush_shapes:
            hp = m == "happy"
            a.hold(bl, "sx", blush_scale[0] if hp else 1.0).hold(bl, "sy", blush_scale[1] if hp else 1.0)
            a.hold(bl, "op", 1.0 if hp else 0.72)
        out[m] = a
    return out


def pet_anim(b, act, groups, blush_shapes, blush_scale=(1.33, 1.3), squish=1.0):
    a = b.anim("pet", 36)
    for k, grp in groups.items():
        a.key(grp, "op", [(0, 1.0 if k == "happy" else 0.0, "hold"), (36, 1.0 if k == "happy" else 0.0, "hold")])
    for bl in blush_shapes:
        a.key(bl, "sx", [(0, 1.0), (8, blush_scale[0] * 1.08), (36, blush_scale[0])])
        a.key(bl, "sy", [(0, 1.0), (8, blush_scale[1] * 1.08), (36, blush_scale[1])])
        a.key(bl, "op", [(0, 0.72), (8, 1.0, "hold"), (36, 1.0, "hold")])
    d = 0.1 * squish
    a.key(act, "sy", [(0, 1.0), (7, 1 - d), (16, 1 + d * 0.45), (26, 1 - d * 0.15), (36, 1.0)])
    a.key(act, "sx", [(0, 1.0), (7, 1 + d * 0.9), (16, 1 - d * 0.35), (26, 1 + d * 0.1), (36, 1.0)])
    return a


def hop_anim(b, act, height=22):
    a = b.anim("hop", 32)
    a.key(act, "y", [(0, 0.0, "linear"), (4, 0.0, "out"), (14, -height), (24, 0.0, "linear"), (32, 0.0)])
    a.key(act, "sy", [(0, 1.0), (4, 0.9), (10, 1.06), (22, 1.0), (25, 0.9), (32, 1.0)])
    a.key(act, "sx", [(0, 1.0), (4, 1.08), (10, 0.96), (22, 1.0), (25, 1.07), (32, 1.0)])
    return a


def rest_anim(b, act, extra=()):
    """Action layer's idle state: resets everything only Action keys, so a hold or one-shot never sticks."""
    a = b.anim("rest", 1).hold(act, "sx", 1.0).hold(act, "sy", 1.0).hold(act, "y", 0.0).hold(act, "rot", 0.0)
    for node, prop, v in extra:
        a.hold(node, prop, v)
    return a


def hold_anim(b, act):
    return b.anim("hold", 12).key(act, "sy", [(0, 1.0), (12, 0.85)]).key(act, "sx", [(0, 1.0), (12, 1.12)])


def props_loop(b, groups, look_extra=None):
    """Blink round eyes, chill content squeeze, z drift, sweat bob, sparkle twinkle. 4.6 s loop."""
    a = b.anim("props", 276, loop=True)
    s = b.anim("props_still", 1)
    for m, grp in groups.items():
        eyes = [k for k in grp.kids if k.name == "Eyes"][0]
        if m in BLINKERS:
            a.key(eyes, "sy", [(0, 1.0, "hold"), (258, 1.0, "linear"), (263, 0.1, "linear"), (269, 1.0, "hold"), (276, 1.0, "hold")])
            s.hold(eyes, "sy", 1.0)
        if m == "chill":
            a.key(eyes, "sy", [(0, 1.0, "hold"), (110, 1.0), (135, 0.55), (165, 0.55), (195, 1.0, "hold"), (276, 1.0, "hold")])
            s.hold(eyes, "sy", 1.0)
        for k in grp.walk():
            if k.name == "Zz":
                a.key(k, "y", [(0, 0.0), (138, -9.0), (276, 0.0)])
                s.hold(k, "y", 0.0)
                z1 = [z for z in k.kids if z.name == "Z1"][0]
                a.key(z1, "op", [(0, 0.75), (138, 0.2), (276, 0.75)])
                s.hold(z1, "op", 0.75)
            elif k.name == "Sweat":
                a.key(k, "y", [(0, 0.0), (69, 4.0), (138, 0.0), (207, 4.0), (276, 0.0)])
                s.hold(k, "y", 0.0)
            elif k.name.startswith("Spark"):
                ph = 0 if k.name.endswith("1") else 46
                a.key(k, "sx", [(0, 1.0), (46 + ph, 0.65), (92 + ph, 1.0), (276, 1.0, "hold")])
                a.key(k, "sy", [(0, 1.0), (46 + ph, 0.65), (92 + ph, 1.0), (276, 1.0, "hold")])
                s.hold(k, "sx", 1.0).hold(k, "sy", 1.0)
    if look_extra:
        look_extra(a, s)
    return a, s


def base_layers(b, idle, still, groups, blush, props, action):
    b.layers = [loop_or_still("Idle", idle, still),
                enum_layer("Mood", "mood", mood_anims(b, groups, blush), MOOD_V, "chill"),
                loop_or_still("Props", *props)]
    return action


# ---- Sit -------------------------------------------------------------------------------------------
def build_sit(bg):
    b = Board("Sit", 0, bg)
    chill = g.sit("chill")
    HEAD_AT = (138, 132)
    BACK_AT = (128, 196)
    ang = math.atan2(HEAD_AT[1] - BACK_AT[1], HEAD_AT[0] - BACK_AT[0])
    blen = math.hypot(HEAD_AT[0] - BACK_AT[0], HEAD_AT[1] - BACK_AT[1])

    groups = {}
    for m in MOODS:
        face = g.profile_face(expr=m)
        groups[m] = face_group(m, face, g.profile_props(m), (72, 88))
    shared = g.profile_face(expr="chill")
    blush = S("Blush", by_name(shared, "Blush"))
    blush.inner = blush.inner.replace(f'{150:02X}{BLUSH}', f'D2{BLUSH}')
    nostril = S("Nostril", by_name(shared, "Nostril"))
    ears_l = pick(chill, "EarFar", "Ear")

    body_pts = g.HEAD_FRONT + [(166, 86), (196, 124), (210, 168), (202, 202), (176, 216), (120, 220), (70, 216),
                               (50, 198), (46, 168), (54, 146), (40, 140), (26, 134)]
    head_ix = {0, 1, 2, 3, 4, 5, 16, 17}
    blend_ix = {6, 15}

    def weight(i):
        if i in head_ix:
            return (2, 255)
        if i in blend_ix:
            return (1 | (2 << 8), 128 | (127 << 8))
        return (1, 255)

    vs, cw = path_xml(body_pts, True, 0, 0, weight)
    ca, sa = math.cos(ang), math.sin(ang)
    back = N("Back", BACK_AT, tag="RootBone", attrs={"length": f(blen), "rotation": f(ang)})
    body = N("Body", (0, 0), tag="Shape")
    body.inner = (f'<PointsPath isClosed="true" isClockwise="{str(cw).lower()}" name="Path">{"".join(vs)}'
                  f'<Skin tx="0" ty="0" name="Skin">'
                  f'<Tendon boneId="{back.id}" xx="{ca:.6f}" xy="{sa:.6f}" yx="{-sa:.6f}" yy="{ca:.6f}" tx="{BACK_AT[0]}" ty="{BACK_AT[1]}" name="BackT"/>'
                  f'<Tendon boneId="@HEAD" tx="{HEAD_AT[0]}" ty="{HEAD_AT[1]}" name="HeadT"/></Skin></PointsPath>'
                  + "".join(paint_xml(p) for p in lined(("solid", BODY))))

    ears_t = nid()
    ears = [S("Ear", ears_l[1], extra=f'<DrawRules drawTargetId="{ears_t}" name="Rules"><DrawTarget drawableId="{body.id}" '
                                     f'placementValue="after" name="BehindBody" id="{ears_t}"/></DrawRules>'),
            S("EarFar", ears_l[0], extra=f'<DrawRules drawTargetId="@EFT" name="Rules"><DrawTarget drawableId="{body.id}" '
                                         f'placementValue="after" name="BehindBody" id="@EFT"/></DrawRules>')]
    eft = nid()
    ears[1].inner = ears[1].inner.replace("@EFT", eft)
    muzzle = S("Muzzle", by_name(shared, "Muzzle"), clip=body)

    head = N("Head", HEAD_AT, [*groups.values(), yuzu_node(92, 46), blush, nostril, muzzle, *ears], tag="Bone",
             attrs={"length": "30", "rotation": f(-ang)})
    body.inner = body.inner.replace("@HEAD", head.id)
    back.kids, head.parent = [head], back

    paw = N("PawWave", (64, 206), [S("PawLToes", pick(chill, "Toe60_0", "Toe60_1")), S("PawL", by_name(chill, "PawL"))])
    paw_l = N("PawLHolder", (64, 206), [paw])
    rest = [S("PawRToes", pick(chill, "Toe92_0", "Toe92_1")), S("PawR", by_name(chill, "PawR")),
            S("FootToes", pick(chill, "Toe186_0", "Toe186_1", "Toe186_2")), S("Foot", by_name(chill, "Foot")),
            S("Thigh", by_name(chill, "Thigh")), S("Ticks", pick(chill, "Tick1", "Tick2")),
            S("Belly", ("Belly", ("ell", 92, 189, 70, 50), by_name(chill, "Belly")[2], {})), body]
    breathe = N("Breathe", (120, 220), [back, paw_l, *rest])
    act = N("Act", (120, 220), [breathe])
    b.root = [N("Place", (120, 220), [act])]

    idle = b.anim("idle", 204, loop=True)
    idle.key(breathe, "sy", [(0, 1.0), (102, 1.025), (204, 1.0)]).key(breathe, "sx", [(0, 1.0), (102, 0.99), (204, 1.0)])
    idle.key(head, "rot", [(0, -ang), (102, -ang - 0.035), (204, -ang)], rel=False)
    still = b.anim("still", 1).hold(breathe, "sy", 1.0).hold(breathe, "sx", 1.0).hold(head, "rot", -ang)
    props = props_loop(b, groups)

    wave = b.anim("wave", 60)
    wave.key(paw, "y", [(0, 0.0), (10, -34.0), (50, -34.0), (60, 0.0)])
    wave.key(paw, "rot", [(0, 0.0), (10, -0.5), (20, 0.1), (30, -0.5), (40, 0.1), (50, -0.3), (60, 0.0)])
    wave.key(head, "rot", [(0, -ang), (10, -ang - 0.08), (50, -ang - 0.08), (60, -ang)], rel=False)

    b.layers = [loop_or_still("Idle", idle, still),
                enum_layer("Mood", "mood", mood_anims(b, groups, [blush]), MOOD_V, "chill"),
                loop_or_still("Props", *props),
                action_layer(rest_anim(b, act, [(paw, "y", 0.0), (paw, "rot", 0.0)]), hold_anim(b, act),
                             {"pet": pet_anim(b, act, groups, [blush]), "hop": hop_anim(b, act), "wave": wave})]
    return b


# ---- Front -----------------------------------------------------------------------------------------
def build_front(bg):
    b = Board("Front", 320, bg)
    base = g.front("active")
    groups = {}
    for m in MOODS:
        lay = g.front(m)
        props = [x for x in lay if x[0].startswith(("Spark", "Sweat", "Z"))]
        if m == "happy":
            for i, x in enumerate(lay):
                if x[0] == "Tongue":
                    lay[i] = ("Tongue", ("ell", 120, 129, 6, 4), x[2], {})
        groups[m] = face_group(m, [x for x in lay if x[0].startswith(("EyeL", "EyeR", "Mouth", "Tongue"))],
                               props, (120, 96))
    blush_l, blush_r = S("BlushL", by_name(base, "BlushL")), S("BlushR", by_name(base, "BlushR"))
    for bl in (blush_l, blush_r):
        bl.inner = bl.inner.replace(f'{150:02X}{BLUSH}', f'D2{BLUSH}')
    look = N("Look", (120, 220), [*groups.values(), blush_l, blush_r, S("Philtrum", by_name(base, "Philtrum")),
                                  S("Nostrils", pick(base, "NostrilL", "NostrilR")), S("Muzzle", by_name(base, "Muzzle"))])
    sparks = N("CelebSparks", (120, 100), [S(f"CSpark{i}", g.sparkle(f"CSpark{i}", *p)) for i, p in
                                           enumerate(((52, 64, 8), (190, 70, 8), (200, 126, 6)))], attrs={"opacity": "0"})
    yz = yuzu_node(120, 36)
    arm_l = N("ArmL", (92, 150), [S("ArmLLine", by_name(base, "ArmL"))])
    arm_r = N("ArmR", (148, 150), [S("ArmRLine", by_name(base, "ArmR"))])
    gk = g.front("guard")
    key = N("Key", (116, 178), [S("KeyBits", pick(gk, "KeyTooth2", "KeyTooth1", "KeyShaft"), at=(140, 180)),
                                 S("KeyHole", by_name(gk, "KeyHole")), S("KeyRing", by_name(gk, "KeyRing"))],
            attrs={"opacity": "0"})
    toes = [x for x in base if x[0].startswith("Toe")]
    body = S("Body", by_name(base, "Body"))
    breathe = N("Breathe", (120, 220), [sparks, yz, look, arm_r, arm_l, key, S("Toes", toes, at=(120, 211)),
                                         S("Feet", pick(base, "FootR", "FootL"), at=(120, 214)),
                                         S("Belly", by_name(base, "Belly")), body,
                                         S("Ears", pick(base, "EarR", "EarL"), at=(120, 58))])
    act = N("Act", (120, 220), [breathe])
    b.root = [N("Place", (120, 220), [act])]

    idle = b.anim("idle", 204, loop=True)
    idle.key(breathe, "sy", [(0, 1.0), (102, 1.025), (204, 1.0)]).key(breathe, "sx", [(0, 1.0), (102, 0.99), (204, 1.0)])
    idle.key(yz, "rot", [(0, 0.0), (102, 0.06), (204, 0.0)])
    still = b.anim("still", 1).hold(breathe, "sy", 1.0).hold(breathe, "sx", 1.0).hold(yz, "rot", 0.0)
    props = props_loop(b, groups)

    UP = 3.06

    def pose(name, al, ar, k, sp, yy):
        return (b.anim(name, 1).hold(arm_l, "rot", al).hold(arm_r, "rot", ar).hold(key, "op", k)
                .hold(sparks, "op", sp).hold(yz, "y", yy))

    poses = {"none": pose("pose_none", 0.0, 0.0, 0.0, 0.0, 0.0), "pet": pose("pose_pet", 0.0, 0.0, 0.0, 0.0, 0.0),
             "celebrate": pose("pose_celebrate", UP, -UP, 0.0, 1.0, -10.0),
             "guard": pose("pose_guard", -0.23, 0.23, 1.0, 0.0, 0.0)}

    wave = b.anim("wave", 60)
    wave.key(arm_r, "rot", [(0, 0.0), (10, -3.1), (20, -2.7), (30, -3.2), (40, -2.7), (50, -3.1), (60, 0.0)])

    cel = b.anim("celebrate", 72)
    for k, grp in groups.items():
        cel.key(grp, "op", [(0, 1.0 if k == "happy" else 0.0, "hold"), (72, 1.0 if k == "happy" else 0.0, "hold")])
    cel.key(arm_l, "rot", [(0, 0.0), (10, UP), (62, UP), (72, 0.0)]).key(arm_r, "rot", [(0, 0.0), (10, -UP), (62, -UP), (72, 0.0)])
    cel.key(sparks, "op", [(0, 0.0), (10, 1.0), (60, 1.0), (72, 0.0)])
    cel.key(sparks, "sx", [(0, 0.6), (14, 1.1), (24, 0.9), (36, 1.1), (48, 0.9), (72, 1.0)])
    cel.key(sparks, "sy", [(0, 0.6), (14, 1.1), (24, 0.9), (36, 1.1), (48, 0.9), (72, 1.0)])
    cel.key(yz, "y", [(0, 0.0), (12, -14.0), (24, -10.0), (60, -10.0), (72, 0.0)])
    cel.key(act, "y", [(0, 0.0), (6, 0.0, "out"), (16, -16.0), (26, 0.0, "linear"), (36, 0.0, "out"), (46, -10.0), (56, 0.0), (72, 0.0)])
    cel.key(act, "sy", [(0, 1.0), (5, 0.9), (12, 1.05), (26, 0.92), (32, 1.0), (72, 1.0)])

    b.layers = [loop_or_still("Idle", idle, still),
                enum_layer("Mood", "mood", mood_anims(b, groups, [blush_l, blush_r]), MOOD_V, "chill"),
                enum_layer("Pose", "pose", poses, POSE_V, "none"),
                loop_or_still("Props", *props),
                action_layer(rest_anim(b, act), hold_anim(b, act),
                             {"pet": pet_anim(b, act, groups, [blush_l, blush_r]), "hop": hop_anim(b, act), "wave": wave,
                              "celebrate": cel})]
    b.look = look
    return b


# ---- Head / Onsen (profile bust) --------------------------------------------------------------------
def bust(ox, oy, k, name):
    lay = g.head("chill") if name == "Head" else g.onsen("chill")
    groups = {}
    for m in MOODS:
        face = g.profile_face(ox, oy, expr=m, k=k)
        groups[m] = face_group(m, face, g.profile_props(m, ox, oy), (72 + ox, 88 + oy))
    shared = g.profile_face(ox, oy, expr="chill", k=k)
    blush = S("Blush", by_name(shared, "Blush"))
    blush.inner = blush.inner.replace(f'{150:02X}{BLUSH}', f'D2{BLUSH}')
    body = S("Body", by_name(lay, "Body"), at=(100 + ox, 110 + oy))
    ears = pick(lay, "Ear", "EarFar")
    parts = [*groups.values(), yuzu_node(92 + ox, 46 + oy), blush, S("Nostril", by_name(shared, "Nostril")),
             S("Muzzle", by_name(shared, "Muzzle"), clip=body), body, S("Ear", ears[1]), S("EarFar", ears[0])]
    return groups, blush, parts


def build_head(bg):
    b = Board("Head", 640, bg)
    groups, blush, parts = bust(0, 0, 1.4, "Head")
    breathe = N("Breathe", (130, 150), parts)
    look = N("Look", (130, 150), [breathe])
    act = N("Act", (130, 150), [look])
    art = N("Art", (0, 0), [N("Place", (130, 150), [act])], attrs={"scaleX": "1.32", "scaleY": "1.32"},
            local=(-8, 4), art_root=True)
    b.root = [art]
    idle = b.anim("idle", 204, loop=True)
    idle.key(breathe, "y", [(0, 0.0), (102, -2.5), (204, 0.0)]).key(breathe, "rot", [(0, 0.0), (102, -0.03), (204, 0.0)])
    still = b.anim("still", 1).hold(breathe, "y", 0.0).hold(breathe, "rot", 0.0)
    b.layers = [loop_or_still("Idle", idle, still),
                enum_layer("Mood", "mood", mood_anims(b, groups, [blush]), MOOD_V, "chill"),
                loop_or_still("Props", *props_loop(b, groups)),
                action_layer(rest_anim(b, act), hold_anim(b, act),
                             {"pet": pet_anim(b, act, groups, [blush]), "hop": hop_anim(b, act, 14)})]
    b.look = look
    return b


def build_onsen(bg):
    b = Board("Onsen", 960, bg)
    ox, oy = 10, 30
    groups, blush, parts = bust(ox, oy, 1.4, "Onsen")
    lay = g.onsen("chill", 3)
    breathe = N("Breathe", (130, 180), parts)
    act = N("Act", (130, 180), [breathe])
    qs = []
    for i, (qx, qy) in enumerate(((156, 162), (184, 168), (210, 160))):
        yz = g.yuzu(qx, qy, 10, False, f"Q{i + 1}")
        flt = N(f"Q{i + 1}Float", (qx, qy), [S(p[0], p) for p in reversed(yz)])
        qs.append(N(f"Q{i + 1}", (qx, qy), [flt], attrs={"opacity": "0"}))
    fl = g.yuzu(184, 168, 10, False, "Flush")
    flush_n = N("FlushQ", (184, 168), [S(p[0], p) for p in reversed(fl)], attrs={"opacity": "0"})
    steam = N("Steam", (160, 26), [S("Steam", pick(lay, "Steam0", "Steam1"), at=(160, 26))])
    b.root = [steam, flush_n, *reversed(qs), S("Ripple", by_name(lay, "Ripple")), S("Water", by_name(lay, "Water")),
              N("Place", (130, 180), [act]), S("PoolBack", by_name(lay, "PoolBack"))]
    b.qs = qs

    idle = b.anim("idle", 204, loop=True)
    idle.key(breathe, "y", [(0, 0.0), (102, 3.0), (204, 0.0)]).key(breathe, "rot", [(0, 0.0), (102, 0.02), (204, 0.0)])
    still = b.anim("still", 1).hold(breathe, "y", 0.0).hold(breathe, "rot", 0.0)
    ripple = [n for n in b.root if n.name == "Ripple"][0]

    def extra(a, s):
        a.key(steam, "y", [(0, 6.0, "linear"), (138, -8.0, "hold"), (139, 6.0, "linear"), (276, -8.0, "linear")])
        a.key(steam, "op", [(0, 0.0), (40, 1.0), (138, 0.0, "hold"), (139, 0.0), (179, 1.0), (276, 0.0)])
        a.key(ripple, "x", [(0, 0.0), (138, 8.0), (276, 0.0)])
        s.hold(steam, "y", 0.0).hold(steam, "op", 1.0).hold(ripple, "x", 0.0)

    props = props_loop(b, groups, extra)
    flush = b.anim("flush", 42)
    flush.key(flush_n, "op", [(0, 1.0, "hold"), (28, 1.0), (42, 0.0)])
    flush.key(flush_n, "x", [(0, 0.0, "linear"), (42, 40.0)]).key(flush_n, "y", [(0, 0.0, "out"), (16, -46.0), (42, -30.0)])
    flush.key(flush_n, "rot", [(0, 0.0, "linear"), (42, 2.4)])
    flush.key(act, "rot", [(0, 0.0), (8, -0.06), (20, 0.0)])
    b.layers = [loop_or_still("Idle", idle, still),
                enum_layer("Mood", "mood", mood_anims(b, groups, [blush]), MOOD_V, "chill"),
                loop_or_still("Props", *props),
                action_layer(rest_anim(b, act, [(flush_n, "op", 0.0), (flush_n, "x", 0.0), (flush_n, "y", 0.0), (flush_n, "rot", 0.0)]),
                             hold_anim(b, act),
                             {"pet": pet_anim(b, act, groups, [blush]), "hop": hop_anim(b, act, 12), "flush": flush})]
    return b


# ---------------------------------------------------------------- binds + root
def bind(node, prop_key, vm_prop, conv):
    node.inner += f'<DataBindContext sourcePathIds="{VM}-{P[vm_prop]}" propertyKey="{prop_key}" converterId="{conv}"/>'


def main():
    out = sys.argv[1]
    bg = sys.argv[sys.argv.index("--bg") + 1] if "--bg" in sys.argv else None
    sit, front, head, onsen = build_sit(bg), build_front(bg), build_head(bg), build_onsen(bg)
    conv = []
    look_x, look_r, interp = nid(), nid(), nid()
    conv.append(f'<DataConverterRangeMapper minInput="-1" maxInput="1" minOutput="-6" maxOutput="6" clampLower="true" '
                f'clampUpper="true" name="LookToX" id="{look_x}"/>')
    conv.append(f'<DataConverterRangeMapper minInput="-1" maxInput="1" minOutput="-0.12" maxOutput="0.12" clampLower="true" '
                f'clampUpper="true" name="LookToTilt" id="{look_r}"/>')
    conv.append(f'<DataConverterInterpolator interpolationType="linear" duration="0.35" name="Ease" id="{interp}"/>')
    bind(front.look, 13, "lookX", look_x)
    bind(head.look, 15, "lookX", look_r)
    for i, q in enumerate(onsen.qs):
        mo, my, go, gy = nid(), nid(), nid(), nid()
        conv.append(f'<DataConverterRangeMapper minInput="{i}" maxInput="{i + 1}" minOutput="0" maxOutput="1" clampLower="true" '
                    f'clampUpper="true" name="Q{i + 1}Show" id="{mo}"/>')
        conv.append(f'<DataConverterRangeMapper minInput="{i}" maxInput="{i + 1}" minOutput="18" maxOutput="0" clampLower="true" '
                    f'clampUpper="true" name="Q{i + 1}Rise" id="{my}"/>')
        conv.append(f'<DataConverterGroup name="Q{i + 1}ShowEased" id="{go}"><DataConverterGroupItem converterId="{mo}"/>'
                    f'<DataConverterGroupItem converterId="{interp}"/></DataConverterGroup>')
        conv.append(f'<DataConverterGroup name="Q{i + 1}RiseEased" id="{gy}"><DataConverterGroupItem converterId="{my}"/>'
                    f'<DataConverterGroupItem converterId="{interp}"/></DataConverterGroup>')
        bind(q, 18, "queued", go)
        bind(q.kids[0], 14, "queued", gy)

    vm = [f'<DataEnumCustom name="Mood" id="{MOOD_ENUM}">' +
          "".join(f'<DataEnumValue key="{m}" value="{m.title()}" id="{MOOD_V[m]}"/>' for m in MOODS) + "</DataEnumCustom>",
          f'<DataEnumCustom name="Pose" id="{POSE_ENUM}">' +
          "".join(f'<DataEnumValue key="{p}" value="{p.title()}" id="{POSE_V[p]}"/>' for p in POSES) + "</DataEnumCustom>"]
    props = [f'<ViewModelPropertyEnumCustom enumId="{MOOD_ENUM}" name="mood" id="{P["mood"]}"/>',
             f'<ViewModelPropertyEnumCustom enumId="{POSE_ENUM}" name="pose" id="{P["pose"]}"/>']
    inst = [f'<ViewModelInstanceEnum propertyValue="{MOOD_V["chill"]}" viewModelPropertyId="{P["mood"]}"/>',
            f'<ViewModelInstanceEnum propertyValue="{POSE_V["none"]}" viewModelPropertyId="{P["pose"]}"/>']
    for k, t in (("still", "Boolean"), ("reducedMotion", "Boolean"), ("holding", "Boolean"), ("pet", "Trigger"),
                 ("hop", "Trigger"), ("wave", "Trigger"), ("celebrate", "Trigger"), ("flush", "Trigger"),
                 ("lookX", "Number"), ("queued", "Number")):
        props.append(f'<ViewModelProperty{t} name="{k}" id="{P[k]}"/>')
        v = {"Boolean": ' propertyValue="false"', "Number": ' propertyValue="0"', "Trigger": ""}[t]
        inst.append(f'<ViewModelInstance{t}{v} viewModelPropertyId="{P[k]}"/>')
    vm.append(f'<ViewModel defaultInstanceId="{VMI}" name="Capy" id="{VM}">\n        ' + "\n        ".join(props) +
              f'\n        <ViewModelInstance exports="true" name="Default" id="{VMI}">\n            ' +
              "\n            ".join(inst) + "\n        </ViewModelInstance>\n    </ViewModel>")

    doc = ("<!-- Page 10 mascot rig (spec docs/design/pages/mascot.md §C). Seeded once from gen_s1v2.py art on\n"
           "     2026-11-10; hand-edit from here. Views: Sit (2 bones, skinned body), Front, Head, Onsen.\n"
           "     View model `Capy` drives every artboard's state machine `Capy` (Idle / Mood / [Pose] / Props / Action). -->\n"
           '<Rive version="1" kind="fragment">\n' + "\n".join(x.xml() for x in (sit, front, head, onsen)) + "\n    " +
           "\n    ".join(conv) + "\n    " + "\n    ".join(vm) + "\n</Rive>\n")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "scene.rml"), "w") as fh:
        fh.write(doc)
    if not os.path.exists(os.path.join(out, "rive.yaml")):
        with open(os.path.join(out, "rive.yaml"), "w") as fh:
            fh.write("name: capy\n")


if __name__ == "__main__":
    main()
