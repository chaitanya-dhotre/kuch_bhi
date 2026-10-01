# Group Invites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consent-based group joins — admin adds from the member picker send `group_invites` requests; invitee accepts (self-join + admin auto-rotate) or declines; admin sees Pending/Declined status.

**Architecture:** New PB `group_invites` collection (UNIQUE conv+user, re-invite = PATCH→pending) + `conversation_members.createRule` self-join clause. Client: invite repo methods, SSE auto-rotate on admin devices, friend-requests-style accept UI, FCM push via a new VM hook. No Drift schema change (invites are PB-backed, provider-fetched).

**Tech Stack:** Flutter/Riverpod/Drift (client), PocketBase 0.37.5 (server), pb.js hooks + python FCM webhook (VM 140.245.15.77).

## Global Constraints

- NO git commits until the user verifies on 2 devices (standing rule — overrides per-task commit steps below; the final task collects the single commit).
- Back-reference rules use `?=` on EVERY `@collection` comparison (plain `=` is match-ALL on this PB build — verified 2026-09-24).
- Group CREATION flow (`create_group_screen.dart` direct member rows) stays as-is — invites apply only to post-creation adds via the picker.
- `flutter analyze` must be 0 errors after every client task.
- Server credentials: superuser password at `/home/chaitanyadhotre/Chaitanya/Oracle/pb_superuser_password_NEW.txt` (pipe via stdin/env, never echo). Identity `chaitanyad301@proton.me`. SSH key `/home/chaitanyadhotre/Chaitanya/Oracle/ssh-key-2026-04-28-1.key`, user `ubuntu@140.245.15.77`.
- Spec: `docs/superpowers/specs/2026-09-24-group-invites-design.md`.

---

### Task 1: Server — `group_invites` collection, rules, self-join clause

