// TEST COPIES ONLY, never the live hooks folder. former-member-history dry run helpers.
// GET /sutok: a superuser token (F16, and reading former_members as the server sees it).
routerAdd("GET", "/sutok", (e) => {
  const r = $app.findAllRecords("_superusers")[0];
  return e.json(200, { token: r.newAuthToken() });
});
// POST /bulk/{conv}/{sender}/{n}: n text messages in one transaction (F18 timing).
routerAdd("POST", "/bulk/{conv}/{sender}/{n}", (e) => {
  const conv = e.request.pathValue("conv");
  const sender = e.request.pathValue("sender");
  const n = parseInt(e.request.pathValue("n"));
  $app.runInTransaction((tx) => {
    const col = tx.findCollectionByNameOrId("messages");
    for (let i = 0; i < n; i++) {
      const r = new Record(col);
      r.set("conversation_id", conv);
      r.set("sender_id", sender);
      r.set("type", "text");
      r.set("encrypted_body", "ZHJ5cnVuLWJ1bGstYm9keS1wYWRkaW5nLXBhZGRpbmctcGFkZGluZy1wYWRkaW5nLXBhZGRpbmc=");
      r.set("iv", "ZHJ5cnVuaXZkcnlydW4=");
      tx.save(r);
    }
  });
  return e.json(200, { n: n });
});
