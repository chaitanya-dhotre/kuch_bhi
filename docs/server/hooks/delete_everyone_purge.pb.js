// Delete for everyone keeps nothing on the server: docs/design/pages/delete-everyone-leftovers.md §5
// (D-11 a) in the app repo. When a message is flagged deleted for everyone, its media rows go
// (PocketBase removes their files) and its body, iv and reply preview are blanked, as is the
// preview any reply holds of it. Direct SQL like disappearing_messages.pb.js: encrypted_body and
// iv are Required, and a saved record would broadcast again. Flat handler (pb-hook-pitfalls).
onRecordAfterUpdateSuccess((e) => {
  if (e.record.getBool('is_deleted_for_everyone')) {
    try {
      const media = $app.findRecordsByFilter('message_media', 'message_id = {:m}', '', 0, 0, { m: e.record.id });
      for (let i = 0; i < media.length; i++) $app.delete(media[i]);
      $app.db()
        .newQuery("UPDATE messages SET encrypted_body = '', iv = '', reply_preview = '' WHERE id = {:id}")
        .bind({ id: e.record.id })
        .execute();
      $app.db()
        .newQuery("UPDATE messages SET reply_preview = '' WHERE reply_to_id = {:id} AND reply_preview != ''")
        .bind({ id: e.record.id })
        .execute();
    } catch (err) {
      console.log('[delete-everyone] purge failed:', String(err));
    }
  }
  return e.next();
}, 'messages');
