/// <reference path="../pb_data/types.d.ts" />
// membership-rules.md M1-M3 (strangers can't join a group) + H1 (hide presence, push token and key backup on users).
const HIDE = ["current_chat", "typing_in", "fcm_token", "private_key_encrypted", "private_key_salt"];
const apply = (app, set, hidden) => {
  for (const name in set) {
    const c = app.findCollectionByNameOrId(name);
    for (const k in set[name]) c[k] = set[name][k];
    app.save(c);
  }
  const u = app.findCollectionByNameOrId("users");
  for (const f of HIDE) u.fields.getByName(f).hidden = hidden;
  app.save(u);
};
migrate((app) => apply(app, {
  "conversation_members": {
    "createRule": "@request.auth.id != \"\" && (@request.auth.id = conversation_id.created_by || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\") || (@request.auth.id = user_id && @collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\" && @request.body.role = \"member\"))",
    "updateRule": "@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\" && @request.body.user_id:isset = false && @request.body.conversation_id:isset = false"
  },
  "group_invites": {
    "updateRule": "(invited_user_id = @request.auth.id && @request.body.conversation_id:isset = false && @request.body.invited_user_id:isset = false && @request.body.invited_by:isset = false && (@request.body.status = \"accepted\" || @request.body.status = \"declined\")) || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\" && @request.body.conversation_id:isset = false && @request.body.invited_user_id:isset = false && @request.body.invited_by:isset = false)"
  }
}, true), (app) => apply(app, {
  "conversation_members": {
    "createRule": "@request.auth.id != \"\" && (@request.auth.id = conversation_id.created_by || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\") || (@request.auth.id = user_id && @collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\"))",
    "updateRule": "(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\" && @request.body.user_id:isset = false && @request.body.conversation_id:isset = false) || (user_id = @request.auth.id && @request.body.role:isset = false)"
  },
  "group_invites": {
    "updateRule": "(invited_user_id = @request.auth.id && @request.body.conversation_id:isset = false && @request.body.invited_user_id:isset = false && @request.body.invited_by:isset = false) || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\")"
  }
}, false));
