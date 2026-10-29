---
title: "Engineering skills track work in GitHub Issues for this repo, canonical triage labels"
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-1189b3ff
scope: repo
status: active
src: agent
touches:
  - pubspec.yaml
---

## Decided
Per-repo config for Matt Pocock's engineering skills: issues live in GitHub Issues (repo inferred from git remote via `gh` CLI), the five canonical triage labels are kept as-is, and domain docs are single-context — because the repo has a GitHub remote and no monorepo signals. Config is pointed to from `CLAUDE.md` ("## Agent skills" section).

## Tried and ruled out
- Local markdown under .scratch/<feature>/ — dropped because the repo already has a GitHub remote (skills are GitHub-first otherwise).
- Custom label vocabulary — dropped because no existing label scheme exists to preserve; defaults avoid duplicate labels.
- Multi-context GLOSSARY-MAP — dropped because this is a single Flutter app (pubspec.yaml, no package.json workspaces).

## Watch out
- CLAUDE.md was empty before setup; the Agent skills block is the first content in it.
- PRs as a triage/request surface is explicitly off in `docs/agents/issue-tracker.md`.

In the code:
- Config lives in `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`; the pointer block in `CLAUDE.md` under "## Agent skills".
