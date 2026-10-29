import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/screens/google_onboarding_screen.dart';
import 'package:kuch_bhi/features/profile/screens/crop_photo_screen.dart';

import '../fakes/fake_auth_repository.dart';
import 'auth_harness.dart';

class _FakePicker extends ImagePickerPlatform {
  Object? error;
  XFile? result;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (error != null) throw error!;
    return result;
  }
}

const _screen = GoogleOnboardingScreen(
  email: 'Avni.R@gmail.com',
  displayName: 'Avni R',
  idToken: 'tok',
);

final _ok = GoogleAuthResult(user: fakeUser(), isNew: true);

final _createButton = find.descendant(
    of: find.bySubtype<ButtonStyleButton>(),
    matching: find.text('Create account'));

/// Onboarding at its own path: `/` is the splash (AppRoutes.splash).
Future<void> _pump(WidgetTester tester,
        {FakeAuthNotifier? notifier, bool narrow = false}) =>
    pumpAuth(tester, const Text('page:/'),
        notifier: notifier,
        narrow: narrow,
        initial: '/onboard',
        routes: [GoRoute(path: '/onboard', builder: (_, __) => _screen)]);

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(_createButton);
  await tester.tap(_createButton);
  await tester.pump();
  await tester.pump();
}

void main() {
  late _FakePicker picker;
  setUp(() {
    picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
  });

  testWidgets('username prefilled from the email; email read-only',
      (tester) async {
    await _pump(tester);
    expect(find.text('avni_r'), findsOneWidget);
    final email = tester.widget<TextField>(fieldWithLabel('Email'));
    expect(email.readOnly, isTrue);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Complete your profile'), findsOneWidget);
    expectNoAccentOrErrorText(tester);
  });

  testWidgets('display name required: no call', (tester) async {
    final n = FakeAuthNotifier()..googleResult = _ok;
    await _pump(tester, notifier: n);
    await tester.enterText(fieldWithLabel('Display name'), '');
    await _submit(tester);
    expect(find.text('Enter your name'), findsOneWidget);
    expect(n.calls, isEmpty);
  });

  testWidgets('username lower-cased at submit, no photo = null file',
      (tester) async {
    final n = FakeAuthNotifier()..googleResult = _ok;
    await _pump(tester, notifier: n);
    await tester.enterText(fieldWithLabel('Username'), 'Avni_X');
    await _submit(tester);
    expect(n.calls, ['registerWithGoogle']);
    expect(n.args.single['username'], 'avni_x');
    expect(n.args.single['avatarFile'], isNull);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('page:/'), findsOneWidget, reason: 'go(splash)');
  });

  testWidgets('a picked photo goes through the crop step and is submitted',
      (tester) async {
    final file = File('${Directory.systemTemp.createTempSync().path}/p.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    picker.result = XFile(file.path);
    final n = FakeAuthNotifier()..googleResult = _ok;
    await _pump(tester, notifier: n);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byType(AppAvatar)),
        isSemantics(label: 'Add a profile photo', isButton: true));
    await tester.tap(find.byType(AppAvatar));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CropPhotoScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(CropPhotoScreen))).pop(file);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSemantics(find.byType(AppAvatar)),
        isSemantics(label: 'Change profile photo', isButton: true));
    handle.dispose();
    await _submit(tester);
    expect((n.args.single['avatarFile'] as File?)?.path, file.path);
  });

  testWidgets('picker failure toasts Edit Profile copy', (tester) async {
    picker.error = PlatformException(code: 'photo_access_denied');
    await _pump(tester);
    await tester.tap(find.byType(AppAvatar));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't open your photos."), findsOneWidget);
  });

  testWidgets('photoFailed shows its (non-error) toast', (tester) async {
    final n = FakeAuthNotifier()
      ..googleResult =
          GoogleAuthResult(user: fakeUser(), isNew: true, photoFailed: true);
    await _pump(tester, notifier: n);
    await _submit(tester);
    expect(find.text(kPhotoFailedCopy), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('username taken lands on the field', (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError(kUsernameTakenCopy, field: 'username');
    await _pump(tester, notifier: n);
    await _submit(tester);
    expect(find.text('That username is taken.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('409 toasts and goes to Login', (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError(kGoogleAccountExistsCopy, code: '409');
    await _pump(tester, notifier: n);
    await _submit(tester);
    expect(find.text(kGoogleAccountExistsCopy), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('page:/login'), findsOneWidget);
  });

  testWidgets('Use a different Google account: forget once, then /login',
      (tester) async {
    final n = FakeAuthNotifier();
    await _pump(tester, notifier: n);
    await tester.ensureVisible(find.text('Use a different Google account'));
    await tester.tap(find.text('Use a different Google account'));
    await tester.pumpAndSettle();
    expect(n.calls, ['forget']);
    expect(find.text('page:/login'), findsOneWidget);
  });

  testWidgets('system Back also forgets the account and goes to /login',
      (tester) async {
    final n = FakeAuthNotifier();
    await _pump(tester, notifier: n);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(n.calls, ['forget']);
    expect(find.text('page:/login'), findsOneWidget);
  });

  testWidgets('360dp x 200% text: no overflow', (tester) async {
    await _pump(tester, narrow: true);
    expect(tester.takeException(), isNull);
    await tester.enterText(fieldWithLabel('Display name'), '');
    await _submit(tester);
    expect(tester.takeException(), isNull);
  });
}