**Files:**
- Create: `~/.claude/jobs/e1ef194b/tmp/create_group_invites.sh` (throwaway; runs locally, hits https://kuch-bhi.duckdns.org)

**Interfaces:**
- Produces: PB collection `group_invites` with fields `conversation_id` (relation→conversations, required, cascadeDelete), `invited_user_id` (relation→users, required, cascadeDelete), `invited_by` (relation→users, required), `status` (select [pending, accepted, declined], required), autodates; UNIQUE index `idx_gi_conv_user (conversation_id, invited_user_id)`; rules per spec. Extended `conversation_members.createRule`.

- [ ] **Step 1: Write the server script**

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

python3 - <<'PYEOF' || exit 1
import json
admin = ('(@collection.conversation_members.conversation_id ?= conversation_id '
         '&& @collection.conversation_members.user_id ?= @request.auth.id '
         '&& @collection.conversation_members.role ?= "admin")')
selfjoin = ('(@request.auth.id = user_id '
            '&& @collection.group_invites.conversation_id ?= conversation_id '
            '&& @collection.group_invites.invited_user_id ?= @request.auth.id '
            '&& @collection.group_invites.status ?= "pending")')
invite_rules = {
  "listRule":   'invited_user_id = @request.auth.id || ' + admin,
  "viewRule":   'invited_user_id = @request.auth.id || ' + admin,
  "createRule": admin,
  "updateRule": 'invited_user_id = @request.auth.id || ' + admin,
  "deleteRule": 'invited_user_id = @request.auth.id || ' + admin,
}
cm_create = ('@request.auth.id != "" && (@request.auth.id = conversation_id.created_by '
             '|| ' + admin + ' || ' + selfjoin + ')')
open('/tmp/gi_create.json', 'w').write(json.dumps(invite_rules))
open('/tmp/cm_create.json', 'w').write(json.dumps({"createRule": cm_create}))
PYEOF

echo '--- CREATE group_invites ---'
curl -s -X POST "$BASE/api/collections" \
  -H "Authorization: $TOKEN" -H 'Content-Type: application/json' -d @/tmp/coll.json
echo
echo '--- PATCH conversation_members.createRule ---'
curl -s -X PATCH "$BASE/api/collections/conversation_members" \
  -H "Authorization: $TOKEN" -H 'Content-Type: application/json' -d @/tmp/cm_create.json \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("createRule:", d.get("createRule"))'
rm -f /tmp/gi_create.json /tmp/cm_create.json
```

The `POST /api/collections` body (`/tmp/coll.json`) — write it in the same python block instead of a second file:

```python
coll = {
  "name": "group_invites",
  "type": "base",
  "fields": [
    {"type": "relation", "name": "conversation_id", "required": True,
     "collectionId": "<CONVERSATIONS_COLLECTION_ID>", "cascadeDelete": True},
    {"type": "relation", "name": "invited_user_id", "required": True,
     "collectionId": "_pb_users_auth_", "cascadeDelete": True},
    {"type": "relation", "name": "invited_by", "required": True,
     "collectionId": "_pb_users_auth_"},
    {"type": "select", "name": "status", "required": True,
     "values": ["pending", "accepted", "declined"]},
    {"type": "autodate", "name": "created", "onCreate": True},
    {"type": "autodate", "name": "updated", "onCreate": True, "onUpdate": True},
  ],
  "indexes": ["CREATE UNIQUE INDEX `idx_gi_conv_user` ON `group_invites` (`conversation_id`, `invited_user_id`)"],
  "listRule":   'invited_user_id = @request.auth.id || ' + admin,
  "viewRule":   'invited_user_id = @request.auth.id || ' + admin,
  "createRule": admin,
  "updateRule": 'invited_user_id = @request.auth.id || ' + admin,
  "deleteRule": 'invited_user_id = @request.auth.id || ' + admin,
}
open('/tmp/coll.json', 'w').write(json.dumps(coll))
```

`<CONVERSATIONS_COLLECTION_ID>` — resolve first: `curl "$BASE/api/collections/conversations" -H "Authorization: $TOKEN" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'` and interpolate into the python heredoc via an exported env var.

- [ ] **Step 2: Run script; verify**

Run: `bash ~/.claude/jobs/e1ef194b/tmp/create_group_invites.sh`
Expected: AUTH_OK, collection JSON with `"name":"group_invites"`, then the patched createRule echoed with all three `?=` clauses.

- [ ] **Step 3: Rule probes (impersonation, mirrors 2026-09-24 method)**

Extend the script (or a second script) to:
1. Impersonate the group creator (`users/impersonate/{created_by}`) → `POST /api/collections/group_invites/records` with `{conversation_id, invited_user_id: <member user id>, invited_by: <creator id>, status: "pending"}` → expect **200**.
2. Impersonate the plain member → same POST (inviting the creator) → expect **400/403**.
3. Impersonate the invitee (the member just invited) → `PATCH /api/collections/group_invites/records/<invite_id>` `{"status":"declined"}` → expect **200**; member POSTing a `conversation_members` row for THEMSELVES in that conv (status back to pending first via admin) → expect **200**; member POSTing a row for ANOTHER user → expect **400/403**.
4. List probes: invitee `GET group_invites/records?filter=conversation_id=...` sees own invite (200 items ≥1); a different non-invited member sees 0 items.
5. Clean up: admin DELETEs the probe invite row (deleteRule covers it) → 204.

Expected: all four scenarios behave as stated. Any failure = fix the rule string before Task 2.

---

### Task 2: VM — group-invite FCM push

**Files:**
- Create on VM: `/opt/pocketbase/pb_hooks/group_invite_notify.pb.js`
- Modify on VM: `/opt/kuchbhi/fcm_webhook.py` (systemd `kuchbhi-fcm.service`)
- Modify (client-side, later task): `lib/services/fcm_service.dart` consumes `type == 'group_invite'`

**Interfaces:**
- Produces: FCM data payload `{type: 'group_invite', invite_id, conversation_id, conversation_name, inviter_id, inviter_name}` delivered to the invitee's token.

- [ ] **Step 1: Write the PB hook** (model: `pb_hooks/fcm_notify.pb.js`)

```javascript
// group_invite_notify.pb.js — push on group_invites create / update-to-pending.
onRecordCreate((e) => {
  return notifyInvite(e.record, e);
}, 'group_invites');

onRecordUpdate((e) => {
  // Re-invite: only when flipped back to pending.
  if (e.record.getString('status') === 'pending') return notifyInvite(e.record, e);
  return e.next();
}, 'group_invites');

function notifyInvite(rec, e) {
  const conversationId = rec.getString('conversation_id');
  const invitedUserId  = rec.getString('invited_user_id');
  const inviterId      = rec.getString('invited_by');
  if (!conversationId || !invitedUserId || !inviterId) return e.next();

  let inviterName = '';
  let convName    = '';
  try {
    const inviter = $app.findRecordById('users', inviterId);
    inviterName = inviter.getString('display_name') || inviter.getString('username') || '';
  } catch (err) { console.log('[FCM] inviter lookup failed:', String(err)); }
  try {
    const conv = $app.findRecordById('conversations', conversationId);
    convName = conv.getString('name') || 'a group';
  } catch (err) { console.log('[FCM] conv lookup failed:', String(err)); }

  let token = '';
  try {
    const user = $app.findRecordById('users', invitedUserId);
    token = user.getString('fcm_token');
  } catch (err) { console.log('[FCM] invitee lookup failed:', String(err)); }
  if (!token || token.length < 10) return e.next();

  try {
    const res = $http.send({
      url:    'http://127.0.0.1:8091/notify',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Hook-Secret': 'kuchbhi-hook-secret' },
      body: JSON.stringify({
        notification_type: 'group_invite',
        invite_id:        rec.id,
        conversation_id:  conversationId,
        conversation_name: convName,
        inviter_id:       inviterId,
        inviter_name:     inviterName,
        recipients:       [{ user_id: invitedUserId, fcm_token: token }],
      }),
    });
    console.log('[FCM] invite webhook status:', res.statusCode);
  } catch (err) { console.log('[FCM] invite webhook failed:', String(err)); }
  return e.next();
}
```

- [ ] **Step 2: Extend the webhook** (`/opt/kuchbhi/fcm_webhook.py`)

In `_send_fcm`, change the hardcoded `'type': 'new_message'` to accept and merge extra data:

```python
def _send_fcm(fcm_token: str, message_id: str,
              conversation_id: str, sender_id: str, sender_name: str = '',
              extra: dict | None = None) -> bool:
    data = {
        'type':            'new_message',
        'message_id':      message_id,
        'conversation_id': conversation_id,
        'sender_id':       sender_id,
        'sender_name':     sender_name,
    }
    if extra:
        data.update(extra)
    payload = {'message': {'token': fcm_token, 'data': data,
                          'android': {'priority': 'HIGH'}}}
    # ... rest unchanged (requests.post with payload)
```

In `_handle_webhook`, branch on the notification type and forward all extra fields:

```python
def _handle_webhook(data: dict) -> None:
    n_type      = data.get('notification_type', 'new_message')
    recipients  = data.get('recipients', [])
    if not recipients:
        log.warning('No recipients in payload'); return
    if n_type == 'group_invite':
        extra = {
            'type':              'group_invite',
            'invite_id':         data.get('invite_id', ''),
            'conversation_id':   data.get('conversation_id', ''),
            'conversation_name': data.get('conversation_name', ''),
            'inviter_id':        data.get('inviter_id', ''),
            'inviter_name':      data.get('inviter_name', ''),
        }
        for r in recipients:
            if r.get('fcm_token'):
                _send_fcm(r['fcm_token'], data.get('invite_id', ''),
                          data.get('conversation_id', ''),
                          data.get('inviter_id', ''),
                          data.get('inviter_name', ''), extra=extra)
        return
    # existing new_message path unchanged below
    ...
```

- [ ] **Step 3: Deploy + restart + verify**

```bash
scp -i <key> group_invite_notify.pb.js ubuntu@140.245.15.77:/opt/pocketbase/pb_hooks/
ssh -i <key> ubuntu@140.245.15.77 'sudo systemctl restart pocketbase kuchbhi-fcm'
```
Verify: `ssh ... 'tail -5 /var/log/kuchbhi-fcm.log; systemctl is-active kuchbhi-fcm pocketbase'` → both active, no startup errors. (PB picks up pb_hooks on restart.)
End-to-end push check happens in Task 8 (device with FCM = the Samsung).

---

### Task 3: Client — `GroupInvite` entity + repository methods

**Files:**
- Create: `lib/domain/entities/group_invite.dart`
- Modify: `lib/domain/repositories/message_repository.dart` (interface)
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (replace `addMemberToGroup` internals with `sendGroupInvite`; add accept/decline/list)

**Interfaces:**
- Consumes: PB `group_invites` records; `_myId()`, `_userName()`, `_emitSystemMessage()`, `_syncConversationsBackground()` (all exist in the impl).
- Produces:
  - `class GroupInvite { final String id; final String conversationId; final String conversationName; final User invitedBy; final String status; final DateTime createdAt; }`
  - `Future<void> sendGroupInvite(String conversationId, String userId)` — admin sends/re-invites
  - `Future<List<GroupInvite>> getIncomingGroupInvites()` — my pending invites, newest first
  - `Future<void> acceptGroupInvite(String inviteId)` — self-join
  - `Future<void> declineGroupInvite(String inviteId)`
  - `Future<Map<String, String>> getInviteStatusesForConversation(String conversationId)` — userId → status, for picker chips

- [ ] **Step 1: Entity** (`lib/domain/entities/group_invite.dart`)

```dart
import 'user.dart';

class GroupInvite {
  const GroupInvite({
    required this.id,
    required this.conversationId,
    required this.conversationName,
    required this.invitedBy,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String conversationName;

  /// User who sent the invite.
  final User invitedBy;

  /// 'pending' | 'accepted' | 'declined'
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}
```

- [ ] **Step 2: Interface additions** (`lib/domain/repositories/message_repository.dart`, next to the group methods at line ~125):

```dart
  /// Sends (or re-sends) a group invite to [userId]. Idempotent per
  /// (conversation, user): an existing row is PATCHed back to 'pending'.
  Future<void> sendGroupInvite(String conversationId, String userId);

  /// My pending incoming group invites, newest first.
  Future<List<GroupInvite>> getIncomingGroupInvites();

  /// Accept: creates my own membership row, marks the invite accepted,
  /// syncs the conversation locally, then emits "X joined the group" once
  /// the group key is distributed (bounded wait).
  Future<void> acceptGroupInvite(String inviteId);

  /// Decline: marks the invite declined. Nothing else.
  Future<void> declineGroupInvite(String inviteId);

  /// userId -> invite status for a conversation (picker chips).
  Future<Map<String, String>> getInviteStatusesForConversation(String conversationId);
```

Add the import: `import '../entities/group_invite.dart';` at the top with the other entity imports.

- [ ] **Step 3: Implementation** (`message_repository_impl.dart`). Replace the body of `addMemberToGroup` (line ~1506) — keep the method name `addMemberToGroup` in the interface deprecated-free style: rename to `sendGroupInvite` in interface + impl + both call sites (Task 5 changes the UI call site; rename here).

```dart
  @override
  Future<void> sendGroupInvite(String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    // Idempotent: one invite per (conversation, user) — UNIQUE index
    // server-side. Re-invite flips an existing row back to pending.
    try {
      final existing = await _pb.collection('group_invites').getFirstListItem(
        'conversation_id="$conversationId"&&invited_user_id="$userId"',
      );
      await _pb.collection('group_invites').update(
        existing.id, body: {'status': 'pending'},
      );
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _pb.collection('group_invites').create(body: {
        'conversation_id': conversationId,
        'invited_user_id': userId,
        'invited_by':     myId,
        'status':         'pending',
      });
    }
  }
```

```dart
  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async {
    final myId = await _myId();
    if (myId.isEmpty) return [];
    final items = await _pb.collection('group_invites').getFullList(
      filter: 'invited_user_id="$myId"&&status="pending"',
      expand: 'invited_by,conversation_id',
      sort:   '-created',
      batch:  100,
    );
    final invites = <GroupInvite>[];
    for (final r in items) {
      final inviter = r.expand['invited_by']?.firstOrNull;
      if (inviter != null) await _cacheUserRecord(inviter);
      final convName = r.expand['conversation_id']?.firstOrNull
          ?.getStringValue('name');
      invites.add(GroupInvite(
        id:              r.id,
        conversationId:  r.getStringValue('conversation_id'),
        conversationName: convName?.isNotEmpty == true ? convName! : 'Group',
        invitedBy:       inviter != null
            ? _recordToUser(inviter)
            : const User(id: '', username: '', displayName: 'Someone'),
        status:          r.getStringValue('status'),
        createdAt:       DateTime.tryParse(r.getStringValue('created')) ??
            DateTime.now(),
      ));
    }
    return invites;
  }
```

Note: `_recordToUser` and `_cacheUserRecord` already exist in this file (used by friends/group flows). If `_recordToUser` lives in `friend_repository_impl.dart` instead, inline the mapping (id/username/display_name/avatarUrl from the record) — check with `grep -n "_recordToUser" lib/infrastructure/repositories/message_repository_impl.dart` and adapt.

```dart
  @override
  Future<void> acceptGroupInvite(String inviteId) async {
    final myId = await _myId();
    if (myId.isEmpty) throw Exception('Not authenticated');
    final invite = await _pb.collection('group_invites').getOne(inviteId);
    final convId = invite.getStringValue('conversation_id');

    // Self-join — conversation_members.createRule's invite clause covers this.
    try {
      await _pb.collection('conversation_members').create(body: {
        'conversation_id': convId,
        'user_id':         myId,
        'role':            'member',
      });
    } on ClientException catch (e) {
      // UNIQUE(conversation_id,user_id) — already a member (e.g. accepted on
      // another device). Treat as joined.
      if (e.statusCode != 400) rethrow;
      debugPrint('[Invite] already a member of $convId — continuing');
    }

    await _pb.collection('group_invites').update(
      inviteId, body: {'status': 'accepted'},
    );

    // Make the group appear locally right away (messages stay garbled until
    // an admin device rotates the key and we fetch it).
    try {
      await _syncConversationsBackground();
    } catch (e) {
      debugPrint('[Invite] post-accept sync failed: $e');
    }

    // Bounded wait for the group key (admin auto-rotate), then a single
    // "X joined the group" bubble.
    unawaited(_emitJoinedWhenKeyReady(convId, myId));
  }

  /// After accepting an invite, the joiner holds no group key until an admin
  /// device rotates. Poll (bounded) for the key, then emit the join bubble
  /// exactly once (guarded by a local lookup for an existing copy).
  Future<void> _emitJoinedWhenKeyReady(String convId, String myId) async {
    const tries = 15;
    for (var i = 0; i < tries; i++) {
      try {
        await encryption.getOrFetchGroupKey(convId, myId);
        final myName = await _userName(myId);
        final body   = '$myName joined the group';
        final already = await db.messagesDao
            .findSystemMessage(convId, myId, body);
        if (already == null) {
          await _emitSystemMessage(convId, body, actorUserId: myId);
        }
        return;
      } on Exception {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    debugPrint('[Invite] key not distributed within ${tries * 2}s — '
        'join bubble deferred to next resume sync');
    _pendingJoinEmitConvIds.add(convId);
  }
```

`_pendingJoinEmitConvIds` = `final Set<String> _pendingJoinEmitConvIds = {};` (field on the repo). The resume path retry: in `resyncOnResume` (or wherever `_syncConversationsBackground` is called on app resume), append:

```dart
    // Retry deferred join bubbles (accept happened while no admin device was
    // online to rotate the key).
    for (final convId in _pendingJoinEmitConvIds.toList()) {
      unawaited(_emitJoinedWhenKeyReady(convId, await _myId()));
    }
```
Note: after a successful emit inside `_emitJoinedWhenKeyReady`, remove the convId from the set (`_pendingJoinEmitConvIds.remove(convId);` right after the emit).

```dart
  @override
  Future<void> declineGroupInvite(String inviteId) async {
    await _pb.collection('group_invites').update(
      inviteId, body: {'status': 'declined'},
    );
  }

  @override
  Future<Map<String, String>> getInviteStatusesForConversation(
      String conversationId) async {
    final rows = await _pb.collection('group_invites').getFullList(
      filter: 'conversation_id="$conversationId"',
      batch: 100,
    );
    return {
      for (final r in rows)
        r.getStringValue('invited_user_id'): r.getStringValue('status'),
    };
  }
```

`findSystemMessage` does not exist yet — add to `MessagesDao` (`lib/data/local/database/daos/messages_dao.dart`):

```dart
  /// Looks up a locally-cached system message by exact body (used to guard
  /// against duplicate "X joined the group" bubbles). Server rows only —
  /// serverId null rows (local-only) count too.
  Future<MessagesTableData?> findSystemMessage(
      String conversationId, String senderId, String body) {
    final q = select(messagesTable)
      ..where((t) =>
          t.conversationId.equals(conversationId) &
          t.senderId.equals(senderId) &
          t.type.equals('system'))
      ..limit(50);
    return q.get().then((rows) => rows.firstWhereOrNull(
        (m) => (m.decryptedBody ?? '') == body));
  }
```

(`firstWhereOrNull` needs `package:collection` — check existing imports in the dao; if absent, use a manual loop. Run `dart run build_runner build` is NOT needed — plain select, no drift codegen for this method.)

- [ ] **Step 4: Verify**

Run: `flutter analyze 2>&1 | tail -5`
Expected: 0 errors (warnings pre-existing only). `unawaited` needs `import 'dart:async';` — confirm it's already imported in the impl file.

---

### Task 4: Client — admin auto-rotate, remove-flow invite purge

**Files:**
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` — `_subMembers` (line ~240), `_syncConversationsBackground` member-upsert path, `removeMemberFromGroup` (line ~1573)

**Interfaces:**
- Consumes: `_rotateGroupKey(conversationId, myId)`, `isCurrentUserAdmin(conversationId)`, `getAllMembersForConversation` — all exist.
- Produces: automatic key rotation on admin devices when a new member row appears (SSE create + sync discovery); invite purge on remove.

- [ ] **Step 1: Auto-rotate on SSE member-create**

Replace `_subMembers` (line 240):

```dart
  /// Per-conversation rotate debounce (one rotation per join burst).
  final Map<String, Timer> _rotateDebounce = {};

  Future<void> _subMembers() async {
    await _pb.collection('conversation_members').subscribe('*', (event) {
      _syncConversationsBackground();
      if (event.action != 'create' || event.record == null) return;
      final r = event.record!;
      _maybeScheduleRotate(r.getStringValue('conversation_id'),
          r.getStringValue('user_id'));
    });
  }

  /// Invite-accept self-joins create the member row from the JOINER's device.
  /// Key distribution must come from a key-holding device: any admin of the
  /// group rotates (debounced) so the joiner receives the current key.
  Future<void> _maybeScheduleRotate(String convId, String newUserId) async {
    if (convId.isEmpty) return;
    final myId = await _myId();
    if (myId.isEmpty || newUserId == myId) return;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type != 'group') return;
    if (!await isCurrentUserAdmin(convId)) return;

    _rotateDebounce[convId]?.cancel();
    _rotateDebounce[convId] = Timer(const Duration(seconds: 3), () async {
      _rotateDebounce.remove(convId);
      try {
        await _rotateGroupKey(convId, myId);
      } catch (e) {
        debugPrint('[Group] auto-rotate on join failed: $e');
      }
    });
  }
