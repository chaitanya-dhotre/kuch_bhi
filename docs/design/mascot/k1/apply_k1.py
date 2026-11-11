"""K1 restore redesign rig additions (Page 10 mascot, spec docs/design/pages/mascot.md §I).

Drafting tool for the spec: reads mascot/capy/scene.rml, writes a patched copy
to OUT/scene.rml so the new parts can be rendered headless before PASS. After
PASS the build applies the same edits to mascot/capy/scene.rml (the rig is
hand-edited, spec §C) and this script is retired, like phase 3's.

    python3 docs/design/mascot/k1/apply_k1.py <out-dir>

Adds to Front only: pose `vault` (capybara steps left and shrinks, the vault
fades in beside it), trigger `tossKey` (throws the key up and catches it),
trigger `envelope` (takes a letter, opens it with its eyes shut, files it in
the vault). New ids start at 0:540 (0:520-0:533 belong to X8b, spec §H).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
src = (ROOT / 'mascot/capy/scene.rml').read_text()
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

EASE = '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>'
OUT_ = '<CubicEaseInterpolator x1="0.2" y1="0.6" x2="0.4" y2="1"/>'   # fast start, soft land
IN_ = '<CubicEaseInterpolator x1="0.6" y1="0" x2="0.8" y2="0.4"/>'    # gravity
INTERP = {'cubic': EASE, 'out': OUT_, 'in': IN_}
INK, EYE, BODY, WHITE, GOLD = 'FF5C3B28', 'FF3A2E22', 'FFC6894F', 'FFFFFFFF', 'FFE8A21D'
WATER, RIPPLE, BLUSH = 'FFA9DCD6', 'FF7FC4BC', 'FFE8946A'
X, Y, ROT, SX, SY, OP = 13, 14, 15, 16, 17, 18


def kf(frame, value, interp='cubic'):
    if interp == 'hold' or interp == 'linear':
        return f'<KeyFrameDouble value="{value:.4f}" frame="{frame}" interpolationType="{interp}"/>'
    return (f'<KeyFrameDouble value="{value:.4f}" frame="{frame}" interpolationType="cubic">'
            f'{INTERP[interp]}</KeyFrameDouble>')


def keyed(obj, props):
    body = ''.join(f'<KeyedProperty propertyKey="{p}">{"".join(kf(*k) for k in keys)}</KeyedProperty>'
                   for p, keys in props)
    return f'<KeyedObject objectId="{obj}">{body}</KeyedObject>'


def held(obj, props):
    return keyed(obj, [(p, [(0, v, 'hold')]) for p, v in props])


def once(s, old, new):
    assert s.count(old) == 1, (old[:80], s.count(old))
    return s.replace(old, new)


def stroke(w, col=INK):
    return f'<Stroke thickness="{w}" cap="round" join="round" name="S"><SolidColor colorValue="{col}" name="C"/></Stroke>'


def fill(col):
    return f'<Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill>'


def rect(w, h, r=0, x=0, y=0):
    return (f'<Rectangle x="{x:.2f}" y="{y:.2f}" width="{w}" height="{h}" cornerRadiusTL="{r}" '
            'originX="0.5" originY="0.5" name="Path"/>')


def ell(w, h, x=0, y=0):
    return f'<Ellipse x="{x:.2f}" y="{y:.2f}" width="{w}" height="{h}" originX="0.5" originY="0.5" name="Path"/>'


def poly(pts, closed=True):
    v = ''.join(f'<StraightVertex x="{a:.2f}" y="{b:.2f}" radius="0"/>' for a, b in pts)
    c = 'true' if closed else 'false'
    return f'<PointsPath isClosed="{c}" isClockwise="true" name="Path">{v}</PointsPath>'


def arc(x0, x1, y, dip):
    m = (x0 + x1) / 2
    return ('<PointsPath isClosed="false" isClockwise="false" name="Path">'
            f'<StraightVertex x="{x0:.2f}" y="{y:.2f}" radius="0"/>'
            f'<CubicMirroredVertex x="{m:.2f}" y="{y + dip:.2f}" rotation="0.0000" distance="2.00"/>'
            f'<StraightVertex x="{x1:.2f}" y="{y:.2f}" radius="0"/></PointsPath>')


def shape(name, id_, paths, paint, x=0, y=0, extra=''):
    return f'<Shape x="{x}" y="{y}" name="{name}" id="{id_}"{extra}>{paths}{paint}</Shape>'


# Ids (0:520-0:533 are X8b's magnifying glass, spec §H).
V_VAULT, T_TOSS, T_ENV = '0:540', '0:541', '0:542'
VAULT, DIAL, ENV, LETTER, FLAP, SHUT = '0:543', '0:547', '0:551', '0:553', '0:555', '0:558'
A_POSE, A_TOSS, A_ENV = '0:561', '0:562', '0:563'
S_POSE, S_TOSS, S_ENV = '0:564', '0:565', '0:566'
# Front ids already in the rig.
PLACE, ACT, KEY, ARM_L, ARM_R, SPARKS, YUZU = '0:264', '0:263', '0:256', '0:250', '0:252', '0:244', '0:248'

s = src

# --- View model: pose value `vault`, triggers `tossKey` and `envelope`.
s = once(s, '<DataEnumValue key="guard" value="Guard" id="0:74"/>',
         f'<DataEnumValue key="guard" value="Guard" id="0:74"/><DataEnumValue key="vault" value="Vault" id="{V_VAULT}"/>')
s = once(s, '<ViewModelPropertyTrigger name="lookAround" id="0:515"/>',
         '<ViewModelPropertyTrigger name="lookAround" id="0:515"/>\n'
         f'        <ViewModelPropertyTrigger name="tossKey" id="{T_TOSS}"/>\n'
         f'        <ViewModelPropertyTrigger name="envelope" id="{T_ENV}"/>')
s = once(s, '<ViewModelInstanceTrigger viewModelPropertyId="0:515"/>',
         '<ViewModelInstanceTrigger viewModelPropertyId="0:515"/>\n'
         f'            <ViewModelInstanceTrigger viewModelPropertyId="{T_TOSS}"/>\n'
         f'            <ViewModelInstanceTrigger viewModelPropertyId="{T_ENV}"/>')

# --- Drawing. Eyes-shut lids: body-coloured patches over whatever eyes the
# mood shows, a closed arc and two lash ticks each (first child = on top).
shut = (f'<Node y="-124" opacity="0" name="Face_shut" id="{SHUT}">'
        + shape('Lids', '0:559', ell(13, 14, -34, 0) + ell(13, 14, 34, 0), fill(BODY))
        + shape('Shut', '0:560',
                arc(-41, -27, -2, 7) + arc(27, 41, -2, 7)
                + poly([(-41, -2), (-46, 2)], False) + poly([(-36, 3), (-38, 8)], False)
                + poly([(41, -2), (46, 2)], False) + poly([(36, 3), (38, 8)], False),
                stroke(5, EYE))
        + '</Node>')
s = once(s, '<Node name="Look" id="0:240">\n                        <DataBindContext sourcePathIds="0:40-0:50" propertyKey="13" converterId="0:512"/>',
         '<Node name="Look" id="0:240">\n                        <DataBindContext sourcePathIds="0:40-0:50" propertyKey="13" converterId="0:512"/>\n'
         '                        ' + shut)

# Envelope in the paws (under the arms, over the body). Flap hinges at its top
# edge, so scaleY -1 opens it; the letter rises from behind the front pocket.
env = (f'<Node x="0" y="-58" opacity="0" name="Envelope" id="{ENV}">'
       f'<Node y="-12" name="Flap" id="{FLAP}">'
       + shape('Seal', '0:557', ell(7, 7, 0, 0), fill(BLUSH) + stroke(2), y=13)
       + shape('FlapShape', '0:556', poly([(-21, 0), (0, 15), (21, 0)]), fill(WHITE) + stroke(3.5))
       + '</Node>'
       + shape('Front', '0:554', poly([(-21, -6), (0, 6), (21, -6), (21, 14), (-21, 14)]), fill(WHITE) + stroke(3.5))
       + shape('Letter', LETTER, rect(30, 22, 2, 0, 0) + poly([(-9, -4), (9, -4)], False) + poly([(-9, 2), (5, 2)], False),
               fill('FFFDF8EE') + stroke(2.5), y=0)
       + shape('Back', '0:552', rect(42, 28, 3, 0, 0), fill(WHITE) + stroke(3.5))
       + '</Node>\n                    ')
s = once(s, '<Node x="-4" y="-42" opacity="0" name="Key" id="0:256">',
         env + '<Node x="-4" y="-42" opacity="0" name="Key" id="0:256">')

# Vault beside the capybara (artboard root, origin at its feet), hidden
# except in pose `vault`. A chat bubble on the door is its label.
vault = (f'\n        <Node x="196" y="214" opacity="0" name="Vault" id="{VAULT}">'
         + shape('Slot', '0:549', poly([(-14, 0), (14, 0)], False), stroke(4), y=-64)
         + f'<Node y="-20" name="Dial" id="{DIAL}">'
         + shape('DialShape', '0:548', ell(11, 11) + poly([(0, 0), (0, -4)], False), fill(GOLD) + stroke(2.5))
         + '</Node>'
         + shape('Bubble', '0:546', rect(20, 13, 4, 0, -41) + poly([(-5, -35), (-8, -30), (1, -35)]),
                 fill(WHITE) + stroke(2.5))
         + shape('Door', '0:545', rect(44, 48, 5, 0, -33), fill(RIPPLE) + stroke(3))
         + shape('Box', '0:544', rect(62, 70, 9, 0, -37), fill(WATER) + stroke(5))
         + shape('VaultFeet', '0:550', ell(14, 7, -20, 0) + ell(14, 7, 20, 0), fill(INK))
         + '</Node>')
s = once(s, '''        </Node>
        <StateMachine name="Capy" id="0:201">''', '        </Node>' + vault + '''
        <StateMachine name="Capy" id="0:201">''')

# --- Poses. Every pose now places the capybara and hides the vault; `vault`
# steps it left (x 120 -> 80) and shrinks it to 0.8 so the vault fits.
def place(x, scale, vault_op):
    return held(PLACE, [(X, x), (SX, scale), (SY, scale)]) + held(VAULT, [(OP, vault_op)])


for pid in ('0:269', '0:270', '0:271', '0:272'):  # pose_none, pet, celebrate, guard
    tag = f'id="{pid}">'
    assert s.count(tag) == 1, pid
    s = s.replace(tag, tag + '\n            ' + place(120, 1, 0))
pose_vault = (f'        <LinearAnimation duration="1" name="pose_vault" id="{A_POSE}">\n            '
              + place(80, 0.8, 1)
              + held(ARM_L, [(ROT, -0.23)]) + held(ARM_R, [(ROT, 0.23)]) + held(KEY, [(OP, 0)])
              + held(SPARKS, [(OP, 0)]) + held(YUZU, [(Y, -184)])
              + '\n        </LinearAnimation>\n')
s = once(s, '        <LinearAnimation duration="60" name="wave" id="0:273">',
         pose_vault + '        <LinearAnimation duration="60" name="wave" id="0:273">')
# Reduced motion: the step-aside is a cut, not a 0.4 s glide (F3), so the
# instant transition is listed first and wins.
def to_vault(duration, reduced):
    return (f'<StateTransition stateToId="{S_POSE}" duration="{duration}"><TransitionViewModelCondition>'
            '<TransitionPropertyViewModelComparator><BindablePropertyEnum><DataBindContext sourcePathIds="0:40-0:42" '
            'propertyKey="637"/></BindablePropertyEnum></TransitionPropertyViewModelComparator>'
            f'<TransitionValueEnumComparator value="{V_VAULT}"/></TransitionViewModelCondition>'
            '<TransitionViewModelCondition><TransitionPropertyViewModelComparator><BindablePropertyBoolean>'
            '<DataBindContext sourcePathIds="0:40-0:44" propertyKey="634"/></BindablePropertyBoolean>'
            '</TransitionPropertyViewModelComparator>'
            f'<TransitionValueBooleanComparator value="{str(reduced).lower()}"/></TransitionViewModelCondition>'
            '</StateTransition>')


pose_tr = to_vault(0, True) + to_vault(400, False)
s = once(s, '<TransitionValueEnumComparator value="0:74"/></TransitionViewModelCondition></StateTransition></AnyState>',
         '<TransitionValueEnumComparator value="0:74"/></TransitionViewModelCondition></StateTransition>'
         + pose_tr + '</AnyState>')
s = once(s, '<AnimationState x="720" y="0" animationId="0:272" id="0:295"></AnimationState>',
         '<AnimationState x="720" y="0" animationId="0:272" id="0:295"></AnimationState>\n'
         f'                <AnimationState x="900" y="0" animationId="{A_POSE}" id="{S_POSE}"></AnimationState>')

# --- tossKey (1.0 s): crouch, spring, the key flies up spinning twice, sparks,
# arms up, it falls back into the paws, small bounce.
toss = (f'        <LinearAnimation duration="60" name="tosskey" id="{A_TOSS}">\n            '
        + keyed(ACT, [(Y, [(0, 0), (6, 4), (14, -10), (24, 0), (46, 0), (52, -4), (60, 0, 'hold')]),
                      (SY, [(0, 1), (6, 0.92), (14, 1.05), (24, 1), (60, 1, 'hold')])])
        + keyed(KEY, [(X, [(0, -4, 'hold'), (8, -4, 'out'), (18, 62), (28, 70, 'in'), (38, 58), (46, -4), (60, -4, 'hold')]),
                      (Y, [(0, -42, 'hold'), (8, -42, 'out'), (28, -190, 'in'), (46, -42), (60, -42, 'hold')]),
                      (ROT, [(0, 0, 'hold'), (8, 0, 'linear'), (46, 12.5664, 'hold'), (60, 12.5664, 'hold')]),
                      (OP, [(0, 1, 'hold'), (60, 1, 'hold')])])
        + keyed(ARM_L, [(ROT, [(0, -0.23, 'hold'), (8, -0.23), (16, 3.06), (36, 3.06), (46, -0.23), (60, -0.23, 'hold')])])
        + keyed(ARM_R, [(ROT, [(0, 0.23, 'hold'), (8, 0.23), (16, -3.06), (36, -3.06), (46, 0.23), (60, 0.23, 'hold')])])
        + keyed(SPARKS, [(OP, [(0, 0, 'hold'), (24, 0), (30, 1), (40, 1), (50, 0), (60, 0, 'hold')])])
        + '\n        </LinearAnimation>\n')

# --- envelope (1.5 s): flies in from the top left into the paws, eyes shut and
# a small turn away, the flap opens and the letter peeks, closes, eyes open,
# it arcs into the vault slot, the vault squashes and its dial turns.
EX, EY = 145, -88  # the slot, in the capybara's own (0.8-scaled) space
envelope = (f'        <LinearAnimation duration="90" name="envelope" id="{A_ENV}">\n            '
            + keyed(ENV, [(X, [(0, -130, 'out'), (16, 0, 'hold'), (50, 0), (61, 100), (72, EX), (90, EX, 'hold')]),
                          (Y, [(0, -200, 'out'), (16, -58, 'hold'), (50, -58, 'out'), (61, -150, 'in'), (72, EY), (90, EY, 'hold')]),
                          (ROT, [(0, -0.6, 'out'), (16, 0, 'hold'), (50, 0), (72, 0.5), (90, 0.5, 'hold')]),
                          (SX, [(0, 1, 'hold'), (50, 1), (72, 0.55), (90, 0.55, 'hold')]),
                          (SY, [(0, 1, 'hold'), (50, 1), (72, 0.55), (90, 0.55, 'hold')]),
                          (OP, [(0, 0), (4, 1, 'hold'), (69, 1), (72, 0, 'hold'), (90, 0, 'hold')])])
            + keyed(SHUT, [(OP, [(0, 0, 'hold'), (18, 0), (21, 1, 'hold'), (44, 1), (47, 0, 'hold'), (90, 0, 'hold')])])
            + keyed(ACT, [(ROT, [(0, 0, 'hold'), (18, 0), (24, -0.09), (42, -0.09), (48, 0), (90, 0, 'hold')])])
            + keyed(FLAP, [(SY, [(0, 1, 'hold'), (22, 1), (30, -1), (38, -1), (46, 1), (90, 1, 'hold')])])
            + keyed(LETTER, [(Y, [(0, 0, 'hold'), (26, 0), (32, -22), (38, -22), (44, 0), (90, 0, 'hold')])])
            + keyed(VAULT, [(SY, [(0, 1, 'hold'), (72, 1), (76, 0.9), (81, 1.05), (86, 1), (90, 1, 'hold')]),
                            (SX, [(0, 1, 'hold'), (72, 1), (76, 1.08), (81, 0.97), (86, 1), (90, 1, 'hold')])])
            + keyed(DIAL, [(ROT, [(0, 0, 'hold'), (74, 0), (81, 1.6), (88, 0), (90, 0, 'hold')])])
            + '\n        </LinearAnimation>\n')
s = once(s, '        <LinearAnimation duration="1" name="mood_chill" id="0:278">',
         toss + envelope + '        <LinearAnimation duration="1" name="mood_chill" id="0:278">')

# Rest holds everything only the Action layer moves (learning 2026-11-10).
s = once(s, '<LinearAnimation duration="1" name="rest" id="0:299">',
         '<LinearAnimation duration="1" name="rest" id="0:299">\n            '
         + held(KEY, [(X, -4), (ROT, 0)])
         + held(ENV, [(X, 0), (Y, -58), (ROT, 0), (SX, 1), (SY, 1), (OP, 0)])
         + held(SHUT, [(OP, 0)]) + held(FLAP, [(SY, 1)]) + held(LETTER, [(Y, 0)])
         + held(VAULT, [(SX, 1), (SY, 1)]) + held(DIAL, [(ROT, 0)]))


def trigger_tr(state_id, trigger_id):
    return (f'<StateTransition stateToId="{state_id}" duration="60"><TransitionViewModelCondition>'
            f'<TransitionPropertyViewModelComparator><BindablePropertyTrigger><DataBindContext '
            f'sourcePathIds="0:40-{trigger_id}" propertyKey="686"/></BindablePropertyTrigger>'
            '</TransitionPropertyViewModelComparator><TransitionValueTriggerComparator/>'
            '</TransitionViewModelCondition><TransitionViewModelCondition>'
            '<TransitionPropertyViewModelComparator><BindablePropertyBoolean><DataBindContext '
            'sourcePathIds="0:40-0:44" propertyKey="634"/></BindablePropertyBoolean>'
            '</TransitionPropertyViewModelComparator><TransitionValueBooleanComparator value="false"/>'
            '</TransitionViewModelCondition></StateTransition>')


def one_shot(x, y, anim, state):
    return (f'<AnimationState x="{x}" y="{y}" animationId="{anim}" reset="true" id="{state}">'
            '<StateTransition stateToId="0:304" duration="150" enableExitTime="true" '
            'exitTimeIsPercetange="true" exitTime="100"></StateTransition></AnimationState>')


s = once(s, '<StateTransition stateToId="0:309" duration="60">',
         trigger_tr(S_TOSS, T_TOSS) + trigger_tr(S_ENV, T_ENV) + '<StateTransition stateToId="0:309" duration="60">')
s = once(s, '<AnimationState x="360" y="120" animationId="0:274" reset="true" id="0:309">',
         one_shot(720, 120, A_TOSS, S_TOSS) + '\n                ' + one_shot(900, 120, A_ENV, S_ENV)
         + '\n                <AnimationState x="360" y="120" animationId="0:274" reset="true" id="0:309">')

(out / 'scene.rml').write_text(s)
(out / 'rive.yaml').write_text((ROOT / 'mascot/capy/rive.yaml').read_text())
print('wrote', out / 'scene.rml')
