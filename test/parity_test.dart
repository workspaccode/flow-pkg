import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'parity_helper.dart';

/// The bundled example was exported on a machine where Arial fell back to
/// DejaVu Sans, so its labels are compared using DejaVu Sans (test/fonts, or
/// FLOW_PARITY_FONTS). Skipped when the fonts are missing.
void main() {
  final dir = Platform.environment['FLOW_PARITY_FONTS'] ?? 'test/fonts';
  final fonts = ['$dir/DejaVuSans.ttf', '$dir/DejaVuSans-Bold.ttf'];

  testWidgets('matches the editor PNG export of the example', (tester) async {
    await tester.runAsync(() async {
      final percent = await compareWithEditorPng(
        name: 'example',
        projectPath: '../../examples/hybrid-energy-flow.flow.json',
        pngPath: '../../examples/hybrid-energy-flow.png',
        fontFiles: fonts,
      );
      expect(percent, lessThan(1.0));
    });
  }, skip: !fonts.every((f) => File(f).existsSync()));
}
