import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'parity_helper.dart';

/// test/fixtures/line-options.* was exported by Chrome on macOS (Arial) and
/// uses curved and straight routes, port offsets, several pulses, glow levels
/// and dashed/dotted tracks. Needs the macOS Arial fonts; skipped elsewhere.
void main() {
  const dir = '/System/Library/Fonts/Supplemental';
  final fonts = ['$dir/Arial.ttf', '$dir/Arial Bold.ttf'];

  testWidgets('matches the editor PNG export with every line option', (tester) async {
    await tester.runAsync(() async {
      final percent = await compareWithEditorPng(
        name: 'line-options',
        projectPath: 'test/fixtures/line-options.flow.json',
        pngPath: 'test/fixtures/line-options.png',
        fontFiles: fonts,
      );
      expect(percent, lessThan(1.0));
    });
  }, skip: !fonts.every((f) => File(f).existsSync()));
}
