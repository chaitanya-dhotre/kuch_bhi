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
  test('gate 8 helper detects both banned hexes and Colors.purple variants',
      () {
    expect(bannedPaletteHits('fixture.dart', 'child: const Color(0xFF5E6AD2)'),
        isNotEmpty, reason: 'hex must be caught');
    expect(bannedPaletteHits('fixture.dart', 'color: Colors.purple'),
        isNotEmpty, reason: 'Colors.purple must be caught');
    expect(bannedPaletteHits('fixture.dart', 'color: Colors.Violet'),
        isNotEmpty, reason: 'case variants must be caught');
    expect(bannedPaletteHits('fixture.dart', 'color: Colors.grey'),
        isEmpty, reason: 'non-banned color must pass');
  });

  test('no banned purple/violet hexes anywhere in lib', () {
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      hits.addAll(bannedPaletteHits(f.path, f.readAsStringSync()));
    }
    expect(hits, isEmpty, reason: 'banned purple palette leaks: $hits');
  });

  // Gate 9: doc/voice bubbles render chrome directly on the Marigold sent
  // bubble — raw Colors.white/grey there is 2.2:1 or worse. Must ride
  // theme tokens (onAccent family on accent, ink family on surface).
  test('doc + voice bubbles carry no raw white/grey chrome', () {
    final files = [
      'lib/features/chat/widgets/document_message_bubble.dart',
      'lib/features/chat/widgets/voice_message_bubble.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      expect(RegExp(r'Colors\.(white|grey)').hasMatch(src), isFalse,
          reason: '$f must use tokens (onAccent/ink), not raw white/grey');
    }
  });

  // Gate 10: media screens are chrome (not photo scrims) — greys and
  // translucent chrome whites must be tokens. Full-opacity Colors.white on
  // black photo-scrim pills (tile play/duration overlays) is allowed;
  // media_viewer_screen is fully exempt (chewie over dark video content).
  test('media docs screen + expiry badge carry no raw grey/alpha-white chrome',
      () {
    final files = [
      'lib/features/media/screens/media_docs_screen.dart',
      'lib/features/media/widgets/expiry_badge.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      expect(RegExp(r'Colors\.grey|Colors\.white(38|54|60|70)').hasMatch(src),
          isFalse, reason: '$f must use Warm Pop tokens');
    }
  });

  // Gate 11 (Task 4): terminal-failure banner + its status provider ride
  // Warm Pop tokens only — raw Color(0x / Colors.* in the banner path is a
  // spec violation (screens may not hardcode color).
  test('terminal banner + outbox status provider carry no raw colors', () {
    final files = [
      'lib/features/chat/providers/outbox_status_provider.dart',
      'lib/features/chat/widgets/message_bubble.dart',
    ];
    for (final f in files) {
      final src = File(f).readAsStringSync();
      expect(src.contains('AppColors'), isFalse, reason: f);
      expect(RegExp(r'Color\(0x').hasMatch(src), isFalse, reason: f);
      expect(RegExp(r'Colors\.(purple|indigo|red|white|grey)').hasMatch(src),
          isFalse, reason: f);
    }
  });

  // Gate 13 (spec §12 + plan carve-outs): network SDK IMPORT LOCALITY only —
  // network SDKs live in the sanctioned integration paths, everything else
  // (screens/features/data/domain/core(else)) stays network-free. Sanctioned:
  // infrastructure (ingest/outbox/blobs), services (fcm/presence/encryption/
  // upload integrations), core/network (the PB client), bootstrap
  // (main + firebase_options).
  // SCOPE (spec §4 amendment 2026-10-10, user-ratified): this gate does NOT
  // enforce the single-writer / two-gate domain rule and cannot — import
  // locality ≠ writer discipline. That rule is held by characterization
  // tests and review audits. Do NOT read gate-13 green as "two-gate rule
  // proven".
  test('no network SDK imports outside sanctioned integration paths', () {
    const sanctioned = [
      'lib/infrastructure/',
      'lib/services/',
      'lib/core/network/',
      'lib/main.dart',
      'lib/firebase_options.dart',
    ];
    final banned = RegExp(
        r"package:http/|package:dio/|package:pocketbase/|"
        r"package:web_socket_channel/|package:firebase_|"
        r"package:connectivity_plus|"
        r"dart:io.*(HttpClient|WebSocket|Socket\b)");
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final allowed = sanctioned.any((p) =>
          p.endsWith('/') ? f.path.startsWith(p) : f.path == p);
      if (allowed) continue;
      if (banned.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: 'network SDK outside sanctioned paths: $hits');
  });
}

const _bannedPurpleHexes = [
  '5E6AD2', // old primary (periwinkle)
  '4A4F9A', // old purple dark-mode reply bg
  '4A55C0', // old primaryVariant / light reply bg
  '2A2D4A', // old dark received reply bg
  '1A1A2E', // near-black navy
  '6750A4', // Material 3 default purple
  'EEF0FB', // old primaryLight
];

List<String> bannedPaletteHits(String path, String src) {
  final hits = <String>[];
  final upper = src.toUpperCase();
  for (final hex in _bannedPurpleHexes) {
    if (upper.contains(hex)) hits.add('$path: $hex');
  }
  if (RegExp(r'colors\.(purple|violet|indigo)', caseSensitive: false)
      .hasMatch(src)) {
    hits.add('$path: Colors.purple/violet/indigo');
  }
  return hits;
}
