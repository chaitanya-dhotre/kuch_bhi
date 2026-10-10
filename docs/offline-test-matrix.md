# Offline Test Matrix — Task 11 (P6 device batch)

Executed 2026-10-09 on emulator-5554 (sdk gphone16k x86_64), app `com.chai.kuch_bhi`,
logged in as minato. Network control: `adb shell cmd connectivity airplane-mode enable|disable`.
Captures: `docs/captures/t11-*.png`. FCM intentionally out of scope (FIS_AUTH_ERROR env).

Legend: PASS = executed + verified. PARTIAL = steps ran, gap recorded. BLOCKED = could not execute (reason + prepared commands).

---

## Row 1 — Airplane render-from-DB + send queues

| Step | Expected | Actual | Capture |
|---|---|---|---|
| 1. Airplane ON, open home | Home renders from DB (no spinner hang) | Home renders full chat list offline | `t11-row1-1-home-offline.png` |
| 2. Open Lineage Chait | History renders from DB | Messages + media history render | `t11-row1-2-chat-offline.png` |
| 3. Search | Offline search over local index | Results from DB | `t11-row1-3-search-offline.png` |
| 4. Send 3 texts offline | Each row `queued` in outbox + UI pending | 4 sends queued (outbox_table state=queued); UI pending ticks | `t11-row1-4-send-queued.png` |

**Row verdict: PASS**

---

## Row 2 — Kill mid-queue

| Step | Expected | Actual | Capture |
|---|---|---|---|
| 1. 4 msgs queued offline | 4 queued rows | 4 `queued` ops in `outbox_table` | `t11-row2-1-4queued-before-kill.png` |
| 2. `am force-stop`, relaunch OFFLINE | 4 rows still `queued`; any `sending` janitor-reset to `queued` | 4 still `queued` after relaunch; janitor OK | `t11-row2-2-relaunch-offline-4queued.png` |
| 3. Reconnect | All 4 send, one bubble each, no dups vs server | **FAIL (ledgered):** 4 ops stuck `queued` attempts=0 forever. Root cause: T9 plaintext `bodyCache` is process-local; kill loses plaintext → `_sendTextOp` → `OpSendOutcome.deferred` (message_repository_impl.dart:891-894). Server count for dc4kebcr today = 0 (no dups, no partials). Differential control: warm-process send in other conv SENT (`pk7h3ym2ef2l9eu`, server REST = 1) proving drain path itself works | `t11-row2-3-warm-cache-sent.png` |

Final outbox snapshot (post-session DB pull): dc4kebcr72v9w80 = 5 queued (attempts=0), urln1octipvgco7 = 1 sent.

**Row verdict: PARTIAL — survival+janitor PASS; reconnect-drain FAIL, root-caused to ledgered T9.7/T2 encryption-at-enqueue forward-carry (out of scope to fix).**

### Row 2 re-run (C1 fix, HEAD 6ab2d50, 2026-10-10) — encrypt-at-enqueue

Conv: "Lineage Chait" (key-present DM). Msgs: `killcase-a101/b102/c103`.

| Step | Expected | Actual | Capture |
|---|---|---|---|
| a-f. Airplane ON → 3 msgs queued → `am force-stop` → relaunch OFFLINE → reopen conv | 3 rows survive `queued`, one bubble each, no placeholder, no dupes | 3 `content-desc="killcase-*"` nodes; bubbles re-decrypted from row ciphertext (C1 path); all 3 queued icons; status bar airplane | `t11-c1row2-1-queued-offline.png`, `t11-c1row2-2-survived-kill-offline.png` |
| g-i. Airplane OFF → drain → verify | All 3 SENT, one bubble each | 3 nodes exactly; all 3 double-tick ✓✓ @15:59 (server-acked); no dupes, no placeholder | `t11-c1row2-3-reconnect-drained.png` |

**Row 2 re-run verdict: PASS** — kill-gap loss window closed by encrypt-at-enqueue (spec §5.2, commit 6ab2d50).

---

## Row 3 — Long-gap reconnect (peer msgs accumulate)

Blocked: single attached device. `cmd connectivity airplane-mode` is device-global — no second live client can send peer messages while this device is offline; no second physical phone attached (`adb devices` = emulator only).

Prepared commands for re-run with 2 devices (A = DUT, B = peer):
```zsh
# A offline; B sends 5 msgs in shared DM; wait 10+ min
adb -s <A> shell cmd connectivity airplane-mode enable
# B: send msgs via app
adb -s <A> shell cmd connectivity airplane-mode disable
# verify: catch-up applies once; message_table count == server REST count;
# cursor gap_check: no skipped ids between pre-offline max and catch-up batch
```

**Row verdict: BLOCKED-single-device**

---

## Row 4 — Key-delay placeholder (T7) + terminal banner (T4)

| Step | Expected | Actual | Capture |
|---|---|---|---|
| 1. Key-missing group | List shows 🔒 + skeleton preview, not plaintext | 7 group rows show 🔒 + grey skeleton preview | `t11-row4-2-key-previews-home.png` |
| 2. Open key-wait group | Empty chat + "Waiting for a group admin..." note | Test group: empty + waiting note rendered | `t11-row4-1-key-wait-empty-chat.png` |
| 3. Own-pending body placeholder | `_BodyPlaceholder` locks on pending | Seen in relaunch capture (row2-2) | (covered by `t11-row2-2-relaunch-offline-4queued.png`) |
| 4. Terminal failure banner (T4) | Banner on failedTerminal ops | No natural solo trigger in batch window (needs auth-expiry / max-retry terminal). Not faked | — |

Prepared repro for banner: revoke/invalidate auth token → send+reconnect → drain 401 → `outbox_pause=auth` / failedTerminal → banner path (`outbox_status_provider`).

**Row verdict: PARTIAL — T7 placeholders PASS; T4 banner BLOCKED-no-natural-trigger (unit-covered per ledger).**

---

## Row 5 — Media download → airplane → cached → delete → reconnect re-fetch

| Step | Expected | Actual | Capture |
|---|---|---|---|
| 1. Online: image visible | Thumb cached in `cache/media_clear/` + dao ready | Downloaded; files on disk | `t11-row5-1-download-online.png` |
| 2. Airplane, view | Cached blob renders | Renders (warm ImageCache noted) | `t11-row5-2-cached-offline.png` |
| 3. Delete cache files, cold restart | Placeholder (broken_image) | Both image files deleted via run-as; cold restart → placeholder bubble | `t11-row5-3-cache-deleted-placeholder.png` |
| 4. Reconnect | Re-fetch restores media | Thumb re-downloaded 11:57 (2972 B); full re-downloaded 12:08 (36965 B); bubble renders re-fetched thumb; viewer shows re-fetched full | `t11-row5-4-reconnect-refetch-render.png`, `t11-row5-5-full-viewer-refetch.png` |

Note: in warm process (no restart) the bubble stayed on placeholder after re-fetch — `mediaFileProvider` (non-autoDispose FutureProvider) had cached the earlier `null`. Cold restart rebuilds → renders. Observation for backlog, not fixed here.

**Row verdict: PASS**

---

## Summary

| Row | Verdict |
|---|---|
| 1 Airplane render + queue | PASS |
| 2 Kill mid-queue | PASS (re-run 2026-10-10 @6ab2d50; original run PARTIAL, root-caused + fixed via encrypt-at-enqueue) |
| 3 Long-gap reconnect | BLOCKED-single-device |
| 4 Key-delay + terminal banner | PARTIAL (T7 PASS; T4 banner blocked-no-trigger) |
| 5 Media lifecycle | PASS |
