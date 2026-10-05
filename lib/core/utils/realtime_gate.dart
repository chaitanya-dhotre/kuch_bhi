/// Whether an authStore change requires rebuilding the realtime
/// subscriptions: only when the logged-in IDENTITY changes (logout, login,
/// account switch) — never when PocketBase merely rotates the token string
/// for the same session (authRefresh), which was rebuilding the SSE client
/// on every navigation (~54x/25min, losing events in every window).
bool shouldReconnectRealtime({
  required bool wasAuthenticated,
  required bool isAuthenticated,
  required String? previousUserId,
  required String? newUserId,
}) {
  if (!isAuthenticated) return true; // logout — tear down
  if (!wasAuthenticated) return true; // login — connect
  // Same live session: refresh events may precede the persisted-id write,
  // so an unresolvable id is churn, not a switch.
  if (newUserId == null) return false;
  return previousUserId != newUserId;
}
