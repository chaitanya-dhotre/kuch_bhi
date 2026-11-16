/// <reference path="../pb_data/types.d.ts" />
// membership-rules.md H2: the five users fields are schema-hidden (no response, no filter).
// Put them back for the owner; current_chat / typing_in also for a member of that same chat.
// Replaces key_backup_hide.pb.js. Flat body, direct e.next() (pb-hook pitfall 1).
onRecordEnrich((e) => {
  const auth = e.requestInfo ? e.requestInfo.auth : null;
  if (!auth) return e.next();
  if (auth.id === e.record.id) {
    e.record.unhide("current_chat", "typing_in", "fcm_token", "private_key_encrypted", "private_key_salt");
    return e.next();
  }
  for (const f of ["current_chat", "typing_in"]) {
    const v = e.record.getString(f);
    if (!v) continue;
    try {
      $app.findFirstRecordByFilter("conversation_members", "conversation_id = {:c} && user_id = {:u}", { c: v, u: auth.id });
      e.record.unhide(f);
    } catch (_) {
      // not a member of that chat: keep it hidden
    }
  }
  return e.next();
}, "users");

// PocketBase drops hidden fields from a non-superuser's update body, requestInfo.body included
// (dry run 2026-11-16: PATCH 200, value unchanged). The owner's own update re-reads the raw
// body and writes them back. "\u0000" marks a field the request did not send.
onRecordUpdateRequest((e) => {
  if (!e.auth || e.auth.id !== e.record.id) return e.next();
  const b = new DynamicModel({ current_chat: "\u0000", typing_in: "\u0000", fcm_token: "\u0000", private_key_encrypted: "\u0000", private_key_salt: "\u0000" });
  try {
    e.bindBody(b);
  } catch (_) {
    return e.next(); // unreadable body: leave the hidden fields as they are
  }
  for (const f of ["current_chat", "typing_in", "fcm_token", "private_key_encrypted", "private_key_salt"]) {
    if (b[f] !== "\u0000") e.record.set(f, b[f]);
  }
  return e.next();
}, "users");
