import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  test('hazard stripe does not paint outside a 4px band', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 200, 48));
    paintHazardStripe(
      canvas,
      const Size(4, 48),
      KelolaColors.dark.red,
      KelolaColors.dark.redDim,
    );
    final image = await recorder.endRecording().toImage(200, 48);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    final data = bytes!.buffer.asUint8List();

    Color at(int x, int y) {
      final i = (y * image.width + x) * 4;
      return Color.fromARGB(data[i + 3], data[i], data[i + 1], data[i + 2]);
    }

    final inBand = at(1, 24);
    final overflow = at(80, 24);
    expect(inBand.a, greaterThan(0),
        reason: 'band itself should be painted, got $inBand');
    expect(overflow.a, 0,
        reason: 'stripe overflow painted x=80, got $overflow');
  });
}
