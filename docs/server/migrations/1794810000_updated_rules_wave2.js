/// <reference path="../pb_data/types.d.ts" />
// server-rules-wave2.md N10-N18: who may add you to a chat (friends only, creator's own first row),
// friend requests and friendships, reactions, media chat id, unused polls/scheduled_messages.
// Member and friendship checks use back-relations: an `||` of @collection joins gets slow as the
// joined table grows (former-member-history F18). Down restores the exact old strings (bible §7).
const NOW_MEMBERS = "conversation_id.conversation_members_via_conversation_id";
const N11 = "@request.auth.id != \"\" && ("
  // 1: the creator's own first row, while the chat has no member rows yet (closes membership D-3).
  // A bare != on @collection is checked against ALL rows: "no member row is in this chat".
  // (`<back-relation>:length = 0` is refused on 0.37.5: "unknown field".)
  + "(@request.auth.id = conversation_id.created_by && @request.auth.id = user_id && @request.body.role = \"admin\" && @collection.conversation_members:existing.conversation_id != conversation_id)"
  // 2: an admin adds a friend, as a member
  + " || (" + NOW_MEMBERS + ".user_id ?= @request.auth.id && " + NOW_MEMBERS + ".role ?= \"admin\" && @request.body.role = \"member\""
  + " && (user_id.friendships_via_user_a.user_b ?= @request.auth.id || user_id.friendships_via_user_b.user_a ?= @request.auth.id))"
  // 3: an invitee joins, as a member (unchanged meaning)
  + " || (@request.auth.id = user_id && conversation_id.group_invites_via_conversation_id.invited_user_id ?= @request.auth.id && conversation_id.group_invites_via_conversation_id.status ?= \"pending\" && @request.body.role = \"member\"))";

const UP = {
  conversations: { createRule: "@request.auth.id != \"\" && @request.body.created_by = @request.auth.id" },
  conversation_members: { createRule: N11 },
  friendships: { createRule: "@request.auth.id = user_a && @collection.friend_requests.from_user ?= user_b && @collection.friend_requests.to_user ?= @request.auth.id && @collection.friend_requests.status ?= \"accepted\"" },
  friend_requests: {
    createRule: "@request.auth.id = from_user && @request.auth.id != to_user && @request.body.status = \"pending\"",
    updateRule: "@request.auth.id = to_user && status = \"pending\" && @request.body.from_user:isset = false && @request.body.to_user:isset = false && (@request.body.status = \"accepted\" || @request.body.status = \"declined\")",
  },
  reactions: {
    createRule: "@request.auth.id = user_id && @collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.messages.id ?= message_id && @collection.messages.conversation_id ?= conversation_id",
    updateRule: null,
  },
  message_media: { createRule: "message_id.sender_id = @request.auth.id && conversation_id = message_id.conversation_id" },
  polls: { createRule: null, updateRule: null, deleteRule: null },
  scheduled_messages: { createRule: null, updateRule: null, deleteRule: null },
};

const DOWN = {
  conversations: { createRule: "@request.auth.id != \"\"" },
  conversation_members: { createRule: "@request.auth.id != \"\" && (@request.auth.id = conversation_id.created_by || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= \"admin\") || (@request.auth.id = user_id && @collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= \"pending\" && @request.body.role = \"member\"))" },
  friendships: { createRule: "@request.auth.id = user_a" },
  friend_requests: {
    createRule: "@request.auth.id = from_user && @request.auth.id != to_user",
    updateRule: "@request.auth.id = to_user && status = \"pending\"",
  },
  reactions: { createRule: "@request.auth.id = user_id", updateRule: "@request.auth.id = user_id" },
  message_media: { createRule: "message_id.sender_id = @request.auth.id" },
  polls: {
    createRule: "@request.auth.id = created_by",
    updateRule: "(@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id)",
    deleteRule: "@request.auth.id = created_by",
  },
  scheduled_messages: { createRule: "@request.auth.id = sender_id", updateRule: "@request.auth.id = sender_id", deleteRule: "@request.auth.id = sender_id" },
};

const apply = (app, set) => {
  for (const name in set) {
    const c = app.findCollectionByNameOrId(name);
    for (const k in set[name]) c[k] = set[name][k];
    app.save(c);
  }
};
migrate((app) => apply(app, UP), (app) => apply(app, DOWN));
