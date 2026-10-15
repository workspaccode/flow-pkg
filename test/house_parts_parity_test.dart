import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'parity_helper.dart';

/// test/fixtures/house-parts.* was exported by Chrome on macOS (Arial): a house with
/// attached roof solar, wall inverter, battery and utility pole, joined by lines drawn
/// above the elements (onTop). Needs the macOS Arial fonts; skipped elsewhere.
void main() {
  const dir = '/System/Library/Fonts/Supplemental';
  final fonts = ['$dir/Arial.ttf', '$dir/Arial Bold.ttf'];

  testWidgets('matches the editor PNG export of a house with parts', (tester) async {
    await tester.runAsync(() async {
      final percent = await compareWithEditorPng(
        name: 'house-parts',
        projectPath: 'test/fixtures/house-parts.flow.json',
        pngPath: 'test/fixtures/house-parts.png',
        fontFiles: fonts,
      );
      expect(percent, lessThan(1.0));
    });
  }, skip: !fonts.every((f) => File(f).existsSync()));
}
