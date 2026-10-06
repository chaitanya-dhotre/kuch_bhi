// Grep gates (spec rule 2: screens may not hardcode color).
// Each Phase B task appends its migrated files here.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home screens carry no AppColors / old indigo palette', () {
    for (final f in [
      'lib/features/home/screens/home_screen.dart',
      'lib/features/home/screens/add_friend_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f);
      expect(RegExp(r'5E6AD2|EEF0FB').hasMatch(src), isFalse, reason: f);
    }
  });

  test('profile + settings screens carry no AppColors / Color(0x / Colors.', () {
    final files = [
      'lib/features/profile/screens/profile_screen.dart',
      'lib/features/profile/screens/edit_profile_screen.dart',
      'lib/features/profile/screens/view_profile_screen.dart',
      'lib/features/settings/screens/settings_screen.dart',
      'lib/features/settings/screens/about_screen.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f);
      expect(src.contains('Color(0x'), isFalse, reason: f);
      expect(RegExp(r'Colors\.(purple|indigo|white|black)').hasMatch(src),
          isFalse, reason: f);
      expect(RegExp(r'5E6AD2|EEF0FB').hasMatch(src), isFalse, reason: f);
    }
  });

  test('chat screen + widgets carry no AppColors / purple / indigo', () {
    final files = Directory('lib/features/chat')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f.path);
      expect(RegExp(r'Colors\.(purple|indigo)').hasMatch(src), isFalse,
          reason: f.path);
      expect(RegExp(r'5E6AD2|1E2030|EEF0FB').hasMatch(src), isFalse,
          reason: f.path);
    }
  });
}
