import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/profile/screens/crop_photo_screen.dart';
import 'package:kuch_bhi/features/profile/screens/edit_profile_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';

import '../fakes/fake_auth_repository.dart';

class _FakePicker extends ImagePickerPlatform {
  Object? error;
  XFile? result;
  ImagePickerOptions? lastOptions;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastOptions = options;
    if (error != null) throw error!;
    return result;
  }
}

Finder get _name => find.byType(TextField).at(0);
Finder get _username => find.byType(TextField).at(1);
Finder get _saveButton => find.byType(AppButton);
VoidCallback? _saveHandler(WidgetTester t) =>
    t.widget<AppButton>(_saveButton).onPressed;

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  User? user,
  bool online = true,
}) async {
  final repo = FakeAuthRepository(user ?? fakeUser());
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
  ]);
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: warmPopLight(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const EditProfileScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  late _FakePicker picker;
  setUp(() {
    picker = _FakePicker();
    ImagePickerPlatform.instance = picker;
  });

  testWidgets('shows the existing avatarUrl and prefilled fields',
      (tester) async {
    await _pump(tester, user: fakeUser(avatarUrl: 'https://x.test/a.png'));
    expect(tester.widget<AppAvatar>(find.byType(AppAvatar)).url,
        'https://x.test/a.png');
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('avni'), findsOneWidget);
    tester.takeException(); // network image cannot load in tests
  });

  testWidgets('Save is disabled until dirty and valid', (tester) async {
    await _pump(tester);
    expect(_saveHandler(tester), isNull, reason: 'not dirty');

    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    expect(_saveHandler(tester), isNotNull);

    await tester.enterText(_username, 'ab');
    await tester.pump();
    expect(_saveHandler(tester), isNull, reason: 'invalid username');
  });

  testWidgets('username validator messages', (tester) async {
    await _pump(tester);
    await tester.enterText(_username, '');
    await tester.pump();
    expect(find.text('Enter a username'), findsOneWidget);
    await tester.enterText(_username, 'ab');
    await tester.pump();
    expect(find.text('At least 3 characters'), findsOneWidget);
    await tester.enterText(_username, 'a b!');
    await tester.pump();
    expect(find.text('Letters, numbers and underscores only'), findsOneWidget);
    await tester.enterText(_name, '');
    await tester.pump();
    expect(find.text('Enter a display name'), findsOneWidget);
  });

  testWidgets('offline: Save disabled with ONE dim and ONE hint',
      (tester) async {
    await _pump(tester, online: false);
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    expect(_saveHandler(tester), isNull);
    expect(find.text('Available online'), findsOneWidget);
    expect(find.text("You're offline — actions are available when you're back."),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is Opacity && w.opacity == .38),
        findsOneWidget);
  });

  testWidgets('success pops, toasts and shows the saved user', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    _saveHandler(tester)!();
    await tester.pumpAndSettle();
    expect(repo.updateProfileCalls, 1);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('UsernameTakenException -> field error, screen stays',
      (tester) async {
    final repo = await _pump(tester);
    repo.onUpdateProfile = () => Future.error(const UsernameTakenException());
    await tester.enterText(_username, 'taken_one');
    await tester.pump();
    _saveHandler(tester)!();
    await tester.pumpAndSettle();
    expect(find.text('That username is taken.'), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(_saveHandler(tester), isNull, reason: 'taken value is not savable');
    await tester.enterText(_username, 'taken_two');
    await tester.pumpAndSettle();
    expect(find.text('That username is taken.'), findsNothing);
  });

  testWidgets('generic failure -> friendly toast, no exception text',
      (tester) async {
    final repo = await _pump(tester);
    repo.onUpdateProfile = () => Future.error(StateError('boom-secret'));
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    _saveHandler(tester)!();
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    expect(find.textContaining('boom-secret'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Avni Rao'), findsOneWidget, reason: 'edits kept');
  });

  testWidgets('a blackholed save releases at 8s with edits kept',
      (tester) async {
    final repo = await _pump(tester);
    repo.onUpdateProfile = () => Completer<User>().future;
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    _saveHandler(tester)!();
    await tester.pump();
    expect(tester.widget<AppButton>(_saveButton).busy, isTrue);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.widget<AppButton>(_saveButton).busy, isTrue);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    expect(tester.widget<AppButton>(_saveButton).busy, isFalse);
    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    expect(find.text('Avni Rao'), findsOneWidget);
  });

  testWidgets('with a photo the bound is 30s', (tester) async {
    final file = File('${Directory.systemTemp.createTempSync().path}/p.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    final repo = await _pump(tester);
    picker.result = XFile(file.path);
    repo.onUpdateProfile = () => Completer<User>().future;
    await tester.tap(find.byType(AppAvatar));
    await tester.pump();
    await tester.pump();
    expect(picker.lastOptions?.maxWidth, 1024);
    expect(picker.lastOptions?.maxHeight, 1024);
    expect(picker.lastOptions?.imageQuality, 80);
    // F5: the pick goes through the crop step; finish it with the file.
    expect(find.byType(CropPhotoScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(CropPhotoScreen))).pop(file);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    _saveHandler(tester)!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(tester.widget<AppButton>(_saveButton).busy, isTrue);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    expect(tester.widget<AppButton>(_saveButton).busy, isFalse);
    expect(repo.lastAvatarFile?.path, file.path);
  });

  testWidgets('back: clean pops, dirty asks, saving is blocked',
      (tester) async {
    final repo = await _pump(tester);
    // dirty -> dialog
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text("Your edits won't be saved."), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);

    // saving -> blocked, no dialog
    repo.onUpdateProfile = () => Completer<User>().future;
    _saveHandler(tester)!();
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
    await tester.pump(const Duration(seconds: 9)); // timeout releases

    // dirty -> Discard pops
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
  });

  testWidgets('clean back pops with no dialog', (tester) async {
    await _pump(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('picker PlatformException -> toast', (tester) async {
    await _pump(tester);
    picker.error = PlatformException(code: 'photo_access_denied');
    await tester.tap(find.byType(AppAvatar));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't open your photos."), findsOneWidget);
    expect(find.textContaining('photo_access_denied'), findsNothing);
  });

  testWidgets('no setState after dispose (save + timeout)', (tester) async {
    final repo = await _pump(tester);
    final done = Completer<User>();
    repo.onUpdateProfile = () => done.future;
    await tester.enterText(_name, 'Avni Rao');
    await tester.pump();
    _saveHandler(tester)!();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    done.complete(repo.user);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('F22: picker copy, replaced crop and last crop leave temp; '
      'files outside temp are never touched', (tester) async {
    final temp = Directory.systemTemp.createTempSync('f22');
    final outside = Directory.systemTemp.createTempSync('f22_out');
    addTearDown(() {
      temp.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temp.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    File f(Directory d, String n) => File('${d.path}/$n')..writeAsBytesSync(png);
    final pick1 = f(temp, 'pick1.png');
    final crop1 = f(temp, 'crop1.png');
    final pick2 = f(outside, 'gallery.png');
    final crop2 = f(temp, 'crop2.png');
    Future<void> io() =>
        tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));

    await _pump(tester);
    Future<void> pickAndCrop(File pick, File crop) async {
      picker.result = XFile(pick.path);
      await tester.tap(find.byType(AppAvatar));
      await tester.pump();
      await tester.pump();
      Navigator.of(tester.element(find.byType(CropPhotoScreen))).pop(crop);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await io();
    }

    await pickAndCrop(pick1, crop1);
    expect(pick1.existsSync(), isFalse, reason: 'picker copy in temp');
    expect(crop1.existsSync(), isTrue, reason: 'still the chosen photo');

    await pickAndCrop(pick2, crop2);
    expect(crop1.existsSync(), isFalse, reason: 'replaced crop');
    expect(pick2.existsSync(), isTrue, reason: 'outside temp: never deleted');
    expect(crop2.existsSync(), isTrue);

    await tester.pumpWidget(const SizedBox());
    await io();
    expect(crop2.existsSync(), isFalse, reason: 'screen closed');
  });
}
