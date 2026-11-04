import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_waveform.dart';

void main() {
  test('waveLevel maps dBFS to the visible range', () {
    expect(waveLevel(-160), 0.06);
    expect(waveLevel(-50), 0.06);
    expect(waveLevel(-25), 0.5);
    expect(waveLevel(0), 1.0);
    expect(waveLevel(3), 1.0);
    expect(waveLevel(double.nan), 0.06);
  });

  test('bucketLevels keeps peaks and handles empty or short input', () {
    expect(bucketLevels([], 10), isEmpty);
    expect(bucketLevels([.1, .2, .3], 10), [.1, .2, .3]);
    expect(bucketLevels([.1, .8, .2, .3, .4, .9, .1, .2, .7, .5], 5), [
      .8,
      .3,
      .9,
      .2,
      .7,
    ]);
    expect(bucketLevels([.1], 0), isEmpty);
  });
}
