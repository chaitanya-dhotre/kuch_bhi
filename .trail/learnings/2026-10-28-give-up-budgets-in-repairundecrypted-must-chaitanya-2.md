---
title: Give-up budgets in _repairUndecrypted must count every exit path
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 7, tokens: 257644 }
id: l-570a8022
scope: repo
status: active
replaces: l-35065d38
src: agent
---

## Decided

A give-up budget is only real if every exit from the attempt counts as an
attempt, because the work usually bails before the end of its loop — counting
only there leaves the counter at zero forever and the guard does nothing.

## Watch out

Two tests passed with the fix disabled: one asserted only the FINAL state,
which a following rebuild corrects; one used a fake whose response changed with
the action, so the race never happened. Prove RED by breaking the fix.

## In the code

`_accountRepair` is called from every exit path of `_repairUndecrypted`
(message_repository_impl.dart), including `MissingKeyException` and `catch`.
`debugRepairRuns` is incremented AFTER the cap check, otherwise it counts
entries the budget already short-circuited. A DAO spy is impossible: its
accessor is a generated `late final` with no setter.
