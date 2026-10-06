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

  test('requests + groups screens carry no AppColors / Color(0x / raw palette',
      () {
    final files = [
      'lib/features/friend_requests/screens/friend_requests_screen.dart',
      'lib/features/groups/screens/group_settings_screen.dart',
      'lib/features/groups/screens/create_group_screen.dart',
      'lib/features/home/screens/add_friend_screen.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f);
      expect(src.contains('Color(0x'), isFalse, reason: f);
      expect(
          RegExp(r'Colors\.(purple|indigo|white|black|orange|red|green)')
              .hasMatch(src),
          isFalse,
          reason: f);
      expect(RegExp(r'5E6AD2|EEF0FB').hasMatch(src), isFalse, reason: f);
    }
  });

  test('no AppColors remains in lib (except the file itself, deleted)', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('AppColors'));
    expect(hits.map((f) => f.path), isEmpty);
  });

  // Gate 8: banned legacy purple/violet hexes anywhere in lib.
  // Old palette: primary 5E6AD2, primaryVariant 4A55C0/4A4F9A, navy 2A2D4A,
  // near-black 1A1A2E, Material default violet 6750A4. Warm Pop = Marigold.
  test('no banned purple/violet hexes anywhere in lib', () {
    const banned = [
      '5E6AD2', // old primary (periwinkle)
      '4A4F9A', // old purple dark-mode reply bg
      '4A55C0', // old primaryVariant / light reply bg
      '2A2D4A', // old dark received reply bg
      '1A1A2E', // near-black navy
      '6750A4', // Material 3 default purple
      'EEF0FB', // old primaryLight
    ];
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync().toUpperCase();
      for (final hex in banned) {
        if (src.contains(hex)) hits.add('${f.path}: $hex');
      }
      if (RegExp(r'Colors\.(purple|violet|indigo)').hasMatch(src)) {
        hits.add('${f.path}: Colors.purple/violet/indigo');
      }
    }
    expect(hits, isEmpty, reason: 'banned purple palette leaks: $hits');
  });
}
