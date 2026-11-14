import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_logo_tile.dart';

void main() {
  for (final size in [88.0, 64.0]) {
    testWidgets('K6: the launcher picture on bath teal, radiusXl, at $size',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: AppLogoTile(size: size))));
      expect(tester.getSize(find.byType(AppLogoTile)), Size(size, size));
      final box = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;
      expect(box.color, AppLogoTile.background);
      expect(box.borderRadius, BorderRadius.circular(WarmPopTokens.radiusXl));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, AppLogoTile.asset);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  }

  test('the asset is bundled and the teal matches the launcher plate',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect((await rootBundle.load(AppLogoTile.asset)).lengthInBytes,
        greaterThan(0));
    final colors =
        File('android/app/src/main/res/values/colors.xml').readAsStringSync();
    final hex = RegExp(r'ic_launcher_background">#([0-9A-F]{6})')
        .firstMatch(colors)!
        .group(1)!;
    expect(AppLogoTile.background, Color(int.parse('FF$hex', radix: 16)));
  });
}
