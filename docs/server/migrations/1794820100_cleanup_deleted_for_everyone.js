/// <reference path="../pb_data/types.d.ts" />
// One-off (delete-everyone-leftovers.md §5, D-11 a): messages deleted for everyone before the
// delete_everyone_purge hook went live lose their media (app.delete removes the files), body, iv
// and reply preview, and replies quoting them lose their preview. L6 read 2026-11-18: 35 messages,
// 8 media rows, 2 quoting previews. Guarded: touches only flagged rows and their replies, and
// refuses (the migration fails and changes nothing) if far more rows are flagged than expected.
// No down step: blanked ciphertext and deleted files cannot be restored (the dated backup can).
migrate((app) => {
  const gone = app.findRecordsByFilter("messages", "is_deleted_for_everyone = true", "", 0, 0);
  if (gone.length > 200) throw new Error("cleanup guard: " + gone.length + " flagged messages, expected about 35");
  let media = 0;
  for (let i = 0; i < gone.length; i++) {
    const rows = app.findRecordsByFilter("message_media", "message_id = {:m}", "", 0, 0, { m: gone[i].id });
    for (let j = 0; j < rows.length; j++) { app.delete(rows[j]); media++; }
  }
  const quotes = app.db().newQuery("UPDATE messages SET reply_preview = '' WHERE reply_preview != '' AND reply_to_id IN (SELECT id FROM messages WHERE is_deleted_for_everyone = 1)").execute().rowsAffected();
  const bodies = app.db().newQuery("UPDATE messages SET encrypted_body = '', iv = '', reply_preview = '' WHERE is_deleted_for_everyone = 1 AND (encrypted_body != '' OR iv != '' OR reply_preview != '')").execute().rowsAffected();
  console.log("[cleanup] flagged", gone.length, "blanked", bodies, "media deleted", media, "quotes blanked", quotes);
}, (app) => {});
