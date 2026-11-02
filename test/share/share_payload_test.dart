// 12.1 C1–C7: how a share is sorted, capped and summed up.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/share/share_payload.dart';

SharedItem _item(String mime, [String name = 'x', int size = 1000]) =>
    SharedItem(uri: 'content://x/$name', mime: mime, name: name, size: size);

const _mb = 1024 * 1024;

void main() {
  group('C1 sorting', () {
    test('photos by MIME, SVG is a document', () {
      for (final m in [
        'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', //
      ]) {
        expect(sharedKindOf(m, 'a'), SharedKind.photo, reason: m);
      }
      expect(sharedKindOf('image/svg+xml', 'a.svg'), SharedKind.document);
    });

    test('videos by MIME; PDF, MP3, ZIP are documents', () {
      expect(sharedKindOf('video/mp4', 'a'), SharedKind.video);
      expect(sharedKindOf('video/3gpp', 'a'), SharedKind.video);
      for (final m in ['application/pdf', 'audio/mpeg', 'application/zip']) {
        expect(sharedKindOf(m, 'a.mp4'), SharedKind.document, reason: m);
      }
    });

    test('unknown MIME falls back to the extension', () {
      const unknown = 'application/octet-stream';
      expect(sharedKindOf(unknown, 'clip.MOV'), SharedKind.video);
      expect(sharedKindOf(unknown, 'clip.3gp'), SharedKind.video);
      expect(sharedKindOf(unknown, 'pic.heic'), SharedKind.photo);
      expect(sharedKindOf(unknown, 'noext'), SharedKind.document);
      expect(sharedKindOf('', 'a.jpg'), SharedKind.photo);
    });
  });

  group('C2 / C3 plan', () {
    test('25 items → the first 20 kept, cap flag set', () {
      final items = [for (var i = 0; i < 25; i++) _item('image/jpeg', 'p$i')];
      final plan = planShare(ShareInPayload(items: items));
      expect(plan.items, hasLength(20));
      expect(plan.items.first.name, 'p0');
      expect(plan.items.last.name, 'p19');
      expect(plan.overCap, isTrue);
      expect(planShare(ShareInPayload(items: items.take(20).toList())).overCap,
          isFalse);
    });

    test('a known 150 MB item is dropped before any copy; unknown size kept',
        () {
      final plan = planShare(ShareInPayload(items: [
        _item('video/mp4', 'big', 150 * _mb),
        _item('image/jpeg', 'ok'),
        _item('image/jpeg', 'unknown', -1),
      ]));
      expect(plan.items.map((i) => i.name), ['ok', 'unknown']);
      expect(plan.tooBig, 1);
    });

    test('only a too-big item and no text → nothing to open', () {
      final plan = planShare(ShareInPayload(
        items: [_item('video/mp4', 'big', 150 * _mb)],
      ));
      expect(plan.isEmpty, isTrue);
      expect(plan.tooBig, 1);
      expect(planShare(const ShareInPayload(text: 'hi')).isEmpty, isFalse);
    });

    test('left-out toast wording', () {
      expect(tooBigLeftOut(1), '1 item is over 100 MB and was left out.');
      expect(tooBigLeftOut(2), '2 items are over 100 MB and were left out.');
      expect(unreadableLeftOut(1),
          "1 item couldn't be opened and was left out.");
      expect(unreadableLeftOut(2),
          "2 items couldn't be opened and were left out.");
    });
  });

  group('C7 summary', () {
    List<SharedItem> n(int c, String mime) =>
        [for (var i = 0; i < c; i++) _item(mime)];

    test('photos and videos use the album wording', () {
      expect(shareSummary(n(1, 'image/jpeg'), null), '1 photo');
      expect(shareSummary(n(5, 'image/jpeg'), null), '5 photos');
      expect(shareSummary(n(2, 'video/mp4'), null), '2 videos');
      expect(
        shareSummary([...n(3, 'image/png'), ...n(2, 'video/mp4')], null),
        '3 photos and 2 videos',
      );
    });

    test('documents, mixed, and text alongside items', () {
      expect(shareSummary(n(1, 'application/pdf'), null), '1 file');
      expect(shareSummary(n(3, 'application/pdf'), null), '3 files');
      expect(
        shareSummary([...n(5, 'image/jpeg'), ...n(1, 'application/pdf')], null),
        '6 items',
      );
      expect(shareSummary(n(1, 'image/jpeg'), 'look'), '1 photo');
    });

    test('Link only for a single URL, Text otherwise', () {
      expect(shareSummary(const [], ' https://example.com/trip '), 'Link');
      expect(shareSummary(const [], 'http://a.b'), 'Link');
      expect(shareSummary(const [], 'look https://example.com'), 'Text');
      expect(shareSummary(const [], 'hello'), 'Text');
    });
  });
}
