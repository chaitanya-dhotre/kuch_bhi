// Runs daily at 2am — deletes expired message_media records (and their files).
// PocketBase v0.37.5 JSVM API ($app.* — the old $app.dao() was removed).
cronAdd("media_expiry", "0 2 * * *", () => {
  try {
    const records = $app.findRecordsByFilter(
      "message_media",
      // @now, not a bound ISO string: stored dates use a space, and "T" sorts after it.
      "expires_at != '' && expires_at <= @now",
      "-created",
      500,
      0
    );
    let deleted = 0;
    for (let i = 0; i < records.length; i++) {
      if (!records[i]) continue;
      try {
        $app.delete(records[i]);
        deleted++;
      } catch (err) {
        console.log("[media_expiry] delete failed:", String(err));
      }
    }
    if (deleted > 0) {
      console.log("[media_expiry] deleted", deleted, "expired media records");
    }
  } catch (err) {
    console.log("[media_expiry] query failed:", String(err));
  }
});
