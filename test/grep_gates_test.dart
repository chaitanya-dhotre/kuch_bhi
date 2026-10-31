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

  test('requests feature follows token, loading, and L4 screen gates', () {
    final files = Directory('lib/features/friend_requests')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains('colorScheme'), isFalse, reason: f.path);
      expect(src.contains('withValues(alpha'), isFalse, reason: f.path);
      expect(src.contains('Error loading requests'), isFalse, reason: f.path);
    }

    final screen =
        File('lib/features/friend_requests/screens/friend_requests_screen.dart')
            .readAsStringSync();
    expect(screen.contains('CircularProgressIndicator'), isFalse);
    expect(screen.contains('_repository_impl.dart'), isFalse);
  });

  test('no shadow is painted with ink (registry T1 / foundation §4)', () {
    // A shadow color derived from `ink` renders a WHITE halo in the dark
    // theme (ink is #F3EDE3 there). Raised surfaces must read the elevation
    // token instead — `context.t.shadow`.
    //
    // Scanned app-wide: the Requests page is where the defect was found, but
    // the contract is global.
    //
    // The check is per BoxShadow BLOCK (not per line): the shadow color
    // usually sits on the line AFTER `BoxShadow(`.
    final hits = <String>[];
    // Exemptions: a surface that IS ink (dark-on-dark card) may cast an ink
    // shadow — that is a deliberate dark shadow, not a halo.
    const exemptions = {
      'lib/features/auth/screens/backup_pin_screen.dart', // dark card on dark
    };
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (exemptions.contains(f.path)) continue;
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('BoxShadow(')) continue;
        // Look at the next few lines — the color follows the constructor.
        final block =
            lines.sublist(i, (i + 4).clamp(0, lines.length)).join('\n');
        // Any shadow color derived from ink is banned: the withValues form
        // (ink.withValues(alpha: …)), the bare token form (color: t.ink),
        // and the static-token form (WarmPopTokens.ink).
        final usesInk = block.contains('ink.withValues') ||
            block.contains('WarmPopTokens.ink') ||
            RegExp(r'color:\s*(context\.t|t|WarmPopTokens)\.ink\b')
                .hasMatch(block);
        if (usesInk) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
      // Material's elevation shadow must not use ink either.
      if (RegExp(r'shadowColor:\s*(context\.t|WarmPopTokens)\.ink')
          .hasMatch(f.readAsStringSync())) {
        hits.add('${f.path}: shadowColor uses ink');
      }
    }
    expect(hits, isEmpty, reason: 'shadow painted with ink: $hits');
  });

  test('no AppColors remains in lib (except the file itself, deleted)', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('AppColors'));
    expect(hits.map((f) => f.path), isEmpty);
  });

  // 13.1: `ref` throws in dispose, which skipped the rest of ChatScreen's
  // cleanup (reply never cleared, presence never left, listeners kept).
  test('no dispose() in lib touches ref, directly or through a getter', () {
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      final refGetters = RegExp(r'get (\w+)\s*=>\s*ref\.')
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toList();
      for (final m in RegExp(r'void dispose\(\)\s*\{').allMatches(src)) {
        var depth = 1, i = m.end;
        while (depth > 0 && i < src.length) {
          if (src[i] == '{') depth++;
          if (src[i] == '}') depth--;
          i++;
        }
        final body = src.substring(m.end, i);
        if (body.contains('ref.') ||
            refGetters.any((g) => RegExp('\\b$g\\b').hasMatch(body))) {
          hits.add(f.path);
        }
      }
    }
    expect(hits, isEmpty);
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
  test('media docs screen carries no raw grey/alpha-white chrome',
      () {
    final files = [
      'lib/features/media/screens/media_docs_screen.dart',
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

  test('groups feature follows the C3/C4/A2/A4/A5/A6 gates', () {
    final files = Directory('lib/features/groups')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final src = f.readAsStringSync();
      // A2/C3: tokens only — no Material colour surface, no alpha maths,
      // no radius literals, no raw spinner.
      expect(src.contains('colorScheme'), isFalse, reason: f.path);
      expect(src.contains('withValues(alpha'), isFalse, reason: f.path);
      expect(src.contains('CircularProgressIndicator'), isFalse, reason: f.path);
      expect(src.contains('.substring(0, 1)'), isFalse, reason: f.path);
      expect(RegExp(r'circular\(\d').hasMatch(src), isFalse, reason: f.path);

      // A4: no exception in a user-visible string. debugPrint is the one
      // sanctioned place for failure detail.
      for (final line in src.split('\n')) {
        if (line.contains('debugPrint')) continue;
        expect(RegExp(r"\$e}|: \$e'").hasMatch(line), isFalse,
            reason: '${f.path}: ${line.trim()}');
      }

      // A2 also bans these two Material tokens (trailing comments excepted).
      final code = src
          .split('\n')
          .map((l) => l.split(RegExp(r'(?<!:)//')).first)
          .join('\n');
      expect(code.contains('errorContainer'), isFalse, reason: f.path);
      expect(code.contains('surfaceContainerHighest'), isFalse, reason: f.path);
    }

    // A5: the screen reads the feature notifier, never the repository impl.
    const screen = 'lib/features/groups/screens/group_settings_screen.dart';
    final info = File(screen).readAsStringSync();
    expect(info.contains('message_repository_impl'), isFalse, reason: screen);
    expect(info.contains('group_admin_provider.dart'), isTrue, reason: screen);
  });

  test('lib/features/profile carries the page-5 hygiene gates', () {
    final files = Directory('lib/features/profile')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final banned = <String, RegExp>{
      'colorScheme': RegExp(r'colorScheme'),
      'withValues(alpha': RegExp(r'withValues\(alpha'),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'substring(0, 1)': RegExp(r'substring\(0, 1\)'),
      'radius literal': RegExp(r'(Border|Radius)\.circular\(\d'),
      'e.toString()': RegExp(r'e\.toString\(\)'),
      'invalidate(authProvider)': RegExp(r'invalidate\(authProvider\)'),
      'profile_update_service': RegExp(r'profile_update_service'),
    };
    for (final f in files) {
      // `$e` / toString are fine on debugPrint lines (debug detail only).
      final lines = f
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      banned.forEach((name, re) {
        expect(re.hasMatch(lines), isFalse, reason: '$name in ${f.path}');
      });
      expect(RegExp(r'\$\{?e\b').hasMatch(lines), isFalse,
          reason: '\$e in ${f.path}');
    }
  });

  test('lib/features/settings carries the page-6 hygiene gates', () {
    final files = Directory('lib/features/settings')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final banned = <String, RegExp>{
      'colorScheme': RegExp(r'colorScheme'),
      'withValues(alpha': RegExp(r'withValues\(alpha'),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'RadioListTile': RegExp(r'RadioListTile'),
      'radius literal': RegExp(r'(Border|Radius)\.circular\(\d'),
      'e.toString()': RegExp(r'e\.toString\(\)'),
      'invalidate(authProvider)': RegExp(r'invalidate\(authProvider\)'),
      // Nothing here needs the network, so nothing is dimmed offline (F1).
      'kOfflineActionHint': RegExp(r'kOfflineActionHint'),
      'network / key import': RegExp(
          r"""import ['"][^'"]*(pocketbase|dio|package:http/|"""
          r'connectivity_plus|secure_storage|crypto|decrypt|encryption)'),
      'key-boundary call': RegExp(r'signOut|deleteAccount|updatePublicKey'),
    };
    for (final f in files) {
      // `$e` / toString are fine on debugPrint lines (debug detail only).
      final lines = f
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      banned.forEach((name, re) {
        expect(re.hasMatch(lines), isFalse, reason: '$name in ${f.path}');
      });
      expect(RegExp(r'\$\{?e\b').hasMatch(lines), isFalse,
          reason: '\$e in ${f.path}');
    }
  });

  test('Page 7 auth: tokens, R3/R5, L4, no \$e, no key or network imports',
      () {
    const frozen = ['encryption_sync_provider.dart'];
    // The backup screen drives the key backup itself (key-backup spec).
    final keyImports = RegExp(
        r"^import '[./]*/(services/encryption_service|providers/encryption_sync_provider)\.dart';$",
        multiLine: true);
    final files = Directory('lib/features/auth')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !frozen.any(f.path.endsWith))
        .toList();
    expect(files.length, greaterThanOrEqualTo(9));
    final banned = {
      'colorScheme': RegExp(r'colorScheme'),
      'withValues(alpha': RegExp(r'withValues\(alpha'),
      'textTheme': RegExp(r'textTheme'),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'SnackBar(': RegExp(r'SnackBar\('),
      'flutter_animate': RegExp(r'flutter_animate'),
      'raw radius': RegExp(r'(Border|Radius)\.circular\(\d'),
      'invalidate(authProvider)': RegExp(r'invalidate\(authProvider\)'),
      '.collection(': RegExp(r'\.collection\('),
      'banned import': RegExp(
          r"^import .*(pocketbase|package:dio|package:http|secure_storage|crypto|encryption)",
          multiLine: true),
    };
    for (final f in files) {
      var src = f.readAsStringSync();
      if (f.path.endsWith('backup_pin_screen.dart')) {
        src = src.replaceAll(keyImports, '');
      }
      banned.forEach((name, re) {
        expect(re.hasMatch(src), isFalse, reason: '$name in ${f.path}');
      });
      final shown = f
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      expect(RegExp(r'\$\{?e\b|\be\.toString\(\)').hasMatch(shown), isFalse,
          reason: '\$e in ${f.path}');
    }
    expect(
        File('lib/infrastructure/services/auth_onboarding_service.dart')
            .existsSync(),
        isFalse,
        reason: 'F6: raw-bytes avatar upload (EXIF) is gone');
  });

  test('Page 8 sheets: one opener, one picker, one add-friend, A11 hygiene',
      () {
    const appSheet = 'lib/core/widgets/app_sheet.dart';
    const addFriend = 'lib/features/home/screens/add_friend_screen.dart';
    const picker = 'lib/features/chat/widgets/reaction_picker.dart';
    final lib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    // A11: one way to open a sheet, one AddFriendSheet builder, one emoji
    // list (any of its rarer entries stands for the literal).
    final only = {
      RegExp(r'showModalBottomSheet'): appSheet,
      RegExp(r'(?<![A-Za-z_])AddFriendSheet\('): addFriend,
      RegExp("'(🫡|🫠|🫶|🥹|💎)'"): picker,
    };
    only.forEach((needle, home) {
      final hits = [
        for (final f in lib)
          if (needle.hasMatch(f.readAsStringSync())) f.path,
      ];
      expect(hits, [home], reason: '${needle.pattern} outside $home');
    });

    const sheetFiles = [
      appSheet,
      'lib/core/widgets/app_dialog.dart',
      picker,
      'lib/features/chat/widgets/attach_sheets.dart',
      'lib/features/chat/widgets/message_context_menu.dart',
      addFriend,
    ];
    final banned = {
      'colorScheme': RegExp(r'colorScheme'),
      'withValues(alpha': RegExp(r'withValues\(alpha'),
      'textTheme': RegExp(r'textTheme'),
      'surfaceContainerHighest': RegExp(r'surfaceContainerHighest'),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'SnackBar(': RegExp(r'SnackBar\('),
      'fontSize: 13.5': RegExp(r'fontSize:\s*13\.5'),
      'fontSize: 12': RegExp(r'fontSize:\s*12(?![\d.])'),
      'raw radius': RegExp(r'(Border|Radius)\.circular\(\d'),
    };
    for (final path in sheetFiles) {
      final src = File(path).readAsStringSync();
      banned.forEach((name, re) {
        expect(re.hasMatch(src), isFalse, reason: '$name in $path');
      });
      final shown = File(path)
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      expect(RegExp(r'\$\{?e\b|\be\.toString\(\)').hasMatch(shown), isFalse,
          reason: '\$e in $path');
    }
  });

  // J1 (Page 9 media): the one fullscreen viewer rides tokens, R3a, R5 and
  // fixed copy; the dead player, its route and both old packages are gone.
  test('Page 9 media: tokens, R3a/R5, no \$e, no chewie/photo_view/dead route',
      () {
    const viewerFiles = [
      'lib/features/media/screens/media_viewer_screen.dart',
      'lib/features/media/providers/media_viewer_providers.dart',
    ];
    final banned = <String, RegExp>{
      'Colors.': RegExp(r'Colors\.'),
      'Color(0x': RegExp(r'Color\(0x'),
      'LinearGradient': RegExp(r'LinearGradient'),
      'SnackBar(': RegExp(r'SnackBar\('),
      'CircularProgressIndicator': RegExp(r'CircularProgressIndicator'),
      'showModalBottomSheet': RegExp(r'showModalBottomSheet'),
    };
    for (final path in viewerFiles) {
      final src = File(path).readAsStringSync();
      banned.forEach((name, re) {
        expect(re.hasMatch(src), isFalse, reason: '$name in $path');
      });
      final shown = File(path)
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      expect(RegExp(r'\$\{?e\b|\be\.toString\(\)').hasMatch(shown), isFalse,
          reason: '\$e in $path');
    }
    final gone = RegExp(r'VideoPlayerScreen|package:chewie|package:photo_view|'
        r'AppRoutes\.mediaViewer');
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => gone.hasMatch(f.readAsStringSync()))
        .map((f) => f.path);
    expect(hits, isEmpty);
  });

  test('security wave 1 §8.1: starred path sends and shows no server body',
      () {
    final repo = File(
      'lib/infrastructure/repositories/message_repository_impl.dart',
    ).readAsStringSync();
    expect(repo.contains("'message_preview'"), isFalse,
        reason: 'starred_messages.message_preview is plaintext at rest');
    final screen = File(
      'lib/features/starred_messages/screens/starred_messages_screen.dart',
    ).readAsStringSync();
    expect(screen.contains('MessageBodyText('), isTrue,
        reason: 'text cards use the keyed body renderer + placeholder');
    expect(screen.contains('🔒 Encrypted'), isFalse);
    expect(screen.contains('messageBodyProvider(msg.localId)'), isTrue,
        reason: 'voice/doc labels decrypt on device, not from the server');
  });

  test('security wave 1 §3: FCM token and user id are not logged', () {
    expect(File('lib/services/fcm_debug_helper.dart').existsSync(), isFalse);
    for (final f in ['lib/main.dart', 'lib/services/fcm_service.dart']) {
      final src = File(f).readAsStringSync();
      expect(src.contains('FcmDebugHelper'), isFalse, reason: f);
      expect(
        RegExp(r'debugPrint\([^;]*\$\{?(newToken|fcmToken|token)\b')
            .hasMatch(src),
        isFalse,
        reason: '$f logs an FCM token',
      );
    }
  });

  test('security wave 1 §4.2: Android backup and D2D transfer are off', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest.contains('android:allowBackup="false"'), isTrue);
    expect(
      manifest.contains(
        'android:dataExtractionRules="@xml/data_extraction_rules"',
      ),
      isTrue,
    );
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      expect(rules.contains('<$section>'), isTrue, reason: section);
    }
    for (final domain in [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ]) {
      expect(rules.contains('<exclude domain="$domain" path="."/>'), isTrue,
          reason: domain);
    }
  });

  test('security wave 1 §2.1: google-services copies are git-ignored', () {
    // --no-index: without it git never reports a tracked file as ignored.
    bool ignored(String path) => Process.runSync(
          'git',
          ['check-ignore', '-q', '--no-index', path],
        ).exitCode ==
        0;
    expect(ignored('android/app/google-services (2).json'), isTrue);
    expect(ignored('android/app/google-services (9).json'), isTrue);
    expect(ignored('android/app/google-services.json'), isFalse,
        reason: 'the real, tracked config stays tracked');
  });

  // Bug wave 1 §1.1–1.3: send/history failures reach the user through the
  // R5 toast or a Retry row, never a swallowed catch or raw `$e`.
  test('bug wave 1: sends rethrow, composer toasts, history keeps Retry', () {
    final input = File('lib/features/chat/widgets/message_input.dart')
        .readAsLinesSync()
        .where((l) => !l.contains('debugPrint('))
        .join('\n');
    expect(RegExp(r'\$\{?e\b|\be\.toString\(\)').hasMatch(input), isFalse,
        reason: r'$e in message_input.dart');
    expect(input.contains("Text('Failed to send"), isFalse);

    final provider =
        File('lib/features/chat/providers/chat_provider.dart').readAsStringSync();
    expect(RegExp(r"rejected: \$e'\);\s*rethrow;").allMatches(provider).length,
        2, reason: 'both send notifiers rethrow after logging');

    final screen =
        File('lib/features/chat/screens/chat_screen.dart').readAsStringSync();
    expect(screen.contains('HistoryLoadFailedRow('), isTrue);
    expect(
        RegExp(r'try \{\s*await ref\.read\(messageRepositoryProvider\)'
                r'\.loadMoreMessages\(_cid, _offset\);\s*_offset \+= 40;'
                r'\s*\} catch \(_\) \{[^}]*_historyLoadFailed = true;')
            .hasMatch(screen),
        isTrue,
        reason: 'offset moves only after the awaited page succeeds');
    expect(screen.contains('!_historyExhausted &&\n        !_historyLoadFailed'),
        isTrue, reason: 'a failed page waits for Retry, not every scroll');
  });

  test('bug wave 2: no raw exception reaches the screen; media reloads', () {
    // A Text / SnackBar / toast / errorText that interpolates the caught
    // error, within one statement (debugPrint lines are dropped first).
    final raw = RegExp(
        r'(Text\(|SnackBar\(|showToast\(|errorText:)[^;]{0,200}?'
        r'(\$\{?(e|e2|ex|err|error|exception)\b|'
        r'\b(e|e2|ex|err|error|exception)\.toString\(\))');
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f
          .readAsLinesSync()
          .where((l) => !l.contains('debugPrint('))
          .join('\n');
      for (final m in raw.allMatches(src)) {
        hits.add('${f.path}: ${m.group(0)!.split('\n').first}');
      }
    }
    expect(hits, isEmpty, reason: 'show plain copy; keep \$e in debugPrint');

    final provider =
        File('lib/features/chat/providers/chat_provider.dart').readAsStringSync();
    expect(
        provider.contains(
            'if (file == null && !await failed()) invalidateOnReconnect(ref);'),
        isTrue,
        reason: 'an empty (not failed) media load re-runs on reconnect');
    final auth = File('lib/infrastructure/repositories/auth_repository_impl.dart')
        .readAsStringSync();
    expect(
        RegExp(r"'fcm_token': fcmToken,\s*\}\)\.timeout\(kAuthNetworkTimeout\)")
            .hasMatch(auth),
        isTrue,
        reason: 'the FCM write after sign-in is bounded');
  });

  // ── Dead-code wave B (docs/audits/2026-10-30-dead-code.md §2) ─────────
  // Five registry-merge gates. Each was run against the pre-wave tree
  // (78d121e) first and failed, and is green on the routed tree.

  test('R5: no ScaffoldMessenger…showSnackBar in lib outside app_toast.dart',
      () {
    const allowed = 'lib/core/widgets/app_toast.dart';
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path == allowed) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'ScaffoldMessenger').hasMatch(src) &&
          RegExp(r'showSnackBar').hasMatch(src)) {
        hits.add('${f.path}: ScaffoldMessenger…showSnackBar');
      }
    }
    expect(hits, isEmpty,
        reason: 'every snackbar goes through R5 showToast(): $hits');
  });

  test('R11: no Shimmer.fromColors in lib outside skeleton.dart', () {
    const allowed = 'lib/core/widgets/skeleton.dart';
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path == allowed) continue;
      if (RegExp(r'Shimmer\.fromColors').hasMatch(f.readAsStringSync())) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty, reason: 'media shimmer lives in R11: $hits');
  });

  test('R1/R1a: no CircleAvatar( in lib/features (avatars go through AppAvatar)',
      () {
    final hits = <String>[];
    for (final f in Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (RegExp(r'CircleAvatar\s*\(').hasMatch(f.readAsStringSync())) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty, reason: 'avatars are R1 AppAvatar: $hits');
  });

  test('R14: no AppBar( in lib/features except lib/features/home/', () {
    // `pageAppBar(` must stay allowed — only a bare AppBar( is a re-build.
    final raw = RegExp(r'(?<![A-Za-z])AppBar\s*\(');
    final hits = <String>[];
    for (final f in Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.startsWith('lib/features/home/')) continue; // Home's own bar
      if (raw.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: 'pages use R14 pageAppBar(): $hits');
  });

  test('T2: no colorScheme. in lib/features outside the D4-skipped files', () {
    // Decision D4: the key backup/restore flow keeps its own colours.
    const d4Exceptions = <String>[
      'lib/features/auth/screens/backup_pin_screen.dart',
    ];
    final hits = <String>[];
    for (final f in Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (d4Exceptions.contains(f.path)) continue;
      if (RegExp(r'colorScheme\.').hasMatch(f.readAsStringSync())) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty, reason: 'components read context.t, not the scheme: $hits');
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
