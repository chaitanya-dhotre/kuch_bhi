# Group Invites Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the verified gaps in the group-invite flow: pre-join history cutoff (server+client), admin-resume key reconciliation, keyless-joiner UX, rejoin-after-leave fix, CM rule hardening, invite management UI, error surfacing.

**Architecture:** Server-side enforcement in PB rules (`messages` list/view, `conversation_members` update, `group_keys` list) + one VM hook edit (rejoin role flip). Client: visibility filter in the repo's row mapper, key-gap reconcile on resume, a key-readiness polling provider gating the composer, group-settings invite list, honest toasts. No Drift schema change.

**Tech Stack:** Flutter/Riverpod/Drift (client), PocketBase 0.37.5 (server), pb.js hook (VM 140.245.15.77).

## Global Constraints

- NO git commits until the user verifies on 2 devices (standing rule; Task 7 collects the single commit — do NOT run the per-task commit steps, they are shown for granularity only).
- Back-reference rules use `?=` for EVERY `@collection` clause, and multi-clause joins over ONE row must be a single `?=` expression (independent `?=` clauses match different rows — that leaks).
- `conversations.type` values are exactly `direct` and `group`.
- `flutter analyze` must be 0 errors after every client task; `flutter test` must pass after tasks that add tests.
- Server credentials: superuser password file `/home/chaitanyadhotre/Chaitanya/Oracle/pb_superuser_password_NEW.txt`, identity `chaitanyad301@proton.me`. SSH: `cd /home/chaitanyadhotre/Chaitanya/Oracle && ssh -i ssh-key-2026-04-28-1.key ubuntu@140.245.15.77`. Pipe secrets via files/env, never echo.
- PB hot-reloads `pb_hooks/*.pb.js` on change and prints `restarting...` — wait ~3s after any hook edit before probing.
- Spec: `docs/superpowers/specs/2026-10-03-group-invites-rework-design.md`.
- Test group for probes: `zrwszx3uifdjlkn` (user-created; members joined 2026-10-03 ~08:43). Old-member probe group: `hnj3vfuhjka7edo` ("4chan"). Clean up every probe row you create.

---

### Task 1: Server — messages history cutoff + CM updateRule + group_keys listRule

