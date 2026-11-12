#!/usr/bin/env zsh
# Renders every sticker on white and on black (CLI captures are opaque), then matte.py
# recovers the alpha and adds the white die-cut edge.
#   zsh docs/design/mascot/stickers/render.sh <scratch-dir> [px]
# Writes <scratch-dir>/png/<id>.png (transparent, px square, default 384) and png/_sheet.png.
set -e
here=${0:A:h}; tmp=${1:?scratch dir}; px=${2:-384}
ids=($(python3 $here/apply_stickers.py $tmp/src))
for id in $ids; do
  for name col in white FFFFFFFF black FF000000; do
    d=$tmp/$name; mkdir -p $d/out; rm -rf $d/rig; cp -r $tmp/src/$id/rig $d/rig
    python3 - $d/rig/scene.rml $col <<'PY'
import re, sys
p, col = sys.argv[1], sys.argv[2]
s = open(p).read()
bg = (f'<Shape x="120" y="120" name="BG"><Rectangle width="300" height="300" name="R"/>'
      f'<Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill></Shape>\n        ')
s = re.sub(r'(\n        )(<StateMachine )', lambda m: m.group(1) + bg + m.group(2), s)
open(p, 'w').write(s)
PY
    (cd $d && ~/.rive/bin/rive rig --commands=$tmp/src/$id/frame.commands --viewport=${px}x${px} --fit=contain >/dev/null 2>&1) \
      || { echo "render failed: $id"; (cd $d && ~/.rive/bin/rive rig --verify 2>&1 | tail -5); exit 1; }
  done
done
python3 $here/matte.py $tmp $tmp/png 6
