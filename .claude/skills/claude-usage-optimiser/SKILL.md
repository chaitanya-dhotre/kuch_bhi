---
name: claude-usage-optimiser
description: Routes work across the three available pools — Claude Pro (judgment, scarce), Astra 6 / Sol 6.1 on ChatGPT (10M tok/day implementation), Mimo 2.6 Flash via freebuff (5h unlimited mechanical work) — so limits never stop the pipeline. Use at the START of any new task/session to decide who does what, and whenever a model's limit is hit or the user asks who should do a task. Enforces one-task-per-session and lean handoffs.
---

# Claude usage optimiser

## The pools

| Pool | Budget | Role |
|---|---|---|
| **Claude (Pro)** | shared limit, scarce | Judgment: grading, adversarial verification, races/crypto/security, PASS gates, commit messages |
| **Astra 6 / Sol 6.1** (ChatGPT) | 10M tok/day | Implementation of written specs (the established pipeline: spec + checklist → Astra implements → Claude grades). Access: **Omnirush desktop app** (`/usr/bin/omnirush`) — GUI-only, every CLI subcommand boots the desktop runtime, so dispatch is manual: the user pastes Claude's brief into the Omnirush UI. Back up 2026-11-02 (user). |
| **Mimo 2.6 Flash / DeepSeek** (freebuff) | 5h unlimited window/day | Mechanical bulk: doc/backlog edits, lint/import fixes, scaffolds, sweeps, renaming. Access: **freebuff CLI** (`/usr/bin/freebuff`, v0.2.34) — interactive TUI, NO headless `-p`/`--print` mode (confirmed 2026-10-29); dispatch = `freebuff --cwd /home/chaitanyadhotre/kuch_bhi --trust-agents` in a terminal + paste the brief. It has DIRECT repo access (reads/writes code, runs tests), unlike Omnirush models — so Mimo briefs can be thinner than Astra briefs |

## Routing table

| Work | Where | Why |
|---|---|---|
| Page/feature implementation against a spec + checklist | **Astra** | 10M tok/day; output is checkable against the checklist |
| Grading Astra output, RED→GREEN proof, PASS verdict | **Claude** | verification is the scarce skill; Astra never self-certifies |
| Races / riverpod lifecycle / crypto / E2E-crypto changes | **Claude** | this is where spec-grade work fails (H3 fence + give-up budget both died on first attempt at full attention) |
| Doc updates, backlog lines, registry rows, work-logs | **Mimo** (else Astra) | fully mechanical, spec-able in one paragraph |
| Mechanical code edits (bulk rename, import fixes, lint) | **Mimo** | unlimited window, zero judgment |
| Broad sweeps / research / reading large docs | **Astra** | never pay Claude-context for reading |
| Final commit message, security review, architecture | **Claude** | authority stays here |

## Session hygiene (one task per session — user's standing rule)

- **Session start:** read `MEMORY.md`, then ONLY the work-log / plan for THIS task. Never re-load whole docs. Use `trail ask` / `trail grep` / `trail callers` before Read or Bash.
- **Session end:** update the task's work-log (`docs/design/pages/*-work-log.md`) + memory pointer. The handoff file IS the memory — the next Claude session resumes from it.
- Before any "done" claim: `flutter test` green, `flutter analyze` 0 errors, `git diff --check`. Evidence before assertions, always.
- `/compact` before starting a large implementation session; a fresh session beats a long one for a new page.

## Handoff brief for Astra / Mimo (zero repo context)

External models know NOTHING about this repo. Every handoff must be self-contained:

1. The checklist file path + the spec file path (exact paths).
2. The exact list of files to create/modify.
3. All copy/strings verbatim (empty-state text, toasts, titles).
4. The gates THEY must run themselves (`flutter test`, `flutter analyze`).
5. One closing line: "Claude grades the result; do not claim PASS."

Delivery: hand the brief to the user as a copy-paste block. Astra/Sol → Omnirush UI (GUI-only, confirmed 2026-10-29). Mimo → `freebuff --cwd /home/chaitanyadhotre/kuch_bhi --trust-agents` terminal paste (TUI-only, no headless flag). Never re-probe either CLI for dispatch modes — both confirmed 2026-10-29. An Astra brief reused for Mimo needs no attachment list (Mimo reads the repo); paste only the part below the brief's `---` line.

## When a limit is hit (downtime protocol)

1. Write the current state into the work-log (done / proven / next step) — never leave it in chat only.
2. Mechanical leftovers → Mimo; already-specified implementation → Astra. Both can continue WITHOUT Claude.
3. Grading / PASS / commit wait for the next Claude window. The no-commit-without-PASS rule never bends.
4. If Astra is down: **Mimo implements** against the same spec + checklist (it has repo access; worked on Page 4, 2026-10-29). Claude implements directly only when both are down. If Mimo is down: its items fold to Astra.
5. When Mimo stands in for Astra, Claude's grading adds one cheap check, because Mimo is the zero-judgment tier and `--trust-agents` lets it write anywhere: diff every code path the spec freezes (e.g. E2E key code) against HEAD at function level, plus `git log` (no stray commits) and `git diff --stat` (no files outside the brief's list). Do this before reading anything else.

## Cost rules (learned the expensive way this project)

- Don't re-verify what a test already proves; trust green suites over re-reading diffs.
- One adversarial verification round per fix-wave by default — a second round only after a BLOCK.
- Never burn Claude context on whole large files: `trail skeleton` / `sed -n` ranges first.
- A question "who should do X" gets a routing answer from the table above, not analysis.
- Claude reading + Mimo writing is the right split for docs; Claude writing docs only when the doc is a verdict.
