import '../decrypt/device_key_store.dart';

/// Group-history visibility (spec D1): non-media rows whose body cannot
/// resolve yet are hidden entirely — ciphertext must never reach a bubble.
///
/// Before this member's current join time (rejoin spec H1), a row shows only
/// when it opens (`ready` / `device_sealed`), media included. A re-joiner's
/// first stint opens with the key versions they were given then (removal
/// keeps their key rows); versions made while they were out are never
/// wrapped for them, and a brand-new joiner holds none from before their
/// join — so the keys, not a stored first-join time, draw the line.
///
/// T9 (column dropped): the gate is now `decryptState`, the row-level
/// projection of the same rule —
///  - `ready` (spec §5.1: "a body read WILL succeed") → visible; the body
///    itself arrives via `messageBodyProvider` (placeholder while it
///    resolves — never a blank);
///  - `pending` / `key_missing` / `failed` → hidden, exactly as a
///    null/empty `decryptedBody` row was hidden pre-drop;
///  - media rows after the join are exempt (their body is optional).
///
/// P8 (`device_sealed`): visible. The body IS present and decryptable — it
/// is wrapped with the device-local key rather than the conversation key, so
/// `messageBodyProvider` resolves it through the ordinary unwrap path. It is
/// NOT in the "cannot resolve" set, so hiding it would make a message the
/// user JUST SENT vanish from their own chat.
///
/// Own optimistic rows carry the column default `ready` (enqueue never
/// writes state) — they stay visible, same as the plaintext they held.
bool isGroupRowVisible({
  required DateTime createdAt,
  required DateTime? memberJoinedAt,
  required String decryptState,
  required String type,
}) {
  final opens = decryptState == 'ready' || decryptState == kDeviceSealedState;
  if (memberJoinedAt != null && createdAt.isBefore(memberJoinedAt)) {
    return opens;
  }
  const mediaTypes = {'image', 'video', 'voice', 'document', 'file'};
  return opens || mediaTypes.contains(type);
}