```

- [ ] **Step 2: Sync-discovery rotate (offline-admin case)**

In `_syncConversationsBackground`, at the point where member rows are upserted locally (search `upsertMember(`), pre-check existence so a row that is new-to-this-device triggers the same rotate:

```dart
      final existingLocal = await db.conversationsDao
          .getAllMembersForConversation(conv.id)
          .then((rows) => rows.any((m) => m.userId == serverRowUserId));
      if (!existingLocal) {
        await _maybeScheduleRotate(conv.id, serverRowUserId);
      }
      await db.conversationsDao.upsertMember(...);  // unchanged
```

Adapt variable names to the actual loop body — read the surrounding code first and splice minimally.

- [ ] **Step 3: Purge invites on remove**

In `removeMemberFromGroup`, right after the member-row deletion loop (the `for (final rec in memberRecs) { ... delete(rec.id); }` block, ~line 1593) and before the group_keys purge, add:

```dart
    // Purge any pending invite for this user in this conversation — a live
    // invite would let them self-rejoin after being removed.
    try {
      final invs = await _pb.collection('group_invites').getFullList(
        filter: 'conversation_id="$conversationId"&&invited_user_id="$userId"',
        batch: 20,
      );
      for (final inv in invs) {
        await _pb.collection('group_invites').delete(inv.id);
      }
    } catch (e) {
      debugPrint('[Group] invite purge on remove failed: $e');
    }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze 2>&1 | tail -5` → 0 errors.

---

### Task 5: Client — provider + requests screen cards

**Files:**
- Modify: `lib/features/friend_requests/providers/friend_request_provider.dart` (add invite provider)
- Modify: `lib/features/friend_requests/screens/friend_requests_screen.dart` (invite section)
- Modify: `lib/domain/repositories/message_repository.dart` already carries the methods (Task 3)

**Interfaces:**
- Consumes: `getIncomingGroupInvites`, `acceptGroupInvite`, `declineGroupInvite`; `messageRepositoryProvider`.
- Produces: `incomingGroupInvitesProvider` (AsyncNotifier<List<GroupInvite>>), badge count includes invites.

- [ ] **Step 1: Provider** (append to `friend_request_provider.dart`)

```dart
/// Watches incoming group invites (same lifecycle pattern as friend requests).
class IncomingGroupInvitesNotifier
    extends AsyncNotifier<List<GroupInvite>> {
  @override
  Future<List<GroupInvite>> build() async {
    final pb = ref.read(pocketbaseClientProvider).pb;

    if (pb != null) {
      await pb.collection('group_invites').subscribe('*', (_) => _refresh());
      ref.onDispose(() => pb.collection('group_invites').unsubscribe());
    }

    return ref.read(messageRepositoryProvider).getIncomingGroupInvites();
  }

  Future<void> _refresh() async {
    state = AsyncData(
      await ref.read(messageRepositoryProvider).getIncomingGroupInvites(),
    );
  }
}

final incomingGroupInvitesProvider =
    AsyncNotifierProvider<IncomingGroupInvitesNotifier, List<GroupInvite>>(
  IncomingGroupInvitesNotifier.new,
);
```

Imports to add at top: `import '../../../domain/entities/group_invite.dart';` and `import '../../../infrastructure/repositories/message_repository_impl.dart';` (for `messageRepositoryProvider` — check where `messageRepositoryProvider` is exported; if it lives in a providers file, import that instead and follow the pattern the screen already uses).

Update `pendingRequestCountProvider` to combine:

```dart
final pendingRequestCountProvider = Provider<int>((ref) {
  final friends = ref.watch(incomingRequestsProvider).when(
        data: (l) => l.length, loading: () => 0, error: (_, __) => 0);
  final invites = ref.watch(incomingGroupInvitesProvider).when(
        data: (l) => l.length, loading: () => 0, error: (_, __) => 0);
  return friends + invites;
});
```

- [ ] **Step 2: Screen cards** (`friend_requests_screen.dart`)

Retitle AppBar to `Requests`. Watch both providers; when both lists are empty keep the current empty state (text: 'No pending requests'). Below the friend-request tiles, render invite tiles:

```dart
class _GroupInviteTile extends ConsumerWidget {
  const _GroupInviteTile({required this.invite});
  final GroupInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inviter = invite.invitedBy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primaryLight,
              child: Text(
                invite.conversationName
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invite.conversationName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    inviter.displayName.isNotEmpty
                        ? '${inviter.displayName} invited you to join'
                        : 'You were invited to join',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                await ref
                    .read(messageRepositoryProvider)
                    .declineGroupInvite(invite.id);
                ref.invalidate(incomingGroupInvitesProvider);
              },
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.error.withValues(alpha: 0.1),
                foregroundColor: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                try {
                  await ref
                      .read(messageRepositoryProvider)
                      .acceptGroupInvite(invite.id);
                  ref.invalidate(incomingGroupInvitesProvider);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to accept: $e')),
                  );
                }
              },
              icon: const Icon(Icons.check),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.success.withValues(alpha: 0.1),
                foregroundColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

