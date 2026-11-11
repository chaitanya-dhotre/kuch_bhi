/// Copy strings the app shows in more than one place (dead-code audit §3).
/// One row per string: import the const, never re-type the text. Everything
/// here is user-visible — a change to a value is a copy change, not a
/// refactor.
library;

// ── Offline strip (I1) — one strip, two scopes. General pages stay
//    contact/search-only; the surfaces that can queue a send promise that
//    the queue flushes on reconnect.
const kOfflineActionsCopy =
    "You're offline — actions are available when you're back.";
const kOfflineSendCopy =
    "You're offline — messages will send when you're back.";

// ── Plain media row labels (§3.5): the icon rows in starred/media lists,
//    bubble retry banners and reply previews.
const kMediaRowPhotoLabel = 'Photo';
const kMediaRowVideoLabel = 'Video';
const kMediaRowVoiceLabel = 'Voice message';
const kMediaRowDocumentLabel = 'Document';

// ── Emoji glyph labels (§3.5): per-type preview glyphs. The one type→label
//    mapping lives in `conversationPreviewLabel` (C9, message_body_text.dart);
//    these are its strings, quoted so the reply quote, pinned banner and the
//    repo's reply-preview builder don't re-type them.
const kPreviewPhotoLabel = '📷 Photo';
const kPreviewVideoLabel = '🎬 Video';
const kPreviewVoiceLabel = '🎤 Voice message';
const kPreviewDocumentLabel = '📎 Document';

// ── Failure copy (§3.7) — toasts and empty-state subtitles.
const kUpdateFailedCopy = "Couldn't update. Try again.";
const kSaveFailedCopy = "Couldn't save. Try again.";
const kLoadFriendsFailedCopy = "Couldn't load friends.";
const kConnectionRetryCopy = 'Check your connection and try again.';

// ── Quoted voice row (§3.8): the row body is a typed `m:ss` duration.
String voiceMessageRowCopy(String dur) => 'Voice message · $dur';

// ── Group admin (§3.9): the moderation toast and the mirrored system
//    message body must stay one string.
String adminPromotedCopy(String name) => '$name is now an admin';
String adminDemotedCopy(String name) => '$name is no longer an admin';

/// K3 (mascot spec §G3): the card after a remove; the remove already rotated
/// the group key.
String groupKeyRotatedCopy(String name) =>
    "New group key made. $name can't read new messages.";

// ── Shared buttons / empty states (§3.11).
const kAddFriendCtaLabel = 'Add a Friend';
const kNoPendingRequestsCopy = 'No pending requests';
const kSystemDefaultLabel = 'System default';
