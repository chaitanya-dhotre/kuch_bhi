/// Write gate for session-scoped work (spec D5 / review C1): an async
/// sync/fetch started under one session must not write after logout or an
/// account switch — INSERTs into a wiped table SUCCEED and repopulate the
/// next account's data (the B1 bleed the wipe exists to prevent).
bool sessionStillValid({
  required int epochAtStart,
  required int currentEpoch,
  required bool authValid,
}) =>
    epochAtStart == currentEpoch && authValid;
