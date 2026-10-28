import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/chat_run_grouping.dart';

/// Backlog §170 fix (b): the chat's empty state must distinguish "this
/// conversation is new" from "history exists but cannot be decrypted".
///
/// The counts the screen passes come from
/// `MessageRepository.countUndecryptable`, and the wire-level path that
/// produces a nonzero count is proven in
/// `test/offline/undecryptable_state_test.dart`. This file pins the decision
/// itself so the copy stops being a guess.
void main() {
  test('a nonzero hidden count means the history is undecryptable', () {
    expect(chatEmptyKind(75), ChatEmptyKind.undecryptable);
    expect(chatEmptyKind(1), ChatEmptyKind.undecryptable);
  });

  test('zero, or a count that never resolved, means the chat is brand-new', () {
    expect(chatEmptyKind(0), ChatEmptyKind.brandNew);
    // The provider is still loading — never claim lost history we have not
    // confirmed. Showing "Say hello" while it resolves is the pre-fix
    // behaviour, and it is the honest one while the answer is unknown.
    expect(chatEmptyKind(null), ChatEmptyKind.brandNew);
  });
}
