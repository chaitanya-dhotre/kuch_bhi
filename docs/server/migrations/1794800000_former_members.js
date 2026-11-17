/// <reference path="../pb_data/types.d.ts" />
// former-member-history.md S1 (former_members, written only by former_member_record.pb.js)
// + S3 R1-R3 (read-only branches with a server time limit). Down restores the exact old rules.
// Back-relation form (conversation_id.X_via_conversation_id) for BOTH branches: an `||` of two
// @collection joins took 5 s for 2,000 rows on a copy; this form took 115 ms (old rule: 183 ms).
// Same meaning as the old member branch: some member row of this row's chat is mine.
const FM = (t) => `(conversation_id.former_members_via_conversation_id.user_id ?= @request.auth.id && conversation_id.former_members_via_conversation_id.history_until ?>= ${t})`;
const MEMBER_OLD = "(@collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.conversation_id ?= conversation_id)";
const MEMBER_NEW = "(conversation_id.conversation_members_via_conversation_id.user_id ?= @request.auth.id)";
const CONV_OLD = "created_by = @request.auth.id || (@collection.conversation_members.conversation_id ?= id && @collection.conversation_members.user_id ?= @request.auth.id) || (@collection.group_invites.conversation_id ?= id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\")";
const CONV_NEW = CONV_OLD + " || (former_members_via_conversation_id.user_id ?= @request.auth.id)";
const MSG_OLD = MEMBER_OLD + " && (expires_at = \"\" || expires_at > @now)";
const MSG_NEW = "(" + MEMBER_NEW + " || " + FM("created") + ") && (expires_at = \"\" || expires_at > @now)";
const MEDIA_OLD = MEMBER_OLD + " && (message_id.expires_at = \"\" || message_id.expires_at > @now)";
const MEDIA_NEW = "(" + MEMBER_NEW + " || " + FM("message_id.created") + ") && (message_id.expires_at = \"\" || message_id.expires_at > @now)";
const apply = (app, set) => {
  for (const name in set) {
    const c = app.findCollectionByNameOrId(name);
    c.listRule = set[name];
    c.viewRule = set[name];
    app.save(c);
  }
};
migrate((app) => {
  const own = "user_id = @request.auth.id";
  app.save(new Collection({
    type: "base",
    name: "former_members",
    listRule: own,
    viewRule: own,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "conversation_id", type: "relation", required: true, collectionId: app.findCollectionByNameOrId("conversations").id, cascadeDelete: true, maxSelect: 1 },
      { name: "user_id", type: "relation", required: true, collectionId: app.findCollectionByNameOrId("users").id, cascadeDelete: true, maxSelect: 1 },
      { name: "joined_at", type: "date" },
      { name: "history_until", type: "date" },
      { name: "reason", type: "select", values: ["left", "removed"], maxSelect: 1 },
      { name: "created", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_former_members_conv_user` ON `former_members` (`conversation_id`, `user_id`)"],
  }));
  apply(app, { conversations: CONV_NEW, messages: MSG_NEW, message_media: MEDIA_NEW });
}, (app) => {
  apply(app, { conversations: CONV_OLD, messages: MSG_OLD, message_media: MEDIA_OLD });
  app.delete(app.findCollectionByNameOrId("former_members"));
});
