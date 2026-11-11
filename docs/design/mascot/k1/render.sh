#!/usr/bin/env zsh
# Renders the K1 redesign frames on the app's backgrounds (CLI captures are opaque).
#   zsh docs/design/mascot/k1/render.sh <scratch-dir>
# Writes <scratch-dir>/<bg>/out/*.png for bg in light, dark.
set -e
here=${0:A:h}; tmp=${1:?scratch dir}
typeset -A bgs=(light FFFAF7F1 dark FF171512)
for name col in ${(kv)bgs}; do
  d=$tmp/$name; mkdir -p $d/out
  python3 $here/apply_k1.py $d/rig >/dev/null
  # Background rectangle as each artboard's bottom-most child.
  python3 - $d/rig/scene.rml $col <<'PY'
import re, sys
p, col = sys.argv[1], sys.argv[2]
s = open(p).read()
bg = (f'<Shape x="120" y="120" name="BG"><Rectangle width="240" height="240" name="R"/>'
      f'<Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill></Shape>\n        ')
s = re.sub(r'(\n        )(<StateMachine )', lambda m: m.group(1) + bg + m.group(2), s)
open(p, 'w').write(s)
PY
  (cd $d && ~/.rive/bin/rive rig --commands=$here/frames.commands --viewport=240x240 --fit=contain >/dev/null)
done
