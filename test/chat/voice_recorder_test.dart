// 12.6 "Voice recorder redesign": the spec's test gates (3–26, plus 32–35).
//
// The composer itself is under test: a fake recorder that records every call
// and returns a real temp file from stop(), a fake mic permission, a temp
// documents dir for voice drafts, and a fake send notifier. The five
// panel-only cases at the end check behaviour of the widgets that hold no
// recording state (the hold strip's pill and the panel's controls).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/voice_body.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/voice_recorder_providers.dart';
import 'package:kuch_bhi/features/chat/voice_draft_store.dart';
import 'package:kuch_bhi/features/chat/widgets/message_input.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_recorder_panel.dart';
import 'package:kuch_bhi/features/share/share_payload.dart';
import 'package:kuch_bhi/services/share_in_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class FakeRecorder implements AudioRecorder {
  FakeRecorder();

  final List<String> calls = [];
  final List<RecordConfig> configs = [];
  final StreamController<RecordState> states =
      StreamController<RecordState>.broadcast();

  bool throwOnStart = false;
  bool throwOnStop = false;
  bool throwOnPause = false;
  String? startedPath;
  String? stoppedPath;

  /// Set one to hold that call open until the test completes it.
  Completer<void>? startGate;
  Completer<void>? stopGate;

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    calls.add('start');
    configs.add(config);
    await startGate?.future;
    if (throwOnStart) throw StateError('microphone busy');
    startedPath = path;
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    await stopGate?.future;
    if (throwOnStop) throw StateError('stop failed');
    final target = startedPath ?? stoppedPath;
    if (target != null) {
      File(target).writeAsStringSync('audio');
      stoppedPath = target;
    }
    return target;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    final target = startedPath;
    if (target != null) {
      final file = File(target);
      if (file.existsSync()) file.deleteSync();
    }
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    if (throwOnPause) throw StateError('pause failed');
  }

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<Amplitude> getAmplitude() async {
    calls.add('amplitude');
    return Amplitude(current: -20, max: -10);
  }

  @override
  Stream<RecordState> onStateChanged() => states.stream;

  @override
  Future<void> dispose() async => calls.add('dispose');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeMicPermission implements MicPermission {
  FakeMicPermission(this.initial);

  PermissionStatus initial;
  PermissionStatus onRequest = PermissionStatus.granted;
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<PermissionStatus> status() async {
    statusCalls++;
    return initial;
  }

  @override
  Future<PermissionStatus> request() async {
    requestCalls++;
    initial = onRequest;
    return onRequest;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class FakeSendNotifier extends SendMediaMessageNotifier {
  final List<Map<String, Object?>> calls = [];
  Object? error;
  bool deleteFileOnThrow = false;

  @override
  bool build() => false;

  @override
  Future<void> send({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
  }) async {
    calls.add(<String, Object?>{
      'conversationId': conversationId,
      'mediaType': mediaType,
      'path': mediaFile.path,
      'durationSeconds': durationSeconds,
      'durationText': durationText,
    });
    if (error != null) {
      if (deleteFileOnThrow) {
        try {
          mediaFile.deleteSync();
        } catch (_) {}
      }
      throw error!;
    }
    // The real send moves the file into the media store.
    try {
      mediaFile.deleteSync();
    } catch (_) {}
  }
}

// ── Harness ────────────────────────────────────────────────────────────────

late Directory tempDir;
var _chatSeq = 0;
var _seedSeq = 0;

String _nextChat() => 'voice-${++_chatSeq}';

class VoiceHost extends StatefulWidget {
  const VoiceHost({super.key, required this.chat, required this.canSend});

  final String chat;
  final bool canSend;

  @override
  State<VoiceHost> createState() => VoiceHostState();
}

class VoiceHostState extends State<VoiceHost> {
  late bool _canSend = widget.canSend;

  void setCanSend(bool value) {
    if (value == _canSend) return;
    setState(() => _canSend = value);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: MessageInput(
      conversationId: widget.chat,
      canSendMessages: _canSend,
      onSend: (_) {},
    ),
  );
}

class Harness {
  Harness(
    this.chat,
    this.recorder,
    this.permission,
    this.send,
    this.hostKey,
  );

  final String chat;
  final FakeRecorder recorder;
  final FakeMicPermission permission;
  final FakeSendNotifier send;
  final GlobalKey<VoiceHostState> hostKey;

  File get draftAudio => File('$draftDir/$chat.m4a');
  File get draftSidecar => File('$draftDir/$chat.json');

  String get draftDir => '${tempDir.path}/voice_drafts';
}

Future<Harness> pumpComposer(
  WidgetTester tester, {
  String? chat,
  bool canSend = true,
  FakeRecorder? recorder,
  FakeMicPermission? permission,
  FakeSendNotifier? send,
  bool accessible = false,
  double textScale = 1,
  ReadyShare? share,
}) async {
  final id = chat ?? _nextChat();
  final rec = recorder ?? FakeRecorder();
  final perm = permission ?? FakeMicPermission(PermissionStatus.granted);
  final sender = send ?? FakeSendNotifier();
  final container = ProviderContainer(
    overrides: [
      voiceRecorderFactoryProvider.overrideWithValue(() => rec),
      micPermissionProvider.overrideWithValue(perm),
      voiceDraftDirProvider.overrideWithValue(() async => tempDir),
      sendMediaMessageProvider.overrideWith(() => sender),
    ],
  );
  addTearDown(container.dispose);
  if (share != null) container.read(chatShareProvider(id).notifier).state = share;
  final hostKey = GlobalKey<VoiceHostState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: warmPopLight(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            accessibleNavigation: accessible,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: VoiceHost(key: hostKey, chat: id, canSend: canSend),
        ),
      ),
    ),
  );
  await tester.pump();
  return Harness(id, rec, perm, sender, hostKey);
}

