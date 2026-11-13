#!/usr/bin/env zsh
# Renders the phase 5 rig (mascot/capy, R11 applied at build 5a) on the app's light and dark page colours (CLI captures are opaque).
#   zsh docs/design/mascot/phase5/render.sh <scratch-dir>
# Writes <scratch-dir>/<bg>/out/*.png for bg in light, dark.
set -e
here=${0:A:h}; tmp=${1:?scratch dir}
typeset -A bgs=(light FFFAF7F1 dark FF171512)
for name col in ${(kv)bgs}; do
  d=$tmp/$name; mkdir -p $d
  rm -rf $d/rig; cp -r $here/../../../../mascot/capy $d/rig; rm -rf $d/rig/build
  for p in rig; do
    python3 - $d/$p/scene.rml $col <<'PY'
import re, sys
p, col = sys.argv[1], sys.argv[2]
s = open(p).read()
bg = (f'<Shape x="120" y="120" name="BG"><Rectangle width="240" height="240" name="R"/>'
      f'<Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill></Shape>\n        ')
s = re.sub(r'(\n        )(<StateMachine )', lambda m: m.group(1) + bg + m.group(2), s)
open(p, 'w').write(s)
PY
    mkdir -p $d/out
    (cd $d && ~/.rive/bin/rive $p --commands=$here/$p.commands --viewport=240x240 --fit=contain >/dev/null) \
      || { (cd $d && ~/.rive/bin/rive $p --verify 2>&1 | tail -8); exit 1; }
  done
done
