"""Page 10 phase 5 (spec mascot.md §K): rig additions, drafted on copies of mascot/capy.

    python3 docs/design/mascot/phase5/apply_phase5.py <out-dir>

Writes <out-dir>/rig (mascot/capy + R11 looks: a `look` enum and per-view nightcap, party hat,
Holi dabs and Diwali diya, switched by a new Look layer). Applied to mascot/capy/scene.rml at
build 5a (2026-11-12); kept as the record. Do not re-run it on the patched rig. (A Loaf view was drafted here too and dropped by the user, 2026-11-12.)
"""
import math, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RIG = os.path.join(HERE, '..', '..', '..', '..', 'mascot', 'capy')
INK, SHADE, SNOUT, BLUSH, WATER, RIPPLE, YUZU, LEAF = (
    'FF5C3B28', 'FFB27A42', 'FF8B5E3E', 'FFE8946A', 'FFA9DCD6', 'FF7FC4BC', 'FFEFA00B', 'FF8DB255')
WHITE, HI = 'FFFFFFFF', 'C7FFFFFF'

_n = [600]
def nid():
    _n[0] += 1
    return f'0:{_n[0]}'

def sv(x, y):
    return f'<StraightVertex x="{x:.2f}" y="{y:.2f}" radius="0"/>'

def cv(x, y, r, d):
    return f'<CubicMirroredVertex x="{x:.2f}" y="{y:.2f}" rotation="{r:.4f}" distance="{d:.2f}"/>'

def pp(verts, closed=True):
    return (f'<PointsPath isClosed="{"true" if closed else "false"}" isClockwise="true" name="Path">'
            f'{"".join(verts)}</PointsPath>')

def stroke(w, c=INK):
    return f'<Stroke thickness="{w}" cap="round" join="round" name="S"><SolidColor colorValue="{c}" name="C"/></Stroke>'

def fill(c):
    return f'<Fill name="F"><SolidColor colorValue="{c}" name="C"/></Fill>'

def ell(w, h, x=0, y=0):
    return f'<Ellipse x="{x:.2f}" y="{y:.2f}" width="{w}" height="{h}" originX="0.5" originY="0.5" name="Path"/>'

def rect(w, h, r, x=0, y=0):
    return (f'<Rectangle x="{x:.2f}" y="{y:.2f}" width="{w}" height="{h}" originX="0.5" originY="0.5" '
            f'cornerRadiusTL="{r}" cornerRadiusTR="{r}" cornerRadiusBL="{r}" cornerRadiusBR="{r}" name="Path"/>')

def shape(name, body, x=0, y=0):
    return f'<Shape x="{x}" y="{y}" name="{name}" id="{nid()}">{body}</Shape>'

def node(name, kids, x=0, y=0, sc=1, op=1, rot=0, ident=None):
    ident = ident or nid()
    return (ident, f'<Node x="{x}" y="{y}" rotation="{rot}" scaleX="{sc}" scaleY="{sc}" opacity="{op}" '
                   f'name="{name}" id="{ident}">{"".join(kids)}</Node>')

def mini_yuzu(x, y, s=1.0):
    """A small yuzu (pom-pom): highlight, fruit, leaf. First child draws in front."""
    return [shape('PomHi', ell(4 * s, 3.4 * s) + fill(HI), x - 2.6 * s, y - 2.2 * s),
            shape('PomLeaf', pp([sv(-5 * s, 2.5 * s), cv(-1.5 * s, -2.6 * s, -0.42, 1.8 * s), sv(5 * s, -1.6 * s),
                                cv(0.5 * s, 2.2 * s, 2.72, 1.8 * s)]) + fill(LEAF) + stroke(2.5), x + 5 * s, y - 8 * s),
            shape('Pom', ell(15 * s, 13.5 * s) + fill(YUZU) + stroke(4), x, y)]

# ── R11 accessories, in yuzu-local units (the yuzu's centre = 0,0; the head top is near y +10) ──
def nightcap():
    cone = pp([sv(-27, 9), cv(-14, -22, -1.10, 9), cv(8, -36, 0.0, 12), cv(36, -27, 0.75, 9), sv(52, -2),
               cv(37, -12, 3.6, 5), sv(27, 9)])
    return [*mini_yuzu(52, 0),
            shape('CapBrim', rect(62, 13, 6.5, 0, 11) + fill(WHITE) + stroke(4)),
            shape('CapStripe', pp([sv(-17, -14), sv(13, -26)], False) + stroke(4, WHITE)),
            shape('Cap', cone + fill(WATER) + stroke(5))]

def party_hat():
    # Drawn with the brim centre at 0,0 inside a node that leans it forward (toward the snout) about the brim.
    cone = pp([sv(-19, 0), sv(-3, -42), sv(19, 0)])
    dots = ''.join(ell(6, 6, x, y) for x, y in ((-7, -11), (6, -22), (8, -7), (-2, -31)))
    kids = [*mini_yuzu(-3, -46, 1.05),
            shape('HatBrim', rect(44, 10, 5) + fill(WHITE) + stroke(4)),
            shape('HatDots', dots + fill(YUZU)),
            shape('Hat', cone + fill(LEAF) + stroke(4.5))]
    return [node('Lean', kids, 0, 9, rot=-0.22)[1]]

