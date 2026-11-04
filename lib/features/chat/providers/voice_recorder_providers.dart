import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

final voiceRecorderFactoryProvider = Provider<AudioRecorder Function()>(
  (_) => AudioRecorder.new,
);

class MicPermission {
  const MicPermission();

  Future<PermissionStatus> status() => Permission.microphone.status;

  Future<PermissionStatus> request() => Permission.microphone.request();

  Future<bool> openSettings() => openAppSettings();
}

final micPermissionProvider = Provider<MicPermission>(
  (_) => const MicPermission(),
);

final voiceDraftDirProvider = Provider<Future<Directory> Function()>(
  (_) => getApplicationDocumentsDirectory,
);
