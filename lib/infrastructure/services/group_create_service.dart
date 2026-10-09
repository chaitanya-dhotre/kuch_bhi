import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../core/network/pocketbase_client.dart';

/// PocketBase write/read steps of group creation.
///
/// Moved verbatim from `create_group_screen._createGroup` (Task 10,
/// guard 5: structure move, no behavior edits). Local Drift / encryption /
/// navigation orchestration stays in the screen and preserves call order.
class GroupCreateService {
  GroupCreateService(this._client);

  final PocketBaseClient _client;

  String get baseUrl => _client.pb.baseUrl;

  Future<RecordModel> createConversation({
    required Map<String, dynamic> convBody,
    File? iconFile,
  }) async {
    final pb = _client.pb;
    late RecordModel conv;
    if (iconFile != null) {
      conv = await pb.collection('conversations').create(
        body: convBody,
        files: [
          http.MultipartFile.fromBytes(
            'icon',
            await iconFile.readAsBytes(),
            filename: 'icon.jpg',
          ),
        ],
      );
    } else {
      conv = await pb.collection('conversations').create(body: convBody);
    }
    return conv;
  }

  Future<RecordModel> createMemberRecord(Map<String, dynamic> body) async {
    final pb = _client.pb;
    return pb.collection('conversation_members').create(body: body);
  }

  Future<List<RecordModel>> addMembers({
    required String conversationId,
    required List<String> memberIds,
  }) async {
    final pb = _client.pb;
    final List<RecordModel> memberRecords = [];
    for (final memberId in memberIds) {
      final rec = await pb.collection('conversation_members').create(body: {
        'conversation_id': conversationId,
        'user_id':         memberId,
        'role':            'member',
      });
      memberRecords.add(rec);
    }
    return memberRecords;
  }

  Future<RecordModel> getUserRecord(String userId) async {
    final pb = _client.pb;
    return pb.collection('users').getOne(userId);
  }

  Future<RecordModel> createGroupKey(Map<String, dynamic> body) async {
    final pb = _client.pb;
    return pb.collection('group_keys').create(body: body);
  }

  Future<RecordModel> createMessage(Map<String, dynamic> body) async {
    final pb = _client.pb;
    return pb.collection('messages').create(body: body);
  }
}

final groupCreateServiceProvider = Provider<GroupCreateService>((ref) {
  return GroupCreateService(ref.watch(pocketbaseClientProvider));
});
