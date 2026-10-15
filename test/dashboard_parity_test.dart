import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'parity_helper.dart';

/// Dashboard features exported by Chrome on macOS (Arial): callout labels with leaders,
/// battery level, status badges, header, day scene (dashboard-day) and dark theme with
/// rain, a low-battery badge and a tiled element (dashboard-dark).
void main() {
  const dir = '/System/Library/Fonts/Supplemental';
  final fonts = ['$dir/Arial.ttf', '$dir/Arial Bold.ttf'];
  final skip = !fonts.every((f) => File(f).existsSync());

  for (final name in ['dashboard-day', 'dashboard-dark', 'villa']) {
    testWidgets('matches the editor PNG export: $name', (tester) async {
      await tester.runAsync(() async {
        final percent = await compareWithEditorPng(
          name: name,
          projectPath: 'test/fixtures/$name.flow.json',
          pngPath: 'test/fixtures/$name.png',
          fontFiles: fonts,
        );
        expect(percent, lessThan(1.0));
      });
    }, skip: skip);
  }
}
