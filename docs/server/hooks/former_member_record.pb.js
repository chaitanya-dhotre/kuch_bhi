/// <reference path="../pb_data/types.d.ts" />
// former-member-history.md S2: a deleted group member row leaves a former_members record
// (read-only history up to the server time of the delete). Flat body (pb-hook pitfall 1).
// Cascade deletes (group or account deleted) skip request hooks, so they never write one.
onRecordDeleteRequest((e) => {
  const conv = e.record.getString("conversation_id");
  const user = e.record.getString("user_id");
  const joined = e.record.getString("joined_at") || e.record.getString("created");
  const reason = e.auth && e.auth.id === user ? "left" : "removed";
  e.next(); // throws if the delete fails: nothing is written then
  try {
    if ($app.findRecordById("conversations", conv).getString("type") !== "group") return;
    let r;
    try {
      r = $app.findFirstRecordByFilter("former_members", "conversation_id = {:c} && user_id = {:u}", { c: conv, u: user });
    } catch (_) {
      r = new Record($app.findCollectionByNameOrId("former_members"));
      r.set("conversation_id", conv);
      r.set("user_id", user);
    }
    const had = r.getString("joined_at");
    if (!had || (joined && joined < had)) r.set("joined_at", joined); // keep the earliest
    r.set("history_until", new DateTime()); // server clock; a later removal moves it forward (D-8)
    r.set("reason", reason);
    $app.save(r);
  } catch (err) {
    console.log("[former_members] " + conv + " " + user + ": " + err);
  }
}, "conversation_members");
