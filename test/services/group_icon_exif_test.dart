import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/infrastructure/services/group_create_service.dart';

import '../offline/char_harness.dart';

/// Security audit §7.1: a group icon went up as the raw picked bytes, EXIF
/// (GPS included) and all. Both icon uploads now re-encode like the avatar:
/// the server only ever gets the re-encoder's output, asked to drop EXIF.
const _gps = 'GPSLatitude=18.5204N'; // stands in for the picked photo's EXIF
const _clean = 'REENCODED-JPEG';

class _FakeCompress extends Fake implements FlutterImageCompressPlatform {
  final keepExif = <bool>[];

  @override
  Future<Uint8List?> compressWithFile(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async {
    this.keepExif.add(keepExif);
    expect(format, CompressFormat.jpeg);
    return Uint8List.fromList(utf8.encode(_clean));
  }
}

void main() {
  late _FakeCompress compress;
  late File picked;
  late List<String> uploads; // multipart bodies sent to conversations

  setUp(() async {
    compress = _FakeCompress();
    FlutterImageCompressPlatform.instance = compress;
    final dir = await Directory.systemTemp.createTemp('group_icon');
    addTearDown(() => dir.delete(recursive: true));
    picked = File('${dir.path}/picked.jpg')
      ..writeAsBytesSync(utf8.encode('JFIF $_gps pixels'));
    uploads = [];
  });

  CharHarness harness() => charHarness(
        clientFactory: () => MockClient((req) async {
          if (req.url.path.startsWith('/api/collections/conversations')) {
            uploads.add(latin1.decode(req.bodyBytes));
            return http.Response(
              jsonEncode({
                'id': 'g1',
                'collectionId': 'conversations',
                'collectionName': 'conversations',
                'icon': 'icon_abc.jpg',
                'name': 'G',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"message":"unhandled"}', 404);
        }),
      );

  void expectStripped() {
    expect(uploads, hasLength(1));
    expect(uploads.single, contains(_clean));
    expect(uploads.single, isNot(contains(_gps)),
        reason: 'the picked bytes (with their EXIF) never leave the phone');
    expect(compress.keepExif, [false]);
  }

  test('group create: the icon is re-encoded without EXIF', () async {
    final h = harness();
    addTearDown(h.close);
    await GroupCreateService(h.pbClient).createConversation(
      convBody: {'type': 'group', 'name': 'G'},
      iconFile: picked,
    );
    expectStripped();
  });

  test('group settings: a new icon is re-encoded without EXIF', () async {
    final h = harness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await h.db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: 'm1',
        conversationId: 'g1',
        userId: 'u_test',
        joinedAt: DateTime.utc(2026, 1, 1),
        role: const Value('admin'),
      ),
    );
    await buildRepo(h).updateGroupInfo('g1', iconFile: picked);
    expectStripped();
  });
}
