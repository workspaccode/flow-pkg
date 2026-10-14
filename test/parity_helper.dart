import 'dart:io';
import 'dart:ui' as ui;

import 'package:flow_studio/flow_studio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders [projectPath] at 2× and 0.75 s and compares it with [pngPath], a PNG
/// the editor exported from the same project with those settings.
///
/// [fontFiles] are registered as "Arial": they must be the fonts the browser
/// used for that export. Set `FLOW_PARITY_OUT=<dir>` to also write
/// `<name>-flutter.png` and `<name>-diff.png`.
Future<double> compareWithEditorPng({
  required String name,
  required String projectPath,
  required String pngPath,
  required List<String> fontFiles,
}) async {
  final loader = FontLoader('Arial');
  for (final f in fontFiles) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();

  final controller = FlowController();
  await controller.loadJsonString(File(projectPath).readAsStringSync());
  final project = controller.project!;
  final scene = FlowScene.build(project, controller.images, const FlowTextStyle());

  const scale = 2.0;
  final w = (project.width * scale).ceil(), h = (project.height * scale).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  scene.paint(canvas, time: .75);
  final image = await recorder.endRecording().toImage(w, h);
  final ours = (await image.toByteData())!.buffer.asUint8List();

  final codec = await ui.instantiateImageCodec(File(pngPath).readAsBytesSync());
  final reference = (await codec.getNextFrame()).image;
  expect([reference.width, reference.height], [w, h]);
  final theirs = (await reference.toByteData())!.buffer.asUint8List();

  var differing = 0;
  var total = 0.0;
  final diff = Uint8List(ours.length);
  for (var i = 0; i < ours.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      final v = (ours[i + c] - theirs[i + c]).abs();
      if (v > d) d = v;
    }
    total += d;
    if (d > 40) differing++;
    diff[i] = 255;
    diff[i + 1] = diff[i + 2] = 255 - d;
    diff[i + 3] = 255;
  }
  final pixels = ours.length ~/ 4;
  final percent = differing * 100 / pixels;
  // ignore: avoid_print
  print('$name — pixels differing noticeably: ${percent.toStringAsFixed(3)}%, '
      'mean channel difference: ${(total / pixels).toStringAsFixed(3)}/255');

  final out = Platform.environment['FLOW_PARITY_OUT'];
  if (out != null) {
    Future<void> save(String file, Uint8List rgba) async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
      final img = (await (await descriptor.instantiateCodec()).getNextFrame()).image;
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$file').writeAsBytesSync(png!.buffer.asUint8List());
    }

    await save('$name-flutter.png', ours);
    await save('$name-diff.png', diff);
  }
  scene.dispose();
  controller.dispose();
  return percent;
}