ListView structure: combine item count = friendTiles + inviteTiles; friend tiles first, then a one-line "Group invites" section header (styled `Text('Group invites', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: onSurface.withValues(alpha: 0.5)))` inside a `Padding`) only when invites are non-empty, then `_GroupInviteTile`s. Empty checks: show empty state only when BOTH lists are empty.

Imports: add `group_invite.dart` entity + the provider import.

- [ ] **Step 3: Verify**

Run: `flutter analyze 2>&1 | tail -5` → 0 errors.

---

### Task 6: Client — group settings picker → invites + chips

**Files:**
- Modify: `lib/features/groups/screens/group_settings_screen.dart` — `_showAddMemberSheet` (line ~122), button label/callsite at line ~169

**Interfaces:**
- Consumes: `sendGroupInvite`, `getInviteStatusesForConversation`; produces: UI behavior only.

- [ ] **Step 1: Sheet changes**

In `_showAddMemberSheet`:

1. Fetch statuses at sheet open: `final inviteStatuses = await ref.read(messageRepositoryProvider).getInviteStatusesForConversation(widget.conversation.id);` (before `showModalBottomSheet`).
2. Button text: `'Invite ${selected.length}'` (and for zero: keep disabled state).
3. Per-row trailing chip inside the `CheckboxListTile` (use the `subtitle:` slot for status when present):

