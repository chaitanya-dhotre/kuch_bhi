import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

/// Page 9 viewer tests: shared pump + fakes (no plugin is ever reached).

MediaViewerArgs viewerArgs({
  String mediaType = 'image',
  String senderName = 'Aanya Kulkarni',
  String? heroTag = 'media_s1',
  String? thumbPath = '/nonexistent/thumb.jpg',
}) =>
    MediaViewerArgs(
      conversationId: 'c1',
      serverId: 's1',
      mediaType: mediaType,
      senderName: senderName,
      timestamp: DateTime(2026, 10, 30, 14, 2),
      heroTag: heroTag,
      thumbPath: thumbPath,
    );

LocalMediaFile mediaFile({String path = '/nonexistent/full.jpg', DateTime? expiresAt}) =>
    LocalMediaFile(file: File(path), expiresAt: expiresAt);

class FakeMediaActions implements MediaActions {
  bool saveResult = true;
  Object? saveError;
  Object? shareError;
  Completer<void>? hold;
  int saves = 0;
  int shares = 0;

  @override
  Future<bool> save(String path, {required bool video}) async {
    saves++;
    if (hold != null) await hold!.future;
    if (saveError != null) throw saveError!;
    return saveResult;
  }

  @override
  Future<void> share(String path) async {
    shares++;
    if (shareError != null) throw shareError!;
  }
}

/// Pumps a launcher, then opens the viewer on top of it (a real push, so
/// pops and route transitions are exercised).
Future<void> pumpViewer(
  WidgetTester tester, {
  required FutureOr<LocalMediaFile?> Function() load,
  MediaViewerArgs? args,
  MediaBlobStatus blob = MediaBlobStatus.other,
  Stream<bool>? online,
  FakeMediaActions? actions,
  bool large = false,
  AppFont font = AppFont.system,
  bool still = false,
  bool a11y = false,
  List<Override> extraOverrides = const [],
  bool open = true,
}) async {
  if (large) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final a = args ?? viewerArgs();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mediaFileProvider.overrideWith((ref, r) => r.thumb ? null : load()),
      mediaBlobStatusProvider.overrideWith((ref, r) async => blob),
      isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
      fontFamilyProvider.overrideWith((ref) => Stream.value(font)),
      mediaActionsProvider.overrideWithValue(actions ?? FakeMediaActions()),
      ...extraOverrides,
    ],
    child: MaterialApp(
      theme: warmPopLight(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 2 : 1),
          disableAnimations: still,
          accessibleNavigation: a11y,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () => pushMediaViewer(context, a),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  if (!open) return;
  await tester.tap(find.byKey(const Key('open')));
  await settle(tester);
}

/// Spinners never settle, so pump past the route fade instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder inViewer(Finder f) =>
    find.descendant(of: find.byType(MediaViewerScreen), matching: f);

/// Every label and tooltip in the semantics tree (hidden chrome is excluded).
Set<String> semanticsStrings(WidgetTester tester) {
  final out = <String>{};
  for (final n in find.semantics.byPredicate((_) => true).evaluate()) {
    if (n.label.isNotEmpty) out.add(n.label);
    if (n.tooltip.isNotEmpty) out.add(n.tooltip);
  }
  return out;
}

/// Records `SystemChrome.setEnabledSystemUIMode` calls.
List<String> recordUiModes(WidgetTester tester) {
  final modes = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
      modes.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return modes;
}
