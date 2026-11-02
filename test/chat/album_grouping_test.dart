/// Albums 12.5 A2–A7, F3: grouping in the list builder (pure).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/chat_run_grouping.dart';

final _base = DateTime(2026, 11, 1, 12);

Message _m(
  String id, {
  String sender = 'a',
  int sec = 0,
  String? album,
  int? index,
  String type = 'image',
  String? serverId,
}) => Message(
  localId: id,
  serverId: serverId,
  conversationId: 'c',
  senderId: sender,
  type: type,
  status: 'sent',
  createdAt: _base.add(Duration(seconds: sec)),
  albumId: album,
  albumIndex: index,
);

List<String> _ids(ChatUnit u) => [for (final r in u.rows) r.localId];

void main() {
  test('same albumId + sender → one entry at the earliest row', () {
    final units = groupChatUnits([
      _m('t', type: 'text', sec: 9),
      _m('p2', album: 'p0', index: 2, sec: 5),
      _m('p1', album: 'p0', index: 1, sec: 4),
      _m('p0', album: 'p0', index: 0, sec: 3),
      _m('old', type: 'text', sec: 1),
    ]);
    expect(units.map((u) => u.anchor.localId), ['t', 'p0', 'old']);
    expect(_ids(units[1]), ['p0', 'p1', 'p2']);
    expect(units[1].isAlbum, isTrue);
  });

  test('a message between two rows → still one album, at the earliest', () {
    final units = groupChatUnits([
      _m('late', album: 'p0', index: 1, sec: 60),
      _m('mid', type: 'text', sender: 'b', sec: 30),
      _m('p0', album: 'p0', index: 0, sec: 3),
    ]);
    expect(units.map((u) => u.anchor.localId), ['mid', 'p0']);
    expect(_ids(units[1]), ['p0', 'late']);
  });

  test('a different sender with the same albumId is not grouped', () {
    final units = groupChatUnits([
      _m('x', sender: 'b', album: 'p0', index: 1, sec: 4),
      _m('p0', album: 'p0', index: 0, sec: 3),
    ]);
    expect(units, hasLength(2));
    expect(units.every((u) => !u.isAlbum), isTrue);
  });

  test('one visible row → a normal entry (A3)', () {
    final units = groupChatUnits([_m('p1', album: 'p0', index: 1)]);
    expect(units.single.isAlbum, isFalse);
    expect(_ids(units.single), ['p1']);
  });

  test('tiles in albumIndex order, ties by time then id (A4)', () {
    final units = groupChatUnits([
      _m('b', album: 'p0', index: 1, sec: 2),
      _m('c', album: 'p0', index: 0, sec: 2),
      _m('a', album: 'p0', index: 1, sec: 2),
      _m('p0', album: 'p0', index: 2, sec: 1),
    ]);
    expect(_ids(units.single), ['c', 'a', 'b', 'p0']);
  });

  test('run flags treat the album as one message (A5)', () {
    final units = groupChatUnits([
      _m('t2', type: 'text', sec: 30),
      _m('p1', album: 'p0', index: 1, sec: 20),
      _m('p0', album: 'p0', index: 0, sec: 10),
      _m('t1', type: 'text', sec: 0),
    ]);
    final flags = computeChatRunFlags([for (final u in units) u.anchor]);
    expect(flags, hasLength(3));
    expect([for (final f in flags) (f.runStart, f.runEnd)], [
      (false, true),
      (false, false),
      (true, false),
    ]);
  });

  test('a jump to a middle row lands on the album entry (A6)', () {
    final units = groupChatUnits([
      _m('p2', album: 'p0', index: 2, serverId: 's2'),
      _m('p1', album: 'p0', index: 1, serverId: 's1'),
      _m('p0', album: 'p0', index: 0, serverId: 's0'),
      _m('t', type: 'text', serverId: 'st'),
    ]);
    int find(Message target) =>
        units.indexWhere((u) => unitHolds(u.rows, target));
    expect(find(_m('p1')), 0);
    // A starred card rebuilt from the server: its localId is the server id.
    expect(find(_m('s2')), 0);
    expect(find(_m('zz', serverId: 's1')), 0);
    expect(find(_m('t')), 1);
  });

  test('a page boundary splitting an album shows the loaded part (A7)', () {
    final loaded = groupChatUnits([
      _m('p3', album: 'p0', index: 3, sec: 4),
      _m('p2', album: 'p0', index: 2, sec: 3),
    ]);
    expect(_ids(loaded.single), ['p2', 'p3']);
    final more = groupChatUnits([
      _m('p3', album: 'p0', index: 3, sec: 4),
      _m('p2', album: 'p0', index: 2, sec: 3),
      _m('p1', album: 'p0', index: 1, sec: 2),
      _m('p0', album: 'p0', index: 0, sec: 1),
    ]);
    expect(_ids(more.single), ['p0', 'p1', 'p2', 'p3']);
  });

  test('albumLabel (F3)', () {
    List<Message> of(int p, int v) => [
      for (var i = 0; i < p; i++) _m('p$i'),
      for (var i = 0; i < v; i++) _m('v$i', type: 'video'),
    ];
    expect(albumLabel(of(5, 0)), '5 photos');
    expect(albumLabel(of(1, 0)), '1 photo');
    expect(albumLabel(of(0, 2)), '2 videos');
    expect(albumLabel(of(0, 1)), '1 video');
    expect(albumLabel(of(3, 2)), '3 photos and 2 videos');
    expect(albumLabel(of(1, 1)), '1 photo and 1 video');
  });
}