```dart
  subtitle: inviteStatuses[u.id] == 'pending'
      ? const Text('Invite pending',
          style: TextStyle(color: Colors.orange, fontSize: 12))
      : inviteStatuses[u.id] == 'declined'
          ? const Text('Declined — invite again?',
              style: TextStyle(color: Colors.red, fontSize: 12))
          : Text('@${u.username}'),
```

4. Replace the add loop (line ~169) with:

```dart
                              for (final id in selected) {
                                try {
                                  await ref
                                      .read(messageRepositoryProvider)
                                      .sendGroupInvite(
                                          widget.conversation.id, id);
                                } catch (e) {
                                  debugPrint('[Group] invite error: $e');
                                }
                              }
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Invite(s) sent')),
                                );
                              }
```

(SnackBars after `Navigator.pop(ctx)` — use the outer `context`, guarded by `ctx.mounted` checks as the file already does.)

- [ ] **Step 2: Verify**

Run: `flutter analyze 2>&1 | tail -5` → 0 errors.

---

### Task 7: Client — FCM group_invite branches

**Files:**
- Modify: `lib/services/fcm_service.dart` — `_handleForegroundMessage` (line ~150), `handleBackgroundMessage` (line ~189), add `_showGroupInviteNotification`

**Interfaces:**
- Consumes: FCM data `{type: 'group_invite', invite_id, conversation_id, conversation_name, inviter_name}` (Task 2 produces it).

