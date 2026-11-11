---
title: Two sessions building mascot features in one checkout commit separately by staging single-feature copies of the shared files
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 11, tokens: 91370 }
id: l-08289a18
scope: repo
status: active
src: agent
touches:
  - assets/mascot/capy.riv
  - docs/design/mascot/search/apply_search.py
  - docs/design/mascot/search/frames.commands
  - docs/design/mascot/search/frames.png
  - docs/design/mascot/search/render.sh
  - docs/design/pages/mascot-work-log.md
  - docs/design/pages/mascot.html
  - docs/design/pages/mascot.md
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/mascot/capy.dart
---

## Decided
- X8b (search) and K1b (restore) were built at the same time in one checkout and changed the same files (the Capy widget, its tests, the rig source, the published .riv, the mascot spec, html and work log). The rule here is one commit per feature after its device PASS, so X8b's commit was staged as X8b-only versions of those shared files, written straight into the git index, while the working tree kept both features. The other feature's commit then diffs only its own parts on top.
- The X8b-only rig was rebuilt from HEAD's scene with the feature's patch script, and republished on its own; the .riv can't be split any other way.
- Before committing, the staged tree was exported and the full suite run there, to prove the commit builds without the other feature.

## Watch out
- Tell the other session before staging: its git add or commit would sweep up, or reset, your staged blobs.
- The suite run in an exported (non-git) folder fails exactly one test, the git-ignore grep gate, because it shells out to git. Trust that one only in the real repo.
- `rive <project> --publish --output-dir=assets/mascot` resolves the output dir under the project folder (mascot/capy/assets/...), not the repo root. Pass an absolute path or move the file.

In the code: `git hash-object -w <file>` + `git update-index --add --cacheinfo 100644,<hash>,<path>`; `git checkout-index -a --prefix=<dir>/` to export the index; docs/design/mascot/search/apply_search.py run against `git show HEAD:mascot/capy/scene.rml`; test/grep_gates_test.dart (git-ignore gate).
