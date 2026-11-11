"""Phase 3 rig additions (Page 10 mascot, spec docs/design/pages/mascot.md §G).

Drafting tool for the spec: reads mascot/capy/scene.rml, writes a patched copy
to OUT/scene.rml so the new animations can be rendered headless before PASS.
After PASS the implementation applies the same edits to mascot/capy/scene.rml
by hand (the rig is hand-edited, spec §C) and this script is retired.

    python3 docs/design/mascot/phase3/apply_phase3.py <out-dir>

Adds: eased lookX on Front (±10) and Head (G1), Front `swapKey` one-shot (G3),
Sit `lookAround` one-shot (G5). New ids start at 0:511.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
src = (ROOT / 'mascot/capy/scene.rml').read_text()
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

CUBIC = '<CubicEaseInterpolator x1="0.42" y1="0" x2="0.58" y2="1"/>'


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


def trigger_transition(state_id, trigger_id):
    return (f'<StateTransition stateToId="{state_id}" duration="60"><TransitionViewModelCondition>'
            f'<TransitionPropertyViewModelComparator><BindablePropertyTrigger><DataBindContext '
            f'sourcePathIds="0:40-{trigger_id}" propertyKey="686"/></BindablePropertyTrigger>'
            '</TransitionPropertyViewModelComparator><TransitionValueTriggerComparator/>'
            '</TransitionViewModelCondition><TransitionViewModelCondition>'
            '<TransitionPropertyViewModelComparator><BindablePropertyBoolean><DataBindContext '
            'sourcePathIds="0:40-0:44" propertyKey="634"/></BindablePropertyBoolean>'
            '</TransitionPropertyViewModelComparator><TransitionValueBooleanComparator value="false"/>'
            '</TransitionViewModelCondition></StateTransition>')


def one_shot_state(x, y, anim_id, state_id, rest_id):
    return (f'<AnimationState x="{x}" y="{y}" animationId="{anim_id}" reset="true" id="{state_id}">'
            f'<StateTransition stateToId="{rest_id}" duration="150" enableExitTime="true" '
            'exitTimeIsPercetange="true" exitTime="100"></StateTransition></AnimationState>')


s = src

# G1: lookX eased over 0.2 s; Front face shift ±6 -> ±10 so it reads at 72 dp.
s = once(s, 'minOutput="-6" maxOutput="6" clampLower="true" clampUpper="true" name="LookToX"',
         'minOutput="-10" maxOutput="10" clampLower="true" clampUpper="true" name="LookToX"')
s = once(s, '<DataConverterInterpolator interpolationType="linear" duration="0.35" name="Ease" id="0:498"/>',
         '<DataConverterInterpolator interpolationType="linear" duration="0.35" name="Ease" id="0:498"/>\n'
         '    <DataConverterInterpolator interpolationType="linear" duration="0.2" name="LookEase" id="0:511"/>\n'
         '    <DataConverterGroup name="LookToXEased" id="0:512"><DataConverterGroupItem converterId="0:496"/>'
         '<DataConverterGroupItem converterId="0:511"/></DataConverterGroup>\n'
         '    <DataConverterGroup name="LookToTiltEased" id="0:513"><DataConverterGroupItem converterId="0:497"/>'
         '<DataConverterGroupItem converterId="0:511"/></DataConverterGroup>')
s = once(s, 'sourcePathIds="0:40-0:50" propertyKey="13" converterId="0:496"',
         'sourcePathIds="0:40-0:50" propertyKey="13" converterId="0:512"')
s = once(s, 'sourcePathIds="0:40-0:50" propertyKey="15" converterId="0:497"',
         'sourcePathIds="0:40-0:50" propertyKey="15" converterId="0:513"')

# View model: two new triggers.
s = once(s, '<ViewModelPropertyTrigger name="flush" id="0:52"/>',
         '<ViewModelPropertyTrigger name="flush" id="0:52"/>\n'
         '        <ViewModelPropertyTrigger name="swapKey" id="0:514"/>\n'
         '        <ViewModelPropertyTrigger name="lookAround" id="0:515"/>')
s = once(s, '<ViewModelInstanceTrigger viewModelPropertyId="0:52"/>',
         '<ViewModelInstanceTrigger viewModelPropertyId="0:52"/>\n'
         '            <ViewModelInstanceTrigger viewModelPropertyId="0:514"/>\n'
         '            <ViewModelInstanceTrigger viewModelPropertyId="0:515"/>')

# G3: Front swapKey (0.9 s). The held key drops and fades, a new one rises
# from above into the paws, sparks flash, a small bounce. Front Key = 0:256
# (y -42), CelebSparks = 0:244, Act = 0:263.
swap = ('        <LinearAnimation duration="54" name="swapkey" id="0:516">\n            '
        + keyed('0:256', [
            (14, [(0, -42), (14, -14, 'hold'), (15, -70), (30, -42), (54, -42, 'hold')]),
            (18, [(0, 1, 'hold'), (6, 1), (14, 0, 'hold'), (16, 0), (28, 1), (54, 1, 'hold')]),
        ])
        + keyed('0:244', [(18, [(0, 0, 'hold'), (26, 0), (32, 1), (50, 0), (54, 0, 'hold')])])
        + keyed('0:263', [(14, [(0, 0, 'hold'), (28, 0), (34, -6), (42, 0), (54, 0, 'hold')])])
        + '\n        </LinearAnimation>\n')
s = once(s, '        <LinearAnimation duration="1" name="mood_chill" id="0:278">',
         swap + '        <LinearAnimation duration="1" name="mood_chill" id="0:278">')
# Rest holds what only the Action layer animates (learning 2026-11-10): Key y.
s = once(s, '<LinearAnimation duration="1" name="rest" id="0:299">',
         '<LinearAnimation duration="1" name="rest" id="0:299">\n            '
         + keyed('0:256', [(14, [(0, -42, 'hold')])]))
s = once(s, '<StateTransition stateToId="0:309" duration="60">',
         trigger_transition('0:517', '0:514') + '<StateTransition stateToId="0:309" duration="60">')
s = once(s, '<AnimationState x="360" y="120" animationId="0:274" reset="true" id="0:309">',
         one_shot_state(540, 120, '0:516', '0:517', '0:304')
         + '\n                <AnimationState x="360" y="120" animationId="0:274" reset="true" id="0:309">')

# G5: Sit lookAround (1.6 s). Turns to look the other way (scaleX through 0,
# the 2D-cartoon turn), turns back, small shrug bob. Sit Act = 0:163.
look = ('        <LinearAnimation duration="96" name="lookaround" id="0:518">\n            '
        + keyed('0:163', [
            (16, [(0, 1, 'hold'), (20, 1), (26, -1, 'hold'), (58, -1), (64, 1, 'hold'), (96, 1, 'hold')]),
            (17, [(0, 1, 'hold'), (20, 1), (23, 0.95), (26, 1, 'hold'), (58, 1), (61, 0.95), (64, 1, 'hold'),
                  (72, 1), (77, 1.04), (84, 1), (96, 1, 'hold')]),
            (14, [(0, 0, 'hold'), (72, 0), (77, -5), (84, 0), (96, 0, 'hold')]),
        ])
        + '\n        </LinearAnimation>\n')
s = once(s, '        <LinearAnimation duration="1" name="mood_chill" id="0:173">',
         look + '        <LinearAnimation duration="1" name="mood_chill" id="0:173">')
s = once(s, '<StateTransition stateToId="0:198" duration="60">',
         trigger_transition('0:519', '0:515') + '<StateTransition stateToId="0:198" duration="60">')
s = once(s, '<AnimationState x="180" y="120" animationId="0:169" reset="true" id="0:198">',
         one_shot_state(360, 120, '0:518', '0:519', '0:194')
         + '\n                <AnimationState x="180" y="120" animationId="0:169" reset="true" id="0:198">')

(out / 'scene.rml').write_text(s)
(out / 'rive.yaml').write_text((ROOT / 'mascot/capy/rive.yaml').read_text())
print('wrote', out / 'scene.rml')