- [ ] **Step 1: Branches**

In BOTH handlers, directly after the `friend_request` branch:

```dart
    if (type == 'group_invite') {
      await _showGroupInviteNotification(data);
      return;
    }
```

- [ ] **Step 2: Notification builder** (model: `_showFriendRequestNotification`)

```dart
  static Future<void> _showGroupInviteNotification(
      Map<String, dynamic> data) async {
    try {
      await _ensureNotifications();
      final inviterName = (data['inviter_name'] as String?)?.trim();
      final convName    = (data['conversation_name'] as String?)?.trim();
      final title = 'Group invite';
      final body = (inviterName != null && inviterName.isNotEmpty)
          ? '$inviterName invited you to ${convName ?? 'a group'}'
          : 'You were invited to ${convName ?? 'a group'}';
      await _localNotifications.show(
        (data['invite_id'] as String? ?? 'inv').hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _reqChannelId, _reqChannelName,
            importance: Importance.defaultImportance,
            priority:   Priority.defaultPriority,
          ),
        ),
        payload: 'friend_requests',  // opens the Requests screen
      );
    } catch (e) {
      debugPrint('[FCM] showGroupInviteNotification: $e');
    }
  }
```

- [ ] **Step 3: Verify**

Run: `flutter analyze 2>&1 | tail -5` → 0 errors. Check the payload-tap routing: existing tap handling maps payload 'friend_requests' → `AppRoutes.friendRequests` (the same route now renders invites).