final Finder mic = find.byKey(const ValueKey('mic-action'));

/// The real event loop only runs inside [WidgetTester.runAsync]; alternate it
/// with the fake clock so a widget's file IO (drafts) can finish.
Future<void> drain(WidgetTester tester, {int cycles = 8}) async {
  for (var i = 0; i < cycles; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// [drain] until [done] holds (a draft file appears or disappears).
Future<void> drainUntil(
  WidgetTester tester,
  bool Function() done, {
  int cycles = 40,
}) async {
  for (var i = 0; i < cycles; i++) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Press and hold the mic past the long-press deadline (the recording starts).
Future<TestGesture> holdMic(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(mic));
  await tester.pump(const Duration(milliseconds: 700));
  await settle(tester);
  return gesture;
}

/// Hold, then drag up past the lock threshold (the finger stays down).
Future<TestGesture> lockMic(WidgetTester tester) async {
  final gesture = await holdMic(tester);
  await gesture.moveBy(const Offset(0, -100));
  await tester.pump();
  return gesture;
}

int _timerSeconds(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .firstWhere((value) => RegExp(r'^\d+:\d{2}$').hasMatch(value));
  final parts = text.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String? _timerText(WidgetTester tester) {
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final value = widget.data ?? '';
    if (RegExp(r'^\d+:\d{2}$').hasMatch(value)) return value;
  }
  return null;
}

Future<void> seedDraft(
  WidgetTester tester,
  String chat, {
  int seconds = 5,
}) async {
  final source = File('${tempDir.path}/seed-${++_seedSeq}.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  await tester.runAsync(
    () => saveVoiceDraft(chat, source, seconds, [.2, .8, .4], () async => tempDir),
  );
}

void main() {
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('voice_recorder_test');
    // The composer records into path_provider's temp dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ── 3–9: hold, release, cancel, lock, pause, send ────────────────────────

  testWidgets('3. a hold records mono 64 kbps and the strip runs', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);

    expect(h.recorder.count('start'), 1);
    final config = h.recorder.configs.single;
    expect(config.encoder, AudioEncoder.aacLc);
    expect(config.numChannels, 1);
    expect(config.bitRate, 64000);
    expect(find.text('Slide to cancel'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('0:01'), findsOneWidget);

    await gesture.up();
    await settle(tester);
  });

  testWidgets('4. release after 2 s opens the preview and stops once', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);

    expect(find.text('Voice note'), findsOneWidget);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(find.byTooltip('Send voice note'), findsOneWidget);
    expect(h.recorder.count('stop'), 1);
    expect(find.text('Slide to cancel'), findsNothing);
  });

  testWidgets('5. release under 1 s keeps nothing and says Hold to record', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);

    expect(find.text('Hold to record'), findsOneWidget);
    expect(find.text('Voice note'), findsNothing);
    expect(h.recorder.count('cancel'), 1);
    expect(h.recorder.count('stop'), 0);
  });

  testWidgets('6. sliding left past 80 dp cancels on release', (tester) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();

    expect(find.text('Release to cancel'), findsOneWidget);

    await gesture.up();
    await settle(tester);

    expect(h.recorder.count('cancel'), 1);
    expect(h.recorder.count('stop'), 0);
    expect(find.text('Voice note'), findsNothing);
    expect(find.text('Slide to cancel'), findsNothing);
  });

  testWidgets('7. sliding up locks without a release; lifting keeps recording', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);

    expect(find.text('Recording'), findsOneWidget);
    expect(find.byTooltip('Pause recording'), findsOneWidget);

    await gesture.up();
    await settle(tester);

    expect(h.recorder.count('stop'), 0);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Voice note'), findsOneWidget);
  });

  testWidgets('8. pause freezes the clock, resume starts it again', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1100));

    await tester.tap(find.byTooltip('Pause recording'));
    await settle(tester);

    expect(h.recorder.count('pause'), 1);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Stop and listen'), findsOneWidget);
    final frozen = _timerText(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_timerText(tester), frozen);

    await tester.tap(find.byTooltip('Resume recording'));
    await tester.pump(const Duration(milliseconds: 1100));

    expect(h.recorder.count('resume'), 1);
    expect(find.text('Recording'), findsOneWidget);
    expect(_timerText(tester), isNot(frozen));
    expect(h.recorder.count('stop'), 0);
  });

  testWidgets('9. send from locked stops first, then sends a voice note', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);

    expect(h.recorder.count('stop'), 1);
    expect(h.send.calls, hasLength(1));
    final call = h.send.calls.single;
    expect(call['mediaType'], 'voice');
    expect(call['conversationId'], h.chat);
    expect(call['durationSeconds'], greaterThanOrEqualTo(2));
    // D-3 A: the body is the duration + the level suffix.
    expect(
      voiceBodyText(call['durationText'] as String?),
      matches(RegExp(r'^\d+:\d{2}$')),
    );
    expect(find.text('Voice note'), findsNothing);
    expect(find.text('Recording'), findsNothing);
  });

  testWidgets('35. send from locked carries the elapsed seconds', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    // Past half a second, so rounding differs from the on-screen floor.
    while (_timerSeconds(tester) < 4) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(_timerSeconds(tester), 4);

    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);

    expect(h.send.calls.single['durationSeconds'], 5);
    expect(
      voiceBodyText(h.send.calls.single['durationText'] as String?),
      '0:05',
    );
  });

  // ── 10–14: delete, failed send, permission, start errors ─────────────────

  testWidgets('10. deleting a preview removes the temp file', (tester) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);

    final path = h.recorder.stoppedPath!;
    expect(File(path).existsSync(), isTrue);

    await tester.tap(find.byTooltip('Delete voice note'));
    await settle(tester);

    expect(find.text('Voice note'), findsNothing);
    expect(File(path).existsSync(), isFalse);
  });

  testWidgets('11. a rejected send keeps the preview and says so', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    h.send.error = StateError('rejected');
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);

    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);

    expect(h.send.calls, hasLength(1));
    expect(
      find.text("Couldn't send voice note. Try again."),
      findsOneWidget,
    );
    expect(find.text('Voice note'), findsOneWidget);
    expect(find.byTooltip('Send voice note'), findsOneWidget);
  });

  testWidgets('12. a denied press only asks; it never starts recording', (
    tester,
  ) async {
    final permission = FakeMicPermission(PermissionStatus.denied)
      ..onRequest = PermissionStatus.granted;
    final h = await pumpComposer(tester, permission: permission);
    final gesture = await holdMic(tester);

    expect(permission.statusCalls, 1);
    expect(permission.requestCalls, 1);
    expect(h.recorder.count('start'), 0);
    expect(find.text('Microphone on. Hold to record.'), findsOneWidget);
    expect(find.text('Slide to cancel'), findsNothing);

    await gesture.up();
    await settle(tester);
  });

  testWidgets('13. a permanent denial opens settings, never records', (
    tester,
  ) async {
    final permission = FakeMicPermission(PermissionStatus.permanentlyDenied);
    final h = await pumpComposer(tester, permission: permission);
    final gesture = await holdMic(tester);

    expect(find.text('Microphone is off'), findsOneWidget);
    expect(h.recorder.count('start'), 0);

    await tester.tap(find.text('Open settings'));
    await settle(tester);

    expect(permission.openSettingsCalls, 1);
    await gesture.up();
    await settle(tester);
  });

  testWidgets('14. a start that throws says the microphone may be in use', (
    tester,
  ) async {
    final h = await pumpComposer(
      tester,
      recorder: FakeRecorder()..throwOnStart = true,
    );
    final gesture = await holdMic(tester);

    expect(
      find.text("Couldn't start recording. The microphone may be in use."),
      findsOneWidget,
    );
    expect(find.text('Slide to cancel'), findsNothing);
    expect(mic, findsOneWidget, reason: 'back to the idle composer');

    await gesture.up();
    await settle(tester);
    expect(h.recorder.count('cancel'), 0);
  });

  // ── 15–17: interruptions, the clock's top end ────────────────────────────

  testWidgets('15. a pause from the plugin stops a hold, pauses a lock', (
    tester,
  ) async {
    final holding = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(milliseconds: 1100));
    holding.recorder.states.add(RecordState.pause);
    await settle(tester);

    expect(holding.recorder.count('stop'), 1);
    expect(find.text('Voice note'), findsOneWidget);
    await gesture.up();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final locked = await pumpComposer(tester);
    final again = await lockMic(tester);
    await again.up();
    locked.recorder.states.add(RecordState.pause);
    await settle(tester);

    expect(find.text('Paused'), findsOneWidget);
    expect(locked.recorder.count('stop'), 0);
  });

  testWidgets('16. hidden pauses a lock; inactive alone changes nothing', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    expect(find.text('Recording'), findsOneWidget);
    expect(h.recorder.count('pause'), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);

    expect(h.recorder.count('pause'), 1);
    expect(find.text('Paused'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
  });

  testWidgets('17. the last 10 s are counted down and 5 minutes stop it', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 290));

    expect(find.text('10 seconds left'), findsOneWidget);
    expect(find.text('Recording'), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    await settle(tester);

    expect(find.text('Voice notes can be up to 5 minutes.'), findsOneWidget);
    expect(find.text('Voice note'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(h.recorder.count('stop'), 1);
  });

  // ── 18: leaving under 1 s keeps nothing ──────────────────────────────────

  testWidgets('18. leaving under 1 s cancels and writes no draft', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);

    await tester.pumpWidget(const SizedBox());
    await drain(tester);

    expect(h.recorder.count('cancel'), 1);
    expect(h.recorder.count('stop'), 0);
    expect(Directory(h.draftDir).existsSync(), isFalse);
    expect(h.recorder.count('dispose'), 1);
    await gesture.up();
  });

  // ── 19–20: TalkBack and 200% text ────────────────────────────────────────

  /// Press a control the way TalkBack's double tap does: through its semantics
  /// action, which throws if the control doesn't offer one.
  Future<void> screenReaderTap(WidgetTester tester, String label) async {
    tester.semantics.tap(find.semantics.byLabel(label));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('19. TalkBack records, pauses, resumes and sends by semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await pumpComposer(tester, accessible: true);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Record voice message')),
      isSemantics(
        label: 'Record voice message',
        hint: 'Double tap to record',
        isButton: true,
      ),
    );

    await screenReaderTap(tester, 'Record voice message');
    expect(h.recorder.count('start'), 1);
    expect(find.text('Recording'), findsOneWidget);

    await screenReaderTap(tester, 'Pause recording');
    expect(h.recorder.count('pause'), 1);
    expect(find.text('Paused'), findsOneWidget);

    await screenReaderTap(tester, 'Resume recording');
    expect(h.recorder.count('resume'), 1);
    expect(find.text('Recording'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await screenReaderTap(tester, 'Send voice note');
    expect(h.recorder.count('stop'), 1);
    expect(h.send.calls, hasLength(1));
    handle.dispose();
  });

  testWidgets('19b. TalkBack can delete a recording, leaving the mic off', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await pumpComposer(tester, accessible: true);

    await screenReaderTap(tester, 'Record voice message');
    await tester.pump(const Duration(seconds: 2));
    await screenReaderTap(tester, 'Delete voice note');

    expect(h.recorder.count('cancel'), 1);
    expect(find.text('Voice note'), findsNothing);
    handle.dispose();
  });

  testWidgets('20. 360 x 640 at 200% text never overflows the panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await pumpComposer(tester, textScale: 2);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Pause recording'));
    await settle(tester);
    expect(find.text('Paused'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Stop and listen'));
    await settle(tester);
    expect(find.text('Voice note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(h.recorder.count('stop'), 1);
  });

  // ── 21–22: leaving saves the chat's voice draft ──────────────────────────

  testWidgets('21. leaving while locked saves the draft, then disposes', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    final shown = _timerSeconds(tester);

    await tester.pumpWidget(const SizedBox());
    await drainUntil(tester, () => h.draftSidecar.existsSync());
    await drainUntil(tester, () => h.recorder.count('dispose') == 1);

    expect(h.recorder.count('stop'), 1);
    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.draftSidecar.existsSync(), isTrue);
    final sidecar = jsonDecode(h.draftSidecar.readAsStringSync()) as Map;
    expect(sidecar['seconds'], shown);
    expect(sidecar['v'], 1);
    expect(
      h.recorder.calls.indexOf('dispose'),
      greaterThan(h.recorder.calls.indexOf('stop')),
      reason: 'the recorder stops before it is disposed',
    );
  });

  testWidgets('22. leaving a preview keeps it; reopening shows Draft', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await drainUntil(tester, () => h.draftSidecar.existsSync());

    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.draftSidecar.existsSync(), isTrue);

    // A new composer for the same chat picks the draft up after the frame.
    await pumpComposer(tester, chat: h.chat);
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(find.byTooltip('Send voice note'), findsOneWidget);
  });

  // ── 23–26, 34: sending and deleting a draft ──────────────────────────────

  testWidgets('23. sending a draft removes its marker', (tester) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final reopened = await pumpComposer(tester, chat: chat);
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    expect(reopened.draftAudio.existsSync(), isTrue);
    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);
    await drainUntil(tester, () => find.text('Voice note').evaluate().isEmpty);
    await settle(tester);

    expect(reopened.send.calls, hasLength(1));
    expect(reopened.send.calls.single['mediaType'], 'voice');
    expect(reopened.send.calls.single['durationSeconds'], 5);
    expect(reopened.draftSidecar.existsSync(), isFalse);
    expect(find.text('Voice note'), findsNothing);
  });

  testWidgets('24. deleting a draft removes both files', (tester) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final h = await pumpComposer(tester, chat: chat);
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete voice note'));
    await settle(tester);
    await drainUntil(tester, () => find.text('Voice note').evaluate().isEmpty);
    await settle(tester);

    expect(h.draftAudio.existsSync(), isFalse);
    expect(h.draftSidecar.existsSync(), isFalse);
    expect(find.text('Voice note'), findsNothing);
    expect(mic, findsOneWidget);
  });

  testWidgets('25. a draft whose chat cannot send stays on disk, unseen', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final h = await pumpComposer(tester, chat: chat, canSend: false);
    await drain(tester);

    expect(find.text('Draft'), findsNothing);

    await tester.pump(const Duration(seconds: 60));
    await drain(tester);

    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.draftSidecar.existsSync(), isTrue);
    expect(find.text('Voice note'), findsNothing);
  });

  testWidgets('34. a kept draft appears as Draft once sending opens', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final h = await pumpComposer(tester, chat: chat, canSend: false);
    await drain(tester);

    expect(find.text('Draft'), findsNothing);
    expect(h.draftSidecar.existsSync(), isTrue);

    h.hostKey.currentState!.setCanSend(true);
    await tester.pump();
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(h.draftSidecar.existsSync(), isTrue, reason: 'shown, not deleted');
  });

  testWidgets('26. a send that deleted its file lands idle, not in preview', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final h = await pumpComposer(tester, chat: chat);
    h.send.error = StateError('rejected');
    h.send.deleteFileOnThrow = true;
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);
    await drainUntil(tester, () => find.text('Voice note').evaluate().isEmpty);
    await settle(tester);

    expect(
      find.text("Couldn't send voice note. Try again."),
      findsOneWidget,
    );
    expect(find.text('Voice note'), findsNothing);
    expect(mic, findsOneWidget);
    expect(h.draftSidecar.existsSync(), isFalse);
  });

  // ── 32–33: the ✕ and a second finger ─────────────────────────────────────

  testWidgets('32. ✕ while locked cancels the recording, nothing is on', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Delete voice note'));
    await settle(tester);

    expect(h.recorder.count('cancel'), 1);
    expect(h.recorder.count('stop'), 0);
    expect(find.text('Voice note'), findsNothing);
    expect(mic, findsOneWidget);

    // The clock is gone too: no more amplitude sampling.
    final samples = h.recorder.count('amplitude');
    await tester.pump(const Duration(seconds: 1));
    expect(h.recorder.count('amplitude'), samples);
  });

  testWidgets('33. a second pointer during the hold does not take it over', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);

    final second = await tester.startGesture(
      tester.getCenter(find.text('Slide to cancel')),
      pointer: 99,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await second.up();
    await tester.pump();

    // The first finger still owns the hold: its release stops the recording.
    expect(h.recorder.count('stop'), 0);
    expect(find.text('Slide to cancel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);

    expect(h.recorder.count('stop'), 1);
    expect(find.text('Voice note'), findsOneWidget);
  });

  testWidgets('33b. a palm elsewhere before the hold fires does not take it', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 100));

    final palm = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
      pointer: 99,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await palm.up();
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    // The palm's lift must not read as the thumb's release.
    expect(h.recorder.count('start'), 1);
    expect(h.recorder.count('cancel'), 0);
    expect(find.text('Slide to cancel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await thumb.up();
    await settle(tester);

    expect(h.recorder.count('stop'), 1);
    expect(find.text('Voice note'), findsOneWidget);
  });

  testWidgets('33c. a palm still down when the hold ends leaves it the thumb\'s', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 100));
    final palm = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
      pointer: 99,
    );
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));

    await thumb.up();
    await settle(tester);

    expect(h.recorder.count('stop'), 1, reason: 'the thumb ends the hold');
    expect(find.text('Voice note'), findsOneWidget);
    await palm.up();
    await settle(tester);
    expect(h.recorder.count('stop'), 1);
  });

  // ── 36–40: races and the draft rule ──────────────────────────────────────

  testWidgets('36. lifting during a pending start stops once it lands', (
    tester,
  ) async {
    final recorder = FakeRecorder()..startGate = Completer<void>();
    await pumpComposer(tester, recorder: recorder);

    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 700));
    await settle(tester);
    expect(recorder.count('start'), 1);

    await gesture.up();
    await tester.pump();
    recorder.startGate!.complete();
    await settle(tester);

    // Nothing may keep recording with no finger down.
    expect(recorder.count('cancel'), 1);
    expect(find.text('Slide to cancel'), findsNothing);
    expect(mic, findsOneWidget);
  });

  testWidgets('37. Resume during Stop and listen cannot revive the recording', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Pause recording'));
    await settle(tester);

    h.recorder.stopGate = Completer<void>();
    await tester.tap(find.text('Stop and listen'));
    await tester.pump();
    await tester.tap(
      find.byTooltip('Resume recording'),
      warnIfMissed: false,
    );
    await tester.pump();
    h.recorder.stopGate!.complete();
    await settle(tester);

    expect(h.recorder.count('resume'), 0);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    final samples = h.recorder.count('amplitude');
    await tester.pump(const Duration(seconds: 1));
    expect(h.recorder.count('amplitude'), samples);
  });

  testWidgets('38. reopening during a slow save finds the draft', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    h.recorder.stopGate = Completer<void>();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // Back in the chat with the first composer's stop still running.
    await pumpComposer(tester, chat: h.chat);
    await drain(tester);
    expect(find.text('Draft'), findsNothing);

    h.recorder.stopGate!.complete();
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.draftSidecar.existsSync(), isTrue);
  });

  testWidgets('39. sending closing mid-recording saves a draft, nothing lost', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    h.hostKey.currentState!.setCanSend(false);
    await tester.pump();
    await drainUntil(tester, () => h.draftSidecar.existsSync());

    expect(h.recorder.count('stop'), 1);
    expect(h.recorder.count('cancel'), 0);
    expect(h.draftAudio.existsSync(), isTrue);
    expect(find.text('Voice note'), findsNothing);

    h.hostKey.currentState!.setCanSend(true);
    await tester.pump();
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('40. a share waits behind a draft and runs after ✕', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final h = await pumpComposer(tester, chat: chat);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessageInput)),
    );
    container.read(chatShareProvider(chat).notifier).state = const ReadyShare(
      chatName: 'Asha',
      text: 'shared words',
    );

    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('shared words'), findsNothing);

    await tester.tap(find.byTooltip('Delete voice note'));
    await settle(tester);
    await drainUntil(tester, () => find.text('Voice note').evaluate().isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    expect(h.draftSidecar.existsSync(), isFalse);
    expect(find.text('shared words'), findsOneWidget);
  });

  testWidgets('41. a share at the first frame goes first; the draft waits', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final doc = File('${tempDir.path}/report.pdf')..writeAsBytesSync([1]);
    await pumpComposer(
      tester,
      chat: chat,
      share: ReadyShare(
        chatName: 'Asha',
        files: [
          (
            path: doc.path,
            kind: SharedKind.document,
            mime: 'application/pdf',
          ),
        ],
      ),
    );
    await drainUntil(
      tester,
      () => find.text('Send to Asha?').evaluate().isNotEmpty,
    );
    expect(find.text('Send to Asha?'), findsOneWidget);

    // The draft has had time to load; it must not slide in under the dialog.
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    await drain(tester);
    expect(find.text('Draft'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('42. sending closing during start() leaves no mic on', (
    tester,
  ) async {
    final recorder = FakeRecorder()..startGate = Completer<void>();
    final handle = tester.ensureSemantics();
    final h = await pumpComposer(tester, recorder: recorder, accessible: true);

    tester.semantics.tap(find.semantics.byLabel('Record voice message'));
    await settle(tester);
    expect(recorder.count('start'), 1);

    h.hostKey.currentState!.setCanSend(false);
    await tester.pump();
    recorder.startGate!.complete();
    await settle(tester);

    expect(recorder.count('cancel'), 1);
    final samples = recorder.count('amplitude');
    await tester.pump(const Duration(seconds: 2));
    expect(recorder.count('amplitude'), samples, reason: 'nothing is running');

    // The composer is usable again once sending opens.
    h.hostKey.currentState!.setCanSend(true);
    await settle(tester);
    expect(mic, findsOneWidget);
    expect(find.text('Voice note'), findsNothing);
    handle.dispose();
  });

  testWidgets('43. a hold during a draft save cannot replace the draft', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    h.recorder.stopGate = Completer<void>();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final second = await pumpComposer(tester, chat: h.chat);
    final hold = await holdMic(tester);
    expect(second.recorder.count('start'), 0);

    await hold.up();
    h.recorder.stopGate!.complete();
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);

    expect(find.text('Draft'), findsOneWidget);
    expect(second.draftAudio.existsSync(), isTrue);
  });

  testWidgets('44. a dead native recorder lands in the preview, not a clock', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    h.recorder.states.addError(StateError('native failure'));
    await settle(tester);

    expect(h.recorder.count('stop'), 1);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(find.text('Recording'), findsNothing);
  });

  testWidgets('45. a stop that fails on a locked send says so, and frees it', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    h.recorder.throwOnStop = true;
    await tester.tap(find.byTooltip('Send voice note'));
    await settle(tester);

    expect(find.text("Couldn't save the voice note."), findsOneWidget);
    expect(h.send.calls, isEmpty);
    expect(find.text('Voice note'), findsNothing);
    expect(mic, findsOneWidget);
  });

  testWidgets('46. a pause that fails keeps recording and says so', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    h.recorder.throwOnPause = true;
    await tester.tap(find.byTooltip('Pause recording'));
    await settle(tester);

    expect(find.text("Couldn't pause the recording."), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    final samples = h.recorder.count('amplitude');
    await tester.pump(const Duration(seconds: 1));
    expect(h.recorder.count('amplitude'), greaterThan(samples));
  });

  testWidgets('47. sending closing during a preview keeps it as a draft', (
    tester,
  ) async {
    final h = await pumpComposer(tester);
    final gesture = await holdMic(tester);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await settle(tester);
    expect(find.byTooltip('Play voice note'), findsOneWidget);

    h.hostKey.currentState!.setCanSend(false);
    await tester.pump();
    await drainUntil(tester, () => h.draftSidecar.existsSync());

    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.recorder.count('cancel'), 0);

    h.hostKey.currentState!.setCanSend(true);
    await tester.pump();
    await drainUntil(tester, () => find.text('Draft').evaluate().isNotEmpty);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('48. TalkBack long click does not start and instantly stop', (
    tester,
  ) async {
    final h = await pumpComposer(tester, accessible: true);

    await tester.longPress(mic);
    await settle(tester);

    expect(h.recorder.count('start'), 0);
    expect(find.text('Hold to record'), findsNothing);
  });

  testWidgets('49. leaving with a draft retry pending leaves no timer', (
    tester,
  ) async {
    final chat = _nextChat();
    await seedDraft(tester, chat);
    final doc = File('${tempDir.path}/report.pdf')..writeAsBytesSync([1]);
    final h = await pumpComposer(
      tester,
      chat: chat,
      share: ReadyShare(
        chatName: 'Asha',
        files: [
          (
            path: doc.path,
            kind: SharedKind.document,
            mime: 'application/pdf',
          ),
        ],
      ),
    );
    await drainUntil(
      tester,
      () => find.text('Send to Asha?').evaluate().isNotEmpty,
    );
    await drain(tester);

    // A pending Timer would fail this test at its end.
    await tester.pumpWidget(const SizedBox());
    await drain(tester);

    expect(h.draftAudio.existsSync(), isTrue);
    expect(h.draftSidecar.existsSync(), isTrue);
  });

  testWidgets('50. haptics go to the vibrator, past what Samsung drops', (
    tester,
  ) async {
    const channel = MethodChannel('haptic_feedback');
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      haptics.add('${call.method}:${(call.arguments as Map)['usage']}');
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await pumpComposer(tester);
    final gesture = await lockMic(tester); // start, then lock
    await gesture.up();
    await settle(tester);

    expect(haptics, ['light:touch', 'light:touch']);
  });

  testWidgets('51. a haptic that fails does not disturb the recording', (
    tester,
  ) async {
    const channel = MethodChannel('haptic_feedback');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      _,
    ) async {
      throw PlatformException(code: 'VIBRATION_ERROR');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final h = await pumpComposer(tester);
    final gesture = await lockMic(tester);
    await gesture.up();
    await settle(tester);

    expect(h.recorder.count('start'), 1);
    expect(find.text('Recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Panel-only cases: no recording state, real behaviour ─────────────────

  Future<void> pumpStrip(
    WidgetTester tester, {
    double dragY = 0,
    bool cancelled = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: VoiceHoldStrip(
            elapsed: const Duration(seconds: 1),
            levels: const [.2, .5],
            dragX: 0,
            dragY: dragY,
            cancelled: cancelled,
            pulse: const AlwaysStoppedAnimation<double>(1),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('P1. the strip shows the clock and its pill rises with the drag', (
    tester,
  ) async {
    await pumpStrip(tester);
    expect(find.text('0:01'), findsOneWidget);
    expect(find.text('Slide to cancel'), findsOneWidget);
    final parked = tester.getTopLeft(find.byIcon(Icons.lock_open_outlined));

    await pumpStrip(tester, dragY: -40);
    final risen = tester.getTopLeft(find.byIcon(Icons.lock_open_outlined));
    expect(parked.dy - risen.dy, 40);

  });

  testWidgets('P2. past the cancel threshold the strip says release', (
    tester,
  ) async {
    await pumpStrip(tester, cancelled: true, dragY: -100);
    expect(find.text('Release to cancel'), findsOneWidget);
    expect(find.text('Slide to cancel'), findsNothing);
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    VoiceRecorderPanelMode mode = VoiceRecorderPanelMode.preview,
    bool draft = false,
    bool sending = false,
    VoidCallback? onDelete,
    VoidCallback? onSend,
    VoidCallback? onCenter,
    VoidCallback? onStopAndListen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: VoiceRecorderPanel(
            mode: mode,
            filePath: '/tmp/voice-panel-test.m4a',
            seconds: 74,
            levels: const [.2, .4, .8, .3],
            isDraft: draft,
            isSending: sending,
            onDelete: onDelete ?? () {},
            onCenter: onCenter ?? () {},
            onSend: onSend ?? () {},
            onStopAndListen: onStopAndListen,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('P3. the preview panel offers play, send and delete', (
    tester,
  ) async {
    var deleted = 0;
    var sent = 0;
    await pumpPanel(
      tester,
      onDelete: () => deleted++,
      onSend: () => sent++,
    );

    expect(find.text('Voice note'), findsOneWidget);
    expect(find.text('1:14'), findsOneWidget);
    expect(find.byTooltip('Play voice note'), findsOneWidget);
    expect(find.byTooltip('Send voice note'), findsOneWidget);

    await tester.tap(find.byTooltip('Send voice note'));
    await tester.tap(find.byTooltip('Delete voice note'));
    expect(sent, 1);
    expect(deleted, 1);
  });

  testWidgets('P4. a paused panel says Paused and disables the controls while '
      'a stop is in flight', (tester) async {
    var stopped = 0;
    var deleted = 0;
    await pumpPanel(
      tester,
      mode: VoiceRecorderPanelMode.paused,
      onStopAndListen: () => stopped++,
      onDelete: () => deleted++,
    );

    expect(find.text('Paused'), findsOneWidget);
    expect(find.byTooltip('Resume recording'), findsOneWidget);
    expect(find.text('Stop and listen'), findsOneWidget);

    await tester.tap(find.text('Stop and listen'));
    expect(stopped, 1);

    var disabledDeletes = 0;
    await pumpPanel(
      tester,
      mode: VoiceRecorderPanelMode.paused,
      sending: true,
      onDelete: () => disabledDeletes++,
      onSend: () => disabledDeletes++,
    );
    await tester.tap(find.byTooltip('Delete voice note'));
    await tester.tap(find.byTooltip('Send voice note'));
    expect(
      disabledDeletes,
      0,
      reason: 'a panel with a stop in flight ignores its controls',
    );
  });

  testWidgets('P5. the timer is read once, as minutes and seconds', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPanel(tester);
    // The panel fades in; before it does, the opacity hides its semantics.
    await tester.pump(const Duration(milliseconds: 400));

    final node = tester.getSemantics(
      find.bySemanticsLabel('1 minutes 14 seconds'),
    );
    expect(node.label, '1 minutes 14 seconds');
    // excludeSemantics: the printed 1:14 is not a second label on the node.
    expect(find.bySemanticsLabel('1:14'), findsNothing);
    handle.dispose();
  });
}