def holi(dabs):
    """dabs: (x, y, colour, w, h) blobs plus two specks each, no outline (colour powder)."""
    out = []
    for i, (x, y, c, w, h) in enumerate(dabs):
        specks = ell(4, 4, x + w * 0.62, y - h * 0.35) + ell(3, 3, x - w * 0.55, y + h * 0.5)
        out.append(shape(f'Dab{i}', ell(w, h, x, y) + specks + fill('E6' + c[2:])))
    return out

def diya():
    """Clay lamp, origin at its base. Flame in yuzu with a white core."""
    flame = pp([sv(0, -47), cv(7.5, -27, 1.5708, 7), cv(0, -18, 3.1416, 5.5), cv(-7.5, -27, 4.7124, 7)])
    bowl = pp([sv(-27, -18), sv(-17, -15), cv(0, 0, 0.0, 13), sv(19, -15)])
    return [shape('Core', ell(5, 10, 0, -27) + fill(HI)),
            shape('Flame', flame + fill(YUZU) + stroke(3.5)),
            shape('Wick', pp([sv(0, -16), sv(0, -20)], False) + stroke(3)),
            shape('Oil', ell(34, 7, 1, -15) + fill(SNOUT) + stroke(4)),
            shape('Bowl', bowl + fill(SHADE) + stroke(4.5))]

# Per view: (state machine id, head parent id, yuzu node id, yuzu xy, holi dabs,
#            ground parent id or None (= artboard root, before `before`), diya xy, diya scale, before)
VIEWS = {
    'Sit':   ('0:103', '0:150', '0:149', (-46, -86),
              [(24, 52, BLUSH, 22, 16), (-48, 30, RIPPLE, 18, 13), (60, 96, LEAF, 24, 17), (-6, 112, YUZU, 16, 12)],
              '0:164', (-94, -2), 0.9, None),
    'Front': ('0:201', '0:262', '0:248', (0, -184),
              [(-16, 35, BLUSH, 26, 19), (-60, 58, RIPPLE, 21, 15), (46, 174, LEAF, 28, 20), (-51, 174, YUZU, 19, 14)],
              '0:264', (-88, -2), 0.9, None),
    'Head':  ('0:312', '0:356', '0:351', (-38, -104),
              [(26, 44, BLUSH, 22, 16), (-58, 34, RIPPLE, 18, 13), (58, 86, LEAF, 24, 17)],
              '0:359', (-100, 20), 0.66, None),
    'Onsen': ('0:395', '0:439', '0:434', (-28, -104),
              [(28, 34, BLUSH, 22, 16), (-48, 26, RIPPLE, 18, 13), (66, 62, LEAF, 22, 15)],
              None, (40, 182), 0.72, 'name="Ripple"'),
}
LOOKS = ['none', 'night', 'diwali', 'holi', 'newYear']
ENUM_ID, PROP_ID = '0:600', '0:606'
LOOK_VALUE = {k: f'0:{601 + i}' for i, k in enumerate(LOOKS)}
_n[0] = 610

def insert_first_child(s, parent_id, xml):
    m = re.search(rf'<(Node|Bone|RootBone)[^>]*id="{parent_id}"[^>]*>', s)
    assert m, parent_id
    return s[:m.end()] + xml + s[m.end():]

# Each accessory is drawn once, as a component artboard (120 x 120, content centred at 60,60), and placed
# into the four views as a NestedArtboard: the shapes are stored once instead of four times.
ACC = {'night': '0:900', 'party': '0:901', 'diya': '0:902'}

def nested(name, art, x=0, y=0, sc=1):
    ident = nid()
    return ident, (f'<NestedArtboard artboardId="{art}" x="{x - 60 * sc:.2f}" y="{y - 60 * sc:.2f}" scaleX="{sc}" '
                   f'scaleY="{sc}" opacity="0" name="{name}" id="{ident}"/>')

def acc_artboards():
    out = []
    for i, (key, kids, cy) in enumerate((('night', nightcap(), 66), ('party', party_hat(), 60), ('diya', diya(), 60))):
        art = ACC[key]
        style = nid()
        _, body = node('Acc', kids, 60, cy)
        out.append(f'\n    <Artboard isComponent="true" x="{1280 + i * 160}" y="0" width="120" height="120" '
                   f'styleId="{style}" name="Acc_{key}" id="{art}"><LayoutComponentStyle name="Artboard Style" '
                   f'id="{style}"/>{body}</Artboard>\n    <ComponentAsset artboardId="{art}" name="Acc_{key}"/>')
    return ''.join(out)

