/// <reference path="../pb_data/types.d.ts" />
// google-link-and-push.md D-3 (audit F24): Google sign-ups were created with a public email.
// The app never sets emailVisibility, so every row that has it on came from that hook.
// One-off data change; down is a no-op (which rows were on is not worth restoring).
migrate((app) => {
  app.db().newQuery("UPDATE users SET emailVisibility = 0 WHERE emailVisibility = 1").execute();
}, (app) => {});
