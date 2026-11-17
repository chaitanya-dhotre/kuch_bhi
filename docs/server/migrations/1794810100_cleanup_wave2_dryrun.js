/// <reference path="../pb_data/types.d.ts" />
// One-off (user go-ahead 2026-11-17): remove the throwaway group and account the wave 2 live
// re-check could not delete. Guarded: does nothing unless both are still the empty dryrun rows.
// app.delete runs the cascades (former_members). No down step: nothing to restore.
migrate((app) => {
  let conv, user;
  try {
    conv = app.findRecordById("conversations", "nk6431fsn5o4964");
    user = app.findRecordById("users", "4rnsndpovj9tn3v");
  } catch (_) { return; }
  if (!user.getString("username").startsWith("dryrun_")) return;
  if (conv.getString("created_by") !== user.id || conv.getString("name") !== "dryrun") return;
  const busy = app.countRecords("conversation_members", $dbx.hashExp({ conversation_id: conv.id }))
    + app.countRecords("messages", $dbx.hashExp({ conversation_id: conv.id }));
  if (busy > 0) return;
  app.delete(conv);
  app.delete(user);
}, (app) => {});
