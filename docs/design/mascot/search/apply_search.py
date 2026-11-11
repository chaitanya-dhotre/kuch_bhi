"""Searching pose (Page 10 mascot, spec docs/design/pages/mascot.md §H).

Drafting tool for the spec: reads mascot/capy/scene.rml, writes a patched copy
to OUT/scene.rml so the pose can be rendered headless before PASS. After PASS
the same edits go into mascot/capy/scene.rml by hand and this script retires.

    python3 docs/design/mascot/search/apply_search.py <out-dir>

Adds (R4): pose enum value `search`; on Sit a magnifying glass in the near
front paw, raised to the eye, and a Pose layer: `pose_search` sweeps the glass
in a slow 2 s loop, `pose_search_still` holds it centred (still or reduced
motion), `pose_none` puts the paw back down. New ids start at 0:520.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
src = (ROOT / 'mascot/capy/scene.rml').read_text()
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

CUBIC = '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>'
INK = 'FF5C3B28'


def kf(frame, value, interp='cubic'):
    body = CUBIC if interp == 'cubic' else ''
    end = f'>{body}</KeyFrameDouble>' if body else '/>'
    return (f'<KeyFrameDouble value="{value:.4f}" frame="{frame}" '
            f'interpolationType="{interp}"{end}')


def keyed(obj, prop_keys):
    props = ''.join(
        f'<KeyedProperty propertyKey="{p}">{"".join(kf(*k) for k in keys)}</KeyedProperty>'
        for p, keys in prop_keys)
    return f'<KeyedObject objectId="{obj}">{props}</KeyedObject>'


def once(s, old, new):
    assert s.count(old) == 1, (old, s.count(old))
    return s.replace(old, new)


def cond_enum(value, op=0):
    return ('<TransitionViewModelCondition' + (f' opValue="{op}"' if op else '') + '>'
            '<TransitionPropertyViewModelComparator><BindablePropertyEnum><DataBindContext '
            'sourcePathIds="0:40-0:42" propertyKey="637"/></BindablePropertyEnum>'
            f'</TransitionPropertyViewModelComparator><TransitionValueEnumComparator value="{value}"/>'
            '</TransitionViewModelCondition>')


def cond_bool(prop, value):
    return ('<TransitionViewModelCondition><TransitionPropertyViewModelComparator><BindablePropertyBoolean>'
            f'<DataBindContext sourcePathIds="0:40-{prop}" propertyKey="634"/></BindablePropertyBoolean>'
            f'</TransitionPropertyViewModelComparator><TransitionValueBooleanComparator value="{str(value).lower()}"/>'
            '</TransitionViewModelCondition>')


def to(state, *conds, duration=150):
    return f'<StateTransition stateToId="{state}" duration="{duration}">{"".join(conds)}</StateTransition>'


s = src

# Pose enum: + search (Sit only; Front's Pose layer has no transition for it).
s = once(s, '<DataEnumValue key="guard" value="Guard" id="0:74"/>',
         '<DataEnumValue key="guard" value="Guard" id="0:74"/>'
         '<DataEnumValue key="search" value="Search" id="0:520"/>')

# The near front paw moves to the front of the draw order (first child = front
# in this rig) so the raised glass sits over the face; at rest it overlaps
# nothing of the head, so the resting look is unchanged.
paw = re.search(r'\n                    <Node x="-56" y="-14" name="PawLHolder" id="0:154">.*?\n'
                r'                    </Node>', s, re.S).group(0)
s = once(s, paw, '')
wave = re.search(r'                        <Node name="PawWave" id="0:153">.*?\n'
                 r'                        </Node>', paw, re.S).group(0)
wave = '\n'.join('    ' + l for l in wave.split('\n'))
glass = f'''
                            <Node x="14" y="-48" opacity="0" name="Glass" id="0:522">
                                <Shape x="-8" y="-8" name="Glint" id="0:525">
                                    <PointsPath isClosed="false" isClockwise="false" name="Path"><StraightVertex x="-5.00" y="4.00" radius="0"/><CubicMirroredVertex x="0.00" y="-3.00" rotation="-0.6000" distance="3.00"/><StraightVertex x="6.00" y="-5.00" radius="0"/></PointsPath><Stroke thickness="3" cap="round" join="round" name="S"><SolidColor colorValue="F0FFFFFF" name="C"/></Stroke>
                                </Shape>
                                <Shape name="Lens" id="0:524">
                                    <Ellipse x="0.00" y="0.00" width="40" height="40" originX="0.5" originY="0.5" name="Path"/><Fill name="F"><SolidColor colorValue="70FFFFFF" name="C"/></Fill><Stroke thickness="5" cap="round" join="round" name="S"><SolidColor colorValue="{INK}" name="C"/></Stroke>
                                </Shape>
                                <Shape name="Handle" id="0:523">
                                    <PointsPath isClosed="false" isClockwise="false" name="Path"><StraightVertex x="-12.00" y="50.00" radius="0"/><StraightVertex x="-4.00" y="20.00" radius="0"/></PointsPath><Stroke thickness="8" cap="round" join="round" name="S"><SolidColor colorValue="{INK}" name="C"/></Stroke>
                                </Shape>
                            </Node>'''
holder = ('\n                    <Node x="-56" y="-14" name="PawLHolder" id="0:154">\n'
          '                        <Node name="Scan" id="0:521">\n'
          + wave + glass + '\n'
          '                        </Node>\n'
          '                    </Node>')
s = once(s, '\n                    <RootBone x="8" y="-24"', holder + '\n                    <RootBone x="8" y="-24"')

# Pose animations (Sit). PawLHolder 0:154, Scan 0:521, Glass 0:522.
REST = [('0:154', [(13, [(0, -56, 'hold')]), (14, [(0, -14, 'hold')]), (15, [(0, 0, 'hold')])]),
        ('0:522', [(18, [(0, 0, 'hold')])])]
UP = [('0:154', [(13, [(0, -64, 'hold')]), (14, [(0, -80, 'hold')]), (15, [(0, 0, 'hold')])]),
      ('0:522', [(18, [(0, 1, 'hold')])])]
CENTRE = [('0:521', [(13, [(0, 0, 'hold')]), (14, [(0, 0, 'hold')]), (15, [(0, 0, 'hold')])])]
# Slow scan, 2 s: left and down toward the snout, back, a little right and up.
SWEEP = [('0:521', [
    (13, [(0, 0), (30, -14), (60, 0), (90, 8), (120, 0)]),
    (14, [(0, 0), (30, 6), (60, 0), (90, -4), (120, 0)]),
    (15, [(0, 0), (30, -0.10), (60, 0), (90, 0.06), (120, 0)]),
])]


def anim(name, aid, parts, duration=1, loop=False):
    lv = ' loopValue="loop"' if loop else ''
    return (f'        <LinearAnimation duration="{duration}"{lv} name="{name}" id="{aid}">\n            '
            + ''.join(keyed(o, p) for o, p in parts) + '\n        </LinearAnimation>\n')


anims = (anim('pose_none', '0:527', REST + CENTRE)
         + anim('pose_search', '0:528', UP + SWEEP, duration=120, loop=True)
         + anim('pose_search_still', '0:529', UP + CENTRE))
s = once(s, '        <LinearAnimation duration="1" name="mood_chill" id="0:173">',
         anims + '        <LinearAnimation duration="1" name="mood_chill" id="0:173">')

# Sit Pose layer (before Props). still = 0:43, reducedMotion = 0:44.
moving = [cond_enum('0:520'), cond_bool('0:43', False), cond_bool('0:44', False)]
layer = ('            <StateMachineLayer name="Pose" id="0:530">\n'
         '                <AnyState x="0" y="-150">'
         + to('0:531', cond_enum('0:520', op=1))
         + to('0:532', *moving)
         + to('0:533', cond_enum('0:520'), cond_bool('0:43', True))
         + to('0:533', cond_enum('0:520'), cond_bool('0:44', True))
         + '</AnyState>\n'
         '                <ExitState x="160" y="-150"/>\n'
         '                <EntryState x="0" y="0"><StateTransition stateToId="0:531"></StateTransition></EntryState>\n'
         '                <AnimationState x="180" y="0" animationId="0:527" id="0:531"></AnimationState>\n'
         '                <AnimationState x="360" y="0" animationId="0:528" id="0:532"></AnimationState>\n'
         '                <AnimationState x="540" y="0" animationId="0:529" id="0:533"></AnimationState>\n'
         '            </StateMachineLayer>\n')
s = once(s, '            <StateMachineLayer name="Props" id="0:186">',
         layer + '            <StateMachineLayer name="Props" id="0:186">')

(out / 'scene.rml').write_text(s)
(out / 'rive.yaml').write_text((ROOT / 'mascot/capy/rive.yaml').read_text())
print('wrote', out / 'scene.rml')
