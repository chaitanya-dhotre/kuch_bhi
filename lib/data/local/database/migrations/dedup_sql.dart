/// Dedupes messages rows sharing one serverId before the UNIQUE index is
/// created (schema v6). Keeps the OLDEST row per serverId (rowid order) —
/// the main-isolate original, which carries decrypted state; the FCM
/// background isolate's placeholder row is the later insert.
class DedupBeforeUniqueIndex {
  static const sql =
      "DELETE FROM messages_table WHERE server_id IS NOT NULL AND rowid NOT IN "
      "(SELECT MIN(rowid) FROM messages_table WHERE server_id IS NOT NULL "
      "GROUP BY server_id)";
}
