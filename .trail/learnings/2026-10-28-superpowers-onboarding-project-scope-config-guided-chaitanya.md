---
title: "Superpowers onboarding: project-scope config, guided subagent model routing, gate+wait-guard hooks on"
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 7, tokens: 673919 }
id: l-748c71de
scope: repo
status: active
src: agent
touches:
  - CLAUDE.md
  - docs/agents/issue-tracker.md
  - docs/agents/triage-labels.md
  - docs/agents/domain.md
  - docs/superpowers/model-routing.json
---

## Decided
Superpowers onboarding ran at project scope: routing is guided tiers (haiku/sonnet/inherit) with automatic effort and choose-per-plan parallel handoff, because this is a solo solo-friendly repo where routine subagent tasks don't need frontier pricing; user-thrown gate enforcement hooks (PostToolUse + Stop) and the plan-execution wait guard are registered because plan execution historically stalled on "waiting" turn-ends and unproven gate closes. Commit strategy stays per-task (default) and the visual companion stays just-in-time, because defaults fit and writing files for defaults only adds config surface.

## Tried and ruled out
- User-level scope — dropped because config should apply to this repo only, not every project on the machine.
- Pin-and-enforce effort — dropped because no effort-pinned agent definitions exist yet, so enforcement would block all dispatches.
- Single commit at plan end — dropped because per-task commits give per-task rollback on a two-device tested messaging app.

## Watch out
- The wait-guard Stop hook is project-scope only: parallel executor sessions running in other directories won't inherit it; mirror into ~/.claude/settings.json if that bites.
- Native task tools were already enabled, so no env write was needed.
- Onboarding wrote into the same working tree as the mattpocock-skills setup; both remain uncommitted.

In the code:
- `docs/superpowers/model-routing.json` (tier map), `.claude/settings.json` (hooks.PostToolUse + hooks.Stop entries and permissions.deny EnterPlanMode), `~/.claude/settings.json` (hooks.SessionStart check-onboard-drift entry; autoUpdate was already true).