**Files:**
- Create: throwaway probe script under `$CLAUDE_JOB_DIR/tmp/` (runs locally, hits https://kuch-bhi.duckdns.org)

**Interfaces:**
- Produces: `messages.listRule`/`viewRule` = `(conversation_id.type = "direct" && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.conversation_id ?= conversation_id) || (conversation_id.type = "group" && @collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.created <= created)`; `conversation_members.updateRule` = `(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin" && @request.body.user_id:isset = false && @request.body.conversation_id:isset = false) || (user_id = @request.auth.id && @request.body.role:isset = false)`; `group_keys.listRule` = `@request.auth.id = user_id.id || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin")`.

- [ ] **Step 1: Write the rule-patch + probe script**

```bash
#!/usr/bin/env bash
set -u
BASE=https://kuch-bhi.duckdns.org
PW=$(cat /home/chaitanyadhotre/Chaitanya/Oracle/pb_superuser_password_NEW.txt)
TOKEN=$(curl -s -X POST "$BASE/api/collections/_superusers/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"identity":"chaitanyad301@proton.me","password":sys.argv[1]}))' "$PW")" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))')
[ -z "$TOKEN" ] && { echo AUTH_FAILED; exit 1; }
echo AUTH_OK

python3 - "$TOKEN" <<'PYEOF'
import json, sys, urllib.request
token = sys.argv[1]
BASE = "https://kuch-bhi.duckdns.org"

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
        headers={"Authorization": token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)

dm   = '@collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.conversation_id ?= conversation_id'
grp  = '@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.created <= created'
adm  = '@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin"'
msgs_rule = f'({{conversation_id.type = "direct" && {dm}}) || (conversation_id.type = "group" && {grp})'
cm_update = (f'({adm} && @request.body.user_id:isset = false && '
             f'@request.body.conversation_id:isset = false) || '
             f'(user_id = @request.auth.id && @request.body.role:isset = false)')
gk_list = f'@request.auth.id = user_id.id || {adm}'

for coll, field, rule in (("messages", "listRule", msgs_rule),
                          ("messages", "viewRule", msgs_rule),
                          ("conversation_members", "updateRule", cm_update),
                          ("group_keys", "listRule", gk_list)):
    st, body = req("PATCH", f"/api/collections/{coll}", {field: rule})
    print(coll, field, "->", st, body.get("message", "")[:60])
PYEOF
```

- [ ] **Step 2: Run it and confirm 200s**

Run: `bash $CLAUDE_JOB_DIR/tmp/t1_rules.sh`
Expected: `AUTH_OK`, then four lines `messages listRule -> 200`, `messages viewRule -> 200`, `conversation_members updateRule -> 200`, `group_keys listRule -> 200`.

- [ ] **Step 3: Behavior probes (impersonation)**

Same script pattern, appended probes (create as `t1_probes.sh`):

```bash
# 1) joiner sees only post-join rows in the test group
SU_TOKEN=<superuser token>
U1=$(curl -s -X POST "$BASE/api/collections/users/impersonate/teb3elavw531hwx" -H "Authorization: $SU_TOKEN" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
# member row created (join time)
curl -s -G "$BASE/api/collections/conversation_members/records" --data-urlencode "filter=conversation_id=\"zrwszx3uifdjlkn\"&&user_id=\"teb3elavw531hwx\"" -H "Authorization: $U1" | python3 -c 'import json,sys; print("member_created:", json.load(sys.stdin)["items"][0]["created"])'
# visible messages
curl -s -G "$BASE/api/collections/messages/records" --data-urlencode "filter=conversation_id=\"zrwszx3uifdjlkn\"" --data-urlencode "sort=-created" --data-urlencode "perPage=5" -H "Authorization: $U1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("visible:", d["totalItems"], "min_created:", min([i["created"] for i in d["items"]] or ["none"]))'
```

Expected: `min_created >= member_created`. Note: if the group has zero pre-join messages this probe is vacuous — in that case verify the inverse with an old member of `hnj3vfuhjka7edo` (impersonate `59j3lb0pnobgjfj`) who MUST still see the group's full history (`totalItems` unchanged from before the rule change; capture the count BEFORE patching in Step 1 for comparison).

Also verify: a non-member (impersonate `vovwsmbta51qc1p` — not a member of `zrwszx3uifdjlkn`) gets `totalItems: 0` for that group, and self-promotion is blocked:

```bash
# member tries to set own role=admin (expect 400/403 now)
curl -s -X PATCH "$BASE/api/collections/conversation_members/records/<their own row id>" \
  -H "Authorization: $U1" -H "Content-Type: application/json" \
  -d '{"role":"admin"}'   # expect failure since role:isset must be false for self-updates
```

- [ ] **Step 4: Record the pre-change message count of the probe group first**

Fold into Step 3: BEFORE running Step 1's patch, capture `totalItems` for `hnj3vfuhjka7edo` as the old member — after the patch it must be identical.

---

### Task 2: Client — group row visibility filter + joinedAt sync fix

**Files:**
- Create: `lib/core/utils/group_visibility.dart`
- Create: `test/group_visibility_test.dart`
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`_rowsToMessages` ~line 518; the three `joinedAt:` sync sites ~lines 2856, 2968, 2998)

**Interfaces:**
- Produces: `bool isGroupRowVisible({required DateTime createdAt, required DateTime? memberJoinedAt, required String? decryptedBody, required String type})` — used by Task 2's repo change only.

- [ ] **Step 1: Write the failing test**

```dart
// test/group_visibility_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/group_visibility.dart';

void main() {
  final join = DateTime(2026, 10, 3, 8, 44);
  final before = DateTime(2026, 10, 1);
  final after = DateTime(2026, 10, 3, 9, 0);

  test('pre-join rows are hidden', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: join,
        decryptedBody: 'hi', type: 'text'), isFalse);
  });

  test('post-join decrypted text is visible', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: 'hi', type: 'text'), isTrue);
  });

  test('undecryptable text rows are hidden (never render ciphertext)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: null, type: 'text'), isFalse);
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: '', type: 'system'), isFalse);
  });

  test('media rows with null body stay visible (body is optional there)', () {
    expect(isGroupRowVisible(createdAt: after, memberJoinedAt: join,
        decryptedBody: null, type: 'image'), isTrue);
  });

  test('no join time (DM or missing member row) hides nothing by date', () {
    expect(isGroupRowVisible(createdAt: before, memberJoinedAt: null,
        decryptedBody: 'hi', type: 'text'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/group_visibility_test.dart`
