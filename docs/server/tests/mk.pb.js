// TEST COPIES ONLY, never the live hooks folder. Makes n throwaway users on a copy.
// ?p=<chat id> sets current_chat and typing_in on every second user (timing check V9).
routerAdd("POST", "/mk/{n}", (e) => {
  const col = $app.findCollectionByNameOrId("users");
  const n = parseInt(e.request.pathValue("n"));
  const p = e.request.url.query().get("p");
  const out = [];
  for (let i = 0; i < n; i++) {
    const s = $security.randomStringWithAlphabet(10, "abcdefghijklmnopqrstuvwxyz0123456789");
    const pw = $security.randomString(20);
    const code = $security.randomStringWithAlphabet(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789");
    const r = new Record(col);
    r.set("email", "dryrun_" + s + "@example.test");
    r.set("username", "dryrun_" + s);
    r.set("display_name", "dryrun");
    r.set("friend_code", code);
    r.set("verified", true);
    r.setPassword(pw);
    if (p && i % 2 === 1) { r.set("current_chat", p); r.set("typing_in", p); }
    $app.save(r);
    out.push({ id: r.id, email: r.email(), pw: pw, code: code });
  }
  return e.json(200, out);
});
