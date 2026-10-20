import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/home/widgets/home_search_bar.dart';

Widget _host({required ValueChanged<String> onChanged}) {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  addTearDown(() {
    controller.dispose();
    focusNode.dispose();
  });
  return MaterialApp(
    theme: warmPopLight(),
    home: Scaffold(
      body: HomeSearchBar(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
      ),
    ),
  );
}

void main() {
  testWidgets('Home search opens, filters live, and clears with focus', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(_host(onChanged: changes.add));

    expect(find.text('Search chats'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Search chats'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'desig');
    await tester.pump();
    expect(changes, contains('desig'));
    expect(find.bySemanticsLabel('Clear search'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Clear search'));
    await tester.pump();
    expect(changes.last, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });
}
