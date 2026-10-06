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

  test('auth screens carry no AppColors / Color(0x / Colors.', () {
    final files = [
      'lib/features/auth/screens/login_screen.dart',
      'lib/features/auth/screens/register_screen.dart',
      'lib/features/auth/screens/google_onboarding_screen.dart',
      'lib/features/auth/screens/forgot_password_screen.dart',
      'lib/features/auth/screens/backup_pin_screen.dart',
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

  test('google sign-in button renders 4-color SVG asset, not a blue text G',
      () {
    final src =
        File('lib/features/auth/widgets/google_sign_in_button.dart')
            .readAsStringSync();
    expect(src.contains('google_g.svg'), isTrue, reason: 'SVG asset required');
    expect(src.contains('SvgPicture'), isTrue, reason: 'SVG widget required');
    expect(src.contains('4285F4'), isFalse,
        reason: 'single-blue text G replaced by official 4-color mark');
    final asset = File('assets/icons/google_g.svg');
    expect(asset.existsSync(), isTrue, reason: 'asset file must exist');
    final svg = asset.readAsStringSync();
    for (final hex in ['#EA4335', '#4285F4', '#FBBC05', '#34A853']) {
      expect(svg.contains(hex), isTrue, reason: 'missing brand color $hex');
    }
  });
}
