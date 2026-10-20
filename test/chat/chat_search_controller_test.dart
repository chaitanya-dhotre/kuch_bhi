import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';

void main() {
  test(
    'search keeps prior matches until the replacement scan completes',
    () async {
      final pending = Completer<String?>();
      var resolveCount = 0;
      final results = <List<int>>[];
      final controller = ConversationSearchController(
        debounce: Duration.zero,
        resolveBody: (_) {
          resolveCount++;
          return resolveCount == 1 ? Future.value('alpha') : pending.future;
        },
      )..onResults = (matches) => results.add(matches);
      addTearDown(controller.dispose);

      controller.setQuery('alp', candidates: [(0, 'message-1')]);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(controller.lastMatches, [0]);
      expect(results, [
        [0],
      ]);

      controller.setQuery('missing', candidates: [(0, 'message-1')]);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(controller.lastMatches, [0]);
      expect(results, [
        [0],
      ]);

      pending.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(controller.lastMatches, isEmpty);
      expect(results, [
        [0],
        [],
      ]);
    },
  );
}
