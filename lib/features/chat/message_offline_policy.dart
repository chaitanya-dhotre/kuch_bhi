/// P4 (user ruling 2): defined-offline contract for message context-menu
/// actions. "Unwired" must never mean a silent no-op that looks like it
/// worked — network-only actions are DISABLED offline with a visible hint.
///
/// Pure policy (no imports) so the contract is unit-testable and the menu
/// stays a thin renderer. Wired offline today (durable local write,
/// fetch/SSE preserve the flag):
/// - star       — Drift `is_starred` written before best-effort PB sync
///                (P4 ruling 1; pinned by test/offline/star_offline_test.dart)
/// - deleteMe   — local tombstone, preserved across re-caches
/// - reply/copy — pure local UI
/// - react      — Drift row + outbox op; server reads keep queued ops
///                (user, 2026-10-30: reactions work like the rest of an
///                offline-first app)
/// Still network-only (post-merge backlog wires them properly):
/// - pin              — local write exists but fetch/SSE clobbers from
///                      server truth → offline pin silently reverts
/// - deleteForEveryone — server-first; local mark reverted by next fetch
library;

/// Every action exposed by the message long-press menu.
enum MessageAction { star, pin, deleteForMe, deleteForEveryone, react, reply, copy }

/// Hint shown on disabled controls / snackbars when an action is blocked
/// offline. Single string — the user-visible half of the contract.
const String kOfflineActionHint = 'Available online';

/// True when [action] cannot complete while offline (no durable local
/// path that survives server-truth sync).
bool messageActionRequiresOnline(MessageAction action) => switch (action) {
      MessageAction.pin || MessageAction.deleteForEveryone => true,
      MessageAction.react ||
      MessageAction.star ||
      MessageAction.deleteForMe ||
      MessageAction.reply ||
      MessageAction.copy =>
        false,
    };

/// Whether the menu must let [action] proceed. Online → always enabled;
/// offline → only durable-local actions.
bool isMessageActionEnabled(MessageAction action, {required bool isOnline}) =>
    isOnline || !messageActionRequiresOnline(action);
