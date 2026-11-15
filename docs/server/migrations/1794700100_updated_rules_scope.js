/// <reference path="../pb_data/types.d.ts" />
// server-rules.md N1-N9: tie each rule to the row's own chat / message / user.
const apply = (app, set) => {
  for (const name in set) {
    const c = app.findCollectionByNameOrId(name);
    for (const k in set[name]) c[k] = set[name][k];
    app.save(c);
  }
};
migrate((app) => apply(app, {
  "conversations": {
    "listRule": "created_by = @request.auth.id || (@collection.conversation_members.conversation_id ?= id && @collection.conversation_members.user_id ?= @request.auth.id) || (@collection.group_invites.conversation_id ?= id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\")",
    "viewRule": "created_by = @request.auth.id || (@collection.conversation_members.conversation_id ?= id && @collection.conversation_members.user_id ?= @request.auth.id) || (@collection.group_invites.conversation_id ?= id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\")",
    "updateRule": "(@collection.conversation_members.conversation_id ?= id && @collection.conversation_members.user_id ?= @request.auth.id) && @request.body.created_by:isset = false && @request.body.type:isset = false"
  },
  "conversation_members": {
    "listRule": "@request.auth.id = user_id || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id)"
  },
  "message_receipts": {
    "listRule": "@request.auth.id = recipient_id || (@collection.messages.id ?= message_id && @collection.messages.sender_id ?= @request.auth.id)",
    "createRule": "@request.auth.id = recipient_id || ((@collection.messages.id ?= message_id && @collection.messages.sender_id ?= @request.auth.id) && delivered_at = \"\" && read_at = \"\")",
    "updateRule": "@request.auth.id = recipient_id && @request.body.message_id:isset = false && @request.body.conversation_id:isset = false && @request.body.recipient_id:isset = false"
  },
  "message_media": {
    "createRule": "message_id.sender_id = @request.auth.id"
  },
  "starred_messages": {
    "createRule": "@request.auth.id = user_id"
  },
  "deleted_messages_for_me": {
    "createRule": "@request.auth.id = user_id"
  },
  "polls": {
    "listRule": "(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id)",
    "viewRule": "(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id)",
    "updateRule": "(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id)"
  }
}), (app) => apply(app, {
  "conversations": {
    "listRule": "@collection.conversation_members.user_id ?= @request.auth.id",
    "viewRule": "@collection.conversation_members.user_id ?= @request.auth.id",
    "updateRule": "@collection.conversation_members.user_id ?= @request.auth.id"
  },
  "conversation_members": {
    "listRule": "@request.auth.id = user_id || @collection.conversation_members.user_id ?= @request.auth.id"
  },
  "message_receipts": {
    "listRule": "@request.auth.id = recipient_id || @collection.messages.sender_id ?=\n@request.auth.id",
    "createRule": "@request.auth.id != \"\"",
    "updateRule": "@request.auth.id = recipient_id"
  },
  "message_media": {
    "createRule": "@request.auth.id != \"\""
  },
  "starred_messages": {
    "createRule": "@request.auth.id != \"\""
  },
  "deleted_messages_for_me": {
    "createRule": "@request.auth.id != \"\""
  },
  "polls": {
    "listRule": "@collection.conversation_members.user_id ?= @request.auth.id",
    "viewRule": "@collection.conversation_members.user_id ?= @request.auth.id",
    "updateRule": "@collection.conversation_members.user_id ?= @request.auth.id"
  }
}));
