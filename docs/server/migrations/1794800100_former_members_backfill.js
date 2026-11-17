/// <reference path="../pb_data/types.d.ts" />
// former-member-history.md D-5 back-fill (user yes 2026-11-17). For each (group, person) with own
// group_keys rows, no member row, and a newer key version wrapped for someone else:
// history_until = first newer version's created (the rotation that shut them out),
// joined_at = their earliest key row, reason blank. Pairs with no newer version are skipped.
// Down deletes only rows with a blank reason (the hook always sets one).
const SQL = `
select k.conversation_id conv, k.user_id usr, min(k.created) joined,
  (select min(n.created) from group_keys n where n.conversation_id = k.conversation_id
     and n.key_version > (select max(x.key_version) from group_keys x
       where x.conversation_id = k.conversation_id and x.user_id = k.user_id)) until
from group_keys k join conversations c on c.id = k.conversation_id and c.type = 'group'
join users u on u.id = k.user_id
where not exists (select 1 from conversation_members m where m.conversation_id = k.conversation_id and m.user_id = k.user_id)
  and not exists (select 1 from former_members f where f.conversation_id = k.conversation_id and f.user_id = k.user_id)
group by k.conversation_id, k.user_id
having until is not null`;
migrate((app) => {
  const rows = arrayOf(new DynamicModel({ conv: "", usr: "", joined: "", until: "" }));
  app.db().newQuery(SQL).all(rows);
  const col = app.findCollectionByNameOrId("former_members");
  for (const x of rows) {
    const r = new Record(col);
    r.set("conversation_id", x.conv);
    r.set("user_id", x.usr);
    r.set("joined_at", x.joined);
    r.set("history_until", x.until);
    app.save(r);
  }
  console.log("[former_members] back-filled " + rows.length);
}, (app) => {
  for (const r of app.findRecordsByFilter("former_members", "reason = ''", "", 0, 0)) app.delete(r);
});
