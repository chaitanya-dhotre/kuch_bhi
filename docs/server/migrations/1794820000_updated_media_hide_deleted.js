/// <reference path="../pb_data/types.d.ts" />
// delete-everyone-leftovers.md §5 (D-11 a): a media row of a message deleted for everyone is no
// longer listed or viewable, and no media can be added to one afterwards (a cancelled send's
// upload still in flight would otherwise leave a public file the purge hook never sees).
// Same forms as before, one clause appended. Down restores the exact old strings (read 2026-11-18).
const DELETED = " && message_id.is_deleted_for_everyone = false";
const OLD_READ = "((conversation_id.conversation_members_via_conversation_id.user_id ?= @request.auth.id) || (conversation_id.former_members_via_conversation_id.user_id ?= @request.auth.id && conversation_id.former_members_via_conversation_id.history_until ?>= message_id.created)) && (message_id.expires_at = \"\" || message_id.expires_at > @now)";
const OLD_CREATE = "message_id.sender_id = @request.auth.id && conversation_id = message_id.conversation_id";

const apply = (app, read, create) => {
  const c = app.findCollectionByNameOrId("message_media");
  c.listRule = read;
  c.viewRule = read;
  c.createRule = create;
  app.save(c);
};
migrate((app) => apply(app, OLD_READ + DELETED, OLD_CREATE + DELETED), (app) => apply(app, OLD_READ, OLD_CREATE));
