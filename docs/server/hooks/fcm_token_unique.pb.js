/// <reference path="../pb_data/types.d.ts" />
// google-link-and-push.md D-4 (audit F25): one push token belongs to one account. When a user's
// row is saved with a token, clear that token on every other row, so a phone that signed out
// offline stops getting the old account's pushes. Direct SQL: no broadcast (the field is hidden).
// shortcut: runs on every users update (presence too) with an unindexed WHERE; fine at this size,
// add an index on fcm_token if users grow past a few thousand.
onRecordAfterUpdateSuccess((e) => {
  const t = e.record.getString("fcm_token");
  if (t) {
    try {
      $app.db().newQuery("UPDATE users SET fcm_token = '' WHERE fcm_token = {:t} AND id != {:id}").bind({ t: t, id: e.record.id }).execute();
    } catch (err) {
      console.log("[fcm-unique] clear failed:", String(err));
    }
  }
  return e.next();
}, "users");
