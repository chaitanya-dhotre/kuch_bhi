import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';

// break-ui 2026-11-18: Requests showed "B" and Home "BM" for the same person.
void main() {
  test('initialsOf matches the Home rule', () {
    expect(initialsOf('Bartholomew Maximilian Featherstonehaugh'), 'BM');
    expect(initialsOf('bartholomew maximilian'),
        nameInitials('bartholomew maximilian'));
    expect(initialsOf('Avium'), 'A');
    expect(initialsOf('  Z  '), 'Z');
    expect(initialsOf('   ', fallback: 'G'), 'G');
    expect(initialsOf('सुपर 🦫🔥 test'), 'सT');
    expect(initialsOf('Raj 🦫'), 'R');
    expect(initialsOf('🦫 party'), 'P');
    expect(initialsOf('🦫🔥'), '🦫'.runes.map(String.fromCharCode).first);
  });
}