def apply_looks(s):
    s = s.replace('\n    <DataEnumCustom name="Mood"', acc_artboards() + '\n    <DataEnumCustom name="Mood"', 1)
    s = s.replace('<ViewModel defaultInstanceId',
                  f'<DataEnumCustom name="Look" id="{ENUM_ID}">' +
                  ''.join(f'<DataEnumValue key="{k}" value="{k}" id="{v}"/>' for k, v in LOOK_VALUE.items()) +
                  '</DataEnumCustom>\n    <ViewModel defaultInstanceId', 1)
    s = s.replace('<ViewModelPropertyNumber name="queued" id="0:51"/>',
                  '<ViewModelPropertyNumber name="queued" id="0:51"/>\n'
                  f'        <ViewModelPropertyEnumCustom enumId="{ENUM_ID}" name="look" id="{PROP_ID}"/>', 1)
    s = s.replace('<ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="0:51"/>',
                  '<ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="0:51"/>\n'
                  f'            <ViewModelInstanceEnum propertyValue="{LOOK_VALUE["none"]}" viewModelPropertyId="{PROP_ID}"/>', 1)
    for view, (sm, head, yuzu, (yx, yy), dabs, ground, (dx, dy), dsc, before) in VIEWS.items():
        night, n_xml = nested('LookNight', ACC['night'])
        party, p_xml = nested('LookParty', ACC['party'])
        hol, h_xml = node('LookHoli', holi(dabs), op=0)
        _, heads = node('Looks', [n_xml, p_xml, h_xml], yx, yy, 0.8 if view == 'Front' else 1)
        s = insert_first_child(s, head, heads)
        diw, d_xml = nested('LookDiwali', ACC['diya'], dx, dy, dsc)
        if ground:
            s = insert_first_child(s, ground, d_xml)
        else:  # Onsen: artboard root, in front of the water
            i = s.index(f'<Shape x="60" y="180" {before}')
            s = s[:i] + d_xml + '\n        ' + s[i:]
        # Look layer + one 1-frame animation per value: opacity of the 4 groups and the yuzu.
        show = {'none': (), 'night': (night,), 'diwali': (diw,), 'holi': (hol,), 'newYear': (party,)}
        anims, states, trans = [], [], []
        for i, look in enumerate(LOOKS):
            aid, stid = nid(), nid()
            keys = ''.join(
                f'<KeyedObject objectId="{o}"><KeyedProperty propertyKey="18"><KeyFrameDouble '
                f'value="{1 if o in show[look] else 0:.4f}" frame="0" interpolationType="hold"/>'
                f'</KeyedProperty></KeyedObject>' for o in (night, party, hol, diw))
            keys += (f'<KeyedObject objectId="{yuzu}"><KeyedProperty propertyKey="18"><KeyFrameDouble '
                     f'value="{0 if look in ("night", "newYear") else 1:.4f}" frame="0" interpolationType="hold"/>'
                     f'</KeyedProperty></KeyedObject>')
            anims.append(f'<LinearAnimation duration="1" name="look_{look}" id="{aid}">{keys}</LinearAnimation>')
            states.append(f'<AnimationState x="{180 * (i + 1)}" y="0" animationId="{aid}" id="{stid}"></AnimationState>')
            trans.append(
                f'<StateTransition stateToId="{stid}"><TransitionViewModelCondition><TransitionPropertyViewModelComparator>'
                f'<BindablePropertyEnum><DataBindContext sourcePathIds="0:40-{PROP_ID}" propertyKey="637"/>'
                f'</BindablePropertyEnum></TransitionPropertyViewModelComparator>'
                f'<TransitionValueEnumComparator value="{LOOK_VALUE[look]}"/></TransitionViewModelCondition></StateTransition>')
        first_state = re.search(r'id="(0:\d+)"', states[0]).group(1)
        layer = (f'<StateMachineLayer name="Look" id="{nid()}"><AnyState x="0" y="-150">{"".join(trans)}</AnyState>'
                 f'<ExitState x="160" y="-150"/><EntryState x="0" y="0"><StateTransition stateToId="{first_state}">'
                 f'</StateTransition></EntryState>{"".join(states)}</StateMachineLayer>')
        m = re.search(rf'<StateMachine name="Capy" id="{sm}">', s)
        end = s.index('</StateMachine>', m.end())
        s = s[:end] + layer + '\n        ' + s[end:]
        end = s.index('</StateMachine>', m.end()) + len('</StateMachine>')
        s = s[:end] + '\n        ' + '\n        '.join(anims) + s[end:]
    return s

def main(out):
    rig = os.path.join(out, 'rig')
    if os.path.exists(rig):
        shutil.rmtree(rig)
    shutil.copytree(RIG, rig, ignore=shutil.ignore_patterns('build'))
    p = os.path.join(rig, 'scene.rml')
    s = apply_looks(open(p).read())  # read before opening for write (that truncates)
    open(p, 'w').write(s)
    print(rig)

if __name__ == '__main__':
    main(sys.argv[1])