Expected: FAIL — `isGroupRowVisible` undefined.

- [ ] **Step 3: Implement the helper**

```dart
// lib/core/utils/group_visibility.dart
/// Group-history visibility (spec D1): a row is visible only from this
/// member's join time onward, and undecryptable non-media rows are hidden
/// entirely — ciphertext must never reach a bubble.
bool isGroupRowVisible({
  required DateTime createdAt,
  required DateTime? memberJoinedAt,
  required String? decryptedBody,
  required String type,
}) {
  if (memberJoinedAt != null && createdAt.isBefore(memberJoinedAt)) return false;
  const mediaTypes = {'image', 'video', 'voice', 'document', 'file'};
  if (!mediaTypes.contains(type) &&
      (decryptedBody == null || decryptedBody.isEmpty)) {
    return false;
  }
  return true;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/group_visibility_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Wire into `_rowsToMessages`**

In `message_repository_impl.dart`, replace `_rowsToMessages` (line ~518):

```dart
Future<List<Message>> _rowsToMessages(
    List<MessagesTableData> rows) async {
  final myId = await _myId();
  if (rows.isEmpty) return [];
  final convId = rows.first.conversationId;
  DateTime? joinedAt;
  final conv = await db.conversationsDao.getConversationById(convId);
  if (conv?.type == 'group') {
    final members = await db.conversationsDao
        .getAllMembersForConversation(convId);
    joinedAt =
        members.where((m) => m.userId == myId).firstOrNull?.joinedAt;
  }
  return [
    for (final r in rows)
      if (joinedAt == null ||
          isGroupRowVisible(
            createdAt:     r.createdAt,
            memberJoinedAt: joinedAt,
            decryptedBody: r.decryptedBody,
            type:          r.type,
          ))
        _rowToMessage(r, myId),
  ];
}
```

Add the import: `import '../../core/utils/group_visibility.dart';` (adjust to the file's relative path).

- [ ] **Step 6: Fix the three `joinedAt` sync sites**

At lines ~2856, ~2968, ~2998 the member-sync maps the never-set server field `joined_at` to `DateTime.now()` (sync time, not join time). In each of the three `ConversationMembersTableCompanion.insert(` blocks replace:

```dart
joinedAt: DateTime.tryParse(m.getStringValue('joined_at')) ?? DateTime.now(),
```

with (second site uses `om`, third whatever its record variable is named — keep each site's record variable):

```dart
joinedAt: DateTime.tryParse(m.getStringValue('joined_at')) ??
    DateTime.tryParse(m.created) ??
    DateTime.now(),
```

This self-heals on the next `_syncConversations` upsert — no migration needed.

- [ ] **Step 7: analyze + full tests**

Run: `flutter analyze` → Expected: 0 errors.
Run: `flutter test` → Expected: all PASS.

- [ ] **Step 8: Commit (skipped — standing rule; Task 7 commits)**

---

### Task 3: Client — admin resume key-gap reconciliation

**Files:**
- Create: `lib/core/utils/key_gap.dart`
- Create: `test/key_gap_test.dart`
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`resyncOnResume` ~line 2146; new `_reconcileGroupKeyGaps`)

**Interfaces:**
- Produces: `Set<String> membersMissingCurrentKey({required Map<String, int?> memberToMaxVersion, required int currentVersion})`; repo private method `Future<void> _reconcileGroupKeyGaps()` called from `resyncOnResume`.

- [ ] **Step 1: Write the failing test**

```dart
// test/key_gap_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/key_gap.dart';

void main() {
  test('members with no key row are missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': null, 'b': 7}, currentVersion: 7),
        {'a'});
  });

  test('members with stale versions are missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 6, 'b': 7}, currentVersion: 7),
        {'a'});
  });

  test('current members are not missing', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 7, 'b': 7}, currentVersion: 7),
        isEmpty);
  });

  test('version 0 counts as no key', () {
    expect(membersMissingCurrentKey(
        memberToMaxVersion: {'a': 0}, currentVersion: 7),
        {'a'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/key_gap_test.dart`
Expected: FAIL — undefined function.

- [ ] **Step 3: Implement**

```dart
// lib/core/utils/key_gap.dart
/// User ids whose latest group_keys version is behind the conversation's
/// current version (null or 0 = no row at all).
Set<String> membersMissingCurrentKey({
  required Map<String, int?> memberToMaxVersion,
  required int currentVersion,
}) {
  return memberToMaxVersion.entries
      .where((e) => (e.value ?? 0) < currentVersion)
      .map((e) => e.key)
      .toSet();
}
```

Run: `flutter test test/key_gap_test.dart` → PASS (4).

- [ ] **Step 4: Add `_reconcileGroupKeyGaps` to the repo**

Insert after `resyncOnResume` (uses existing `_isRotationOwner`, `_rotateGroupKey`, `_rotateDebounce` — same shapes as `_maybeScheduleRotate`):

```dart
/// Spec D2: after resume, find groups where some member has no current
/// key row (all admin devices missed the join SSE event) and rotate so
/// they can read the group. Only the elected rotation owner acts.
Future<void> _reconcileGroupKeyGaps() async {
  try {
    final myId = await _myId();
    if (myId.isEmpty) return;
    final memberships =
        await db.conversationsDao.getMembershipsOfUser(myId);
    for (final m in memberships) {
      if (m.role != 'admin') continue;
      final convId = m.conversationId;
      final conv = await db.conversationsDao.getConversationById(convId);
      if (conv?.type != 'group') continue;
      try {
        final members = await _pb
            .collection('conversation_members')
            .getFullList(filter: 'conversation_id="$convId"', batch: 200);
        final keys = await _pb.collection('group_keys').getFullList(
            filter: 'conversation_id="$convId"', batch: 200);
        final maxByVersion = <String, int?>{};
        int current = 0;
        for (final k in keys) {
          final uid = k.getStringValue('user_id');
          final v = k.getIntValue('key_version');
          if (v > current) current = v;
          if ((maxByVersion[uid] ?? 0) < v) maxByVersion[uid] = v;
        }
        final memberVersions = {
          for (final r in members)
            r.getStringValue('user_id'): maxByVersion[r.getStringValue('user_id')],
        };
        final missing =
            membersMissingCurrentKey(
                memberToMaxVersion: memberVersions, currentVersion: current);
        if (missing.isEmpty) continue;
        debugPrint('[Group] key gap in $convId for $missing');
        if (!await _isRotationOwner(convId, myId)) continue;
        _rotateDebounce[convId]?.cancel();
        _rotateDebounce[convId] = Timer(const Duration(seconds: 3), () {
          _rotateDebounce.remove(convId);
          _rotateGroupKey(convId, myId).catchError((e) {
            debugPrint('[Group] key-gap rotate failed: $e');
          });
        });
      } catch (e) {
        debugPrint('[Group] key-gap check failed for $convId: $e');
      }
    }
  } catch (e) {
    debugPrint('[Group] key-gap reconcile failed: $e');
  }
}
```

- [ ] **Step 5: Call it from `resyncOnResume`**

Inside `resyncOnResume`, immediately after `await _syncConversations(myId);` add:

```dart
      // 2b. Rotate for members whose key distribution was missed while
      // every admin device was offline (spec D2).
      await _reconcileGroupKeyGaps();
```

Add import: `import '../../core/utils/key_gap.dart';`

- [ ] **Step 6: analyze + tests**

Run: `flutter analyze` → 0 errors. `flutter test` → all PASS.

---

### Task 4: Client — keyless-joiner banner + composer gate

**Files:**
- Modify: `lib/domain/repositories/message_repository.dart` (add method), `lib/infrastructure/repositories/message_repository_impl.dart` (implement), `lib/features/chat/providers/chat_provider.dart` (provider), `lib/features/chat/screens/chat_screen.dart` (~line 344 `canSend` block)

**Interfaces:**
- Produces: repo `Future<bool> hasUsableKey(String conversationId)`; provider `groupKeyReadyProvider` (StreamProvider.autoDispose.family<bool, String>).

- [ ] **Step 1: Repo method**

Add to the domain interface (`message_repository.dart`) near `resyncOnResume`:

```dart
  /// True when this device can encrypt/decrypt for [conversationId]
  /// (always true for DMs; groups require a distributed key).
  Future<bool> hasUsableKey(String conversationId);
```

Implement in `message_repository_impl.dart` (near `isCurrentUserAdmin`):

```dart
  @override
  Future<bool> hasUsableKey(String conversationId) async {
    final conv = await db.conversationsDao.getConversationById(conversationId);
    if (conv?.type != 'group') return true;
    try {
      await encryption.getOrFetchGroupKey(conversationId, await _myId());
      return true;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 2: Provider** (chat_provider.dart, after `conversationStreamProvider`):

```dart
/// Group-key readiness. Emits false while this device has no distributed
/// key for the group (join accepted, admin not yet online to rotate);
/// polls every 3s, stops once ready. DMs are always ready.
final groupKeyReadyProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, conversationId) async* {
  final repo = ref.read(messageRepositoryProvider);
  while (true) {
    final ready = await repo.hasUsableKey(conversationId);
    yield ready;
    if (ready) return;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
```

- [ ] **Step 3: Chat screen gate** — in the build block at line ~344, after `final restrictionMessage = ...`:

```dart
    final keyReady = !conv.isGroup
        ? true
        : (ref.watch(groupKeyReadyProvider(_cid)).asData?.value ?? false);
    final canSend = !conv.isGroup
        ? true
        : (isLeft || !keyReady
            ? false
            : (!conv.onlyAdminsCanMessage || isMeAdmin));
    final restrictionMessage = isLeft
        ? "You can't send messages to this group because you're no longer a member."
        : (!keyReady
            ? 'Waiting for a group admin to come online and share the group key…'
            : null);
```

(Replace the existing `canSend`/`restrictionMessage` declarations with this block; `_cid` and `conv` are already in scope.)

- [ ] **Step 4: analyze**

Run: `flutter analyze` → 0 errors. Manual verify happens in Task 7.

---

### Task 5: VM hook — rejoin role flip (server)

**Files:**
- Modify: `/opt/pocketbase/pb_hooks/group_invite_notify.pb.js` (on VM, via SSH)

- [ ] **Step 1: Append the accepted-handler to the hook**

Edit the VM hook (it hot-reloads; wait for `restarting...` + ~3s). Append BEFORE the `function notifyInvite` definition:

```js
// Rejoin fix (spec D4): accepting an invite when a stale member row exists
// (role='left' from a previous leave) — flip it back to member. Hooks
// bypass API rules, so this is safe even though members can't self-promote.
onRecordUpdate((e) => {
  if (e.record.getString('status') !== 'accepted') return e.next();
  const convId = e.record.getString('conversation_id');
  const uid    = e.record.getString('invited_user_id');
  try {
    const row = $app.findFirstRecordByFilter('conversation_members',
      'conversation_id = {:conv} && user_id = {:user}',
      { conv: convId, user: uid });
    if (row.getString('role') === 'left') {
      row.set('role', 'member');
      $app.save(row);
      console.log('[Invite] rejoined member re-activated:', uid);
    }
  } catch (err) { console.log('[Invite] rejoin flip skipped:', String(err)); }
  return e.next();
}, 'group_invites');
```

NOTE: verify `findFirstRecordByFilter` exists on this PB build (`$app.findFirstRecordByFilter(collection, filter, params)`); if the VM's PB rejects it at load (journalctl shows a load error), use `$app.findRecordsByFilter(...)` and take `.rows[0]`... first check `/opt/pocketbase/pb_hooks/` siblings for an existing usage pattern (fcm_notify.pb.js) and mirror it. If journalctl shows the hook loaded with no error and a probe accept flips a left row, done.

- [ ] **Step 2: Probe**

Create a left-row scenario with throwaway data: as superuser via curl, pick group `zrwszx3uifdjlkn`, create a `group_invites` row for `teb3elavw531hwx`, set their existing `conversation_members` row `role` to `left` (SU PATCH), then impersonate `teb3elavw531hwx` and PATCH the invite to `accepted`... — NO: the invitee can only PATCH status to accepted via updateRule (allowed: own row, immutable fields unset) — but that makes them a real member of the user's group. Acceptable: they already accepted a real invite there today; the probe restores their legit state (role member, which is what it already is). Simpler safe probe: temporarily set `teb3elavw531hwx`'s CM row in that group to `left` via SU, impersonate them to PATCH invite `f6mchqkcq0023sy` (already `accepted`? — no, PATCH fires on any update; set it to `pending` first via SU, then the invitee PATCHes to `accepted`) → expect journalctl `[Invite] rejoined member re-activated: teb3elavw531hwx` and the CM row back to `member`. Restore invite row to `accepted` afterwards (it was). If anything fails, restore the CM row to `member` by hand via SU PATCH.

- [ ] **Step 3: Verify hook load**

Run on VM: `sudo journalctl -u pocketbase --since "-2 minutes" --no-pager | tail -5`
Expected: `restarting...`, `Server started`, no `jsvm`/hook error lines.

---

### Task 6: Client — invite management UI + error surfacing

**Files:**
- Modify: `lib/domain/entities/group_invite.dart` (add `PendingGroupInvite`), `lib/domain/repositories/message_repository.dart` + `lib/infrastructure/repositories/message_repository_impl.dart` (methods), `lib/features/groups/screens/group_settings_screen.dart` (section + honest toasts), `lib/features/friend_requests/screens/friend_requests_screen.dart` (decline catch)

**Interfaces:**
- Produces: entity `PendingGroupInvite {String inviteId; User user; String status}`; repo `Future<List<PendingGroupInvite>> getPendingInvitesForConversation(String conversationId)`; repo `Future<void> cancelGroupInvite(String inviteId)`.

- [ ] **Step 1: Entity** — append to `lib/domain/entities/group_invite.dart`:

```dart
/// An invite as seen from the ADMIN side (group settings): the invitee,
/// not the inviter, is the interesting party.
class PendingGroupInvite {
  const PendingGroupInvite({
    required this.inviteId,
    required this.user,
    required this.status,
  });
  final String inviteId;
  final User   user;
  final String status; // pending | accepted | declined
}
```

(The file already imports the `User` entity — verify; if not, add the import.)

- [ ] **Step 2: Repo methods** — interface + impl:

```dart
  @override
  Future<List<PendingGroupInvite>> getPendingInvitesForConversation(
      String conversationId) async {
    final rows = await _pb.collection('group_invites').getFullList(
      filter: 'conversation_id="$conversationId"',
      expand: 'invited_user_id',
      batch: 100,
    );
    final out = <PendingGroupInvite>[];
    for (final r in rows) {
      final u = r.expand['invited_user_id']?.firstOrNull;
      if (u == null) continue;
      out.add(PendingGroupInvite(
        inviteId: r.id,
        status:   r.getStringValue('status'),
        user:     _inviteRecordToUser(u),
      ));
    }
    return out;
  }

  @override
  Future<void> cancelGroupInvite(String inviteId) async {
    await _pb.collection('group_invites').delete(inviteId);
  }
```

- [ ] **Step 3: Group settings section** — in `group_settings_screen.dart`, inside the member list area, add a FutureBuilder (or `ref.watch` on a small `FutureProvider.family` defined at the top of the file: `final pendingInvitesProvider = FutureProvider.autoDispose.family<List<PendingGroupInvite>, String>((ref, convId) => ref.watch(messageRepositoryProvider).getPendingInvitesForConversation(convId));`) rendering below the members tile list (visible only when the list is non-empty):

```dart
  // ── Invites (admin management) ────────────────────────────────
  final invitesAsync = ref.watch(pendingInvitesProvider(widget.conversation.id));
  final invites = invitesAsync.asData?.value
      ?.where((i) => i.status != 'accepted').toList() ?? const [];
  if (isMeAdmin && invites.isNotEmpty) ...[
    const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text('Invites',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    ),
    for (final inv in invites)
      ListTile(
        leading: CircleAvatar(child: Text(inv.user.displayName.isNotEmpty
            ? inv.user.displayName[0].toUpperCase() : '?')),
        title: Text(inv.user.displayName.isNotEmpty
            ? inv.user.displayName : inv.user.username),
        subtitle: Text(inv.status == 'pending'
            ? 'Invite pending' : 'Declined'),
        trailing: inv.status == 'pending'
            ? TextButton(
                onPressed: () async {
                  try {
                    await ref.read(messageRepositoryProvider)
                        .cancelGroupInvite(inv.inviteId);
                    ref.invalidate(pendingInvitesProvider(widget.conversation.id));
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cancel failed: $e')));
                    }
                  }
                },
                child: const Text('Cancel'),
              )
            : TextButton(
                onPressed: () async {
                  try {
                    await ref.read(messageRepositoryProvider)
                        .sendGroupInvite(widget.conversation.id, inv.user.id);
                    ref.invalidate(
                        pendingInvitesProvider(widget.conversation.id));
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Re-invite failed: $e')));
                    }
                  }
                },
                child: const Text('Re-invite'),
              ),
      ),
  ],
```

Adapt placement to the actual widget tree (the screen is a ConsumerStatefulWidget; `isMeAdmin` may need computing via `isCurrentUserAdmin` — the file already imports the repo). Keep every mutation wrapped in try/catch with a visible SnackBar — no silent failures (spec D7).

- [ ] **Step 4: Honest invite-send toast** — replace the send loop (~line 179-195) with failure counting:

```dart
                              Navigator.pop(ctx);
                              var failed = 0;
                              for (final id in selected) {
                                try {
                                  await ref
                                      .read(messageRepositoryProvider)
                                      .sendGroupInvite(
                                          widget.conversation.id, id);
                                } catch (e) {
                                  failed += 1;
                                  debugPrint('[Group] invite error for $id: $e');
                                }
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(failed == 0
                                        ? 'Invite(s) sent'
                                        : 'Invited ${selected.length - failed}, '
                                          'failed $failed — check connection and try again'),
                                  ),
                                );
                              }
```

- [ ] **Step 5: Decline error surfacing** — in `friend_requests_screen.dart` decline handler (~line 262) wrap:

```dart
              onPressed: () async {
                try {
                  await ref
                      .read(messageRepositoryProvider)
                      .declineGroupInvite(invite.id);
                  ref.invalidate(incomingGroupInvitesProvider);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to decline: $e')),
                  );
                }
              },
```

- [ ] **Step 6: analyze + tests**

Run: `flutter analyze` → 0 errors. `flutter test` → all PASS.

---

### Task 7: Ship — build, install, user 2-device pass, commit

**Files:** none (verification + commit)

- [ ] **Step 1: Full gate**

Run: `flutter analyze` → 0 errors. Run: `flutter test` → all PASS.
Run: `flutter build apk --debug --target-platform android-arm64` → `✓ Built build/app/outputs/flutter-apk/app-debug.apk`
Verify the APK contains `lib/arm64-v8a/libflutter.so` (the 25 Sep x64-only build bug must never recur):
`unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libflutter`

- [ ] **Step 2: Install both devices**

`adb -s RFCRA047WSJ install -r build/app/outputs/flutter-apk/app-debug.apk` → Success
`adb -s c7e9f10e install -r build/app/outputs/flutter-apk/app-debug.apk` → Success
(Redmi drops off USB occasionally — re-check `adb devices`, ask user to replug if gone.)
Launch both via `monkey -p com.chai.kuch_bhi -c android.intent.category.LAUNCHER 1`, confirm process alive (`adb shell pidof com.chai.kuch_bhi`), crash buffer empty (`adb logcat -d -b crash`).

- [ ] **Step 3: User 2-device pass criteria**

1. Admin invites a friend from group info → card appears on invitee's Requests screen; admin sees "Invite pending" + Cancel in group info.
2. Cancel kills the pending invite (invitee's card disappears on refresh; re-invite restores it).
3. Decline → admin sees "Declined" + Re-invite; re-invite → card returns.
4. Accept → instant member, "X joined the group" bubble once, composer enabled.
5. **New member does NOT see any pre-join messages** (no 🔒 garbage); old members' history unchanged.
6. Admin-offline scenario: invitee accepts while admin's device is offline/force-stopped → banner "Waiting for a group admin…" + composer disabled on joiner; start admin app → within ~10s banner clears, joiner can send.
7. Leave group → re-invite → accept → member can send again (rejoin fix).
8. Failed invite (airplane mode) → toast reports the failure, not "Invite(s) sent".

- [ ] **Step 4: Commit (only after user PASS)**

```bash
git add -A lib test docs
git commit -m "[Groups] Invite rework — history cutoff, key-gap reconcile, rejoin fix, invite management

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

Exclude junk files (session transcripts, current_task*.md, stray .txt files in repo root — keep them untracked).