---

### Task 8: Build, install, 2-device verification

**Files:** none (verification + the deferred commit)

- [ ] **Step 1: Build**

Run: `flutter build apk --debug 2>&1 | tail -3`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (JDK 21 pinned via flutter config).

- [ ] **Step 2: Install + launch both phones**

```bash
adb -s RFCRA047WSJ install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s c7e9f10e install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCRA047WSJ shell am start -n com.chai.kuch_bhi/.MainActivity
adb -s c7e9f10e shell am start -n com.chai.kuch_bhi/.MainActivity
```
Expected: Success ×2.

- [ ] **Step 3: USER 2-device pass (pass criteria from spec)**

1. Admin (Samsung) → group settings → Add to Group → pick Redmi user → "Invite(s) sent". Redmi: push arrives (kb_requests) + Requests screen shows invite card.
2. Redmi accepts → instantly a member; group appears; can send; Samsung sees auto-rotation happen (logcat or simply: Redmi's message is readable on Samsung); "Redmi joined the group" bubble appears once on both.
3. Decline path: re-invite → decline → Samsung picker shows "Declined — invite again?" chip → re-invite works.
4. Remove still works (re-test #17 end-to-end) AND removing a user with a pending invite kills the invite (they cannot accept afterwards — expect "Failed to accept" snackbar or a silent no-op row-check: verify the invite is gone server-side).
5. Regression sweep: receipts, system bubbles, live media in groups.

- [ ] **Step 4: Single commit after user PASS**

Clean junk untracked files first (`current_task.md`, `current_task_backup.md`, `cd home chaitanyadhotre.txt`, `https store steampowered.txt`, session transcript `.txt` — confirm with user before deleting), then:

```bash
git add lib/ test/ docs/
git commit -m "$(cat <<'EOF'
[Groups] Invite-based joins — consent flow, auto-rotate, FCM push; #17 server rules

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

`git status` before add — review nothing suspicious; the tree also carries the #16–#20 fixes from the prior session, which is intended (single verify gate).

---

## Self-Review (done at plan time)

- Spec coverage: uniform invites ✓ (picker Task 6; creation flow untouched per spec's client section); friend-request-style UX ✓ (Task 5); self-join + auto-rotate ✓ (Task 3 accept + Task 4 rotate); invite purge on remove ✓ (Task 4.3); FCM ✓ (Task 2 + 7); UNIQUE re-invite ✓ (Task 3 sendGroupInvite idempotent PATCH); probes ✓ (Task 1.3); pass criteria ✓ (Task 8.3).
- Known limitation carried in spec: key-gap when no admin device online between accept and rotation — bounded 30s poll + resume retry (`_pendingJoinEmitConvIds`) covers the bubble; message readability converges on first admin app-open (sync-discovery rotate, Task 4.2).
- Type consistency: `GroupInvite` fields match across entity/provider/UI; `sendGroupInvite`/`acceptGroupInvite`/`declineGroupInvite`/`getIncomingGroupInvites`/`getInviteStatusesForConversation` names consistent in interface, impl, and UI call sites.
