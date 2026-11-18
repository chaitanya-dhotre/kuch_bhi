/// <reference path="../pb_data/types.d.ts" />
// One-off, 2026-11-19: remove the break-ui throwaway accounts (3 + the orphaned
// "qqq") and the 4 test chats they share with Pixel Chait. The API can't delete
// them: receipts and group-key rows point at them with no cascade.
// Guarded: every account must be a kb-breakui-*@example.com sign-up, and every
// chat may hold only Pixel Chait and those accounts. Anything else aborts the
// whole migration (it runs in one transaction).
const IDS = ["vqokglpqt81gs7c", "e9uzqhs8zucznt8", "9za5vlstbf7cee7"];
const EMAIL = /^kb-breakui-[0-9a-f]{8}@example\.com$/;
const PIXEL_CODE = "OGN22P";
const CAP = 600;

migrate((app) => {
  let deleted = 0;
  const counts = {};
  const relationRefs = (collectionId) => {
    const refs = [];
    for (const c of app.findAllCollections()) {
      if (c.system) continue;
      for (const f of c.fields) {
        if (f.type() === "relation" && f.collectionId === collectionId) {
          refs.push({ coll: c.name, field: f.name, multi: f.maxSelect > 1 });
        }
      }
    }
    return refs;
  };
  // Delete everything that points at `rec` (re-scanning, since delete hooks may
  // write new rows such as former_members), then the record itself.
  const deleteDeep = (rec) => {
    const refs = relationRefs(rec.collection().id);
    for (let pass = 0; pass < 5; pass++) {
      let found = 0;
      for (const r of refs) {
        const op = r.multi ? "~" : "=";
        const kids = app.findRecordsByFilter(r.coll, `${r.field} ${op} {:id}`, "", 0, 0, { id: rec.id });
        for (const k of kids) { found++; deleteDeep(k); }
      }
      if (found === 0) break;
    }
    app.delete(rec);
    deleted++;
    counts[rec.collection().name] = (counts[rec.collection().name] || 0) + 1;
    if (deleted > CAP) throw new Error("cleanup: over cap, aborting");
  };

  const users = IDS.map((id) => app.findRecordById("users", id));
  try { users.push(app.findFirstRecordByData("users", "username", "qqq")); } catch (_) {}
  for (const u of users) {
    if (!EMAIL.test(u.getString("email"))) throw new Error("cleanup: not a throwaway: " + u.id);
  }
  const targets = new Set(users.map((u) => u.id));
  const pixel = app.findFirstRecordByData("users", "friend_code", PIXEL_CODE).id;

  const chatIds = new Set();
  for (const u of users) {
    for (const m of app.findRecordsByFilter("conversation_members", "user_id = {:id}", "", 0, 0, { id: u.id })) {
      chatIds.add(m.getString("conversation_id"));
    }
  }
  for (const cid of chatIds) {
    for (const m of app.findRecordsByFilter("conversation_members", "conversation_id = {:id}", "", 0, 0, { id: cid })) {
      const uid = m.getString("user_id");
      if (uid !== pixel && !targets.has(uid)) throw new Error("cleanup: chat " + cid + " has a real member " + uid);
    }
  }
  console.log("[cleanup] users", users.length, "chats", chatIds.size);
  for (const cid of chatIds) deleteDeep(app.findRecordById("conversations", cid));
  for (const u of users) deleteDeep(u);
  console.log("[cleanup] deleted", deleted, JSON.stringify(counts));
}, (app) => {
  // Nothing to restore: the backup taken before this ran is the way back.
});
