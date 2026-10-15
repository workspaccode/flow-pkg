// Dashboard look: theme colours, badges, scene backgrounds, element tiles and the header.
// Mirrors src/core.js (theme, TONES, SCENES, rainDrops, tilePoints, header, weatherIcon).
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'model.dart';
import 'render.dart' show FlowTextStyle;

/// Badge / status colours: light background, light text, dark background, dark text.
const _tones = {
  'green': [Color(0xffe3f6ec), Color(0xff23845a), Color(0xff1b3b2e), Color(0xff72d7a7)],
  'blue': [Color(0xffe5efff), Color(0xff2f63d6), Color(0xff1c2c4f), Color(0xff8fb1ff)],
  'amber': [Color(0xfffff2dc), Color(0xffb26a12), Color(0xff3d2f17), Color(0xfff5c06d)],
  'red': [Color(0xffffe7e4), Color(0xffc4473a), Color(0xff43221f), Color(0xfff39a8f)],
  'gray': [Color(0xffeef1f5), Color(0xff5e6b7e), Color(0xff263246), Color(0xffa9b6c9)],
};

/// (background, text) for a tone in the project's theme.
(Color, Color) toneColors(String tone, bool dark) {
  final t = _tones[tone] ?? _tones['gray']!;
  return dark ? (t[2], t[3]) : (t[0], t[1]);
}

/// Theme colours for labels, leaders, gauges and tiles.
class FlowTheme {
  FlowTheme(FlowProject p) : dark = p.theme == 'dark';

  final bool dark;
  Color get name => dark ? const Color(0xffa9b6c9) : const Color(0xff566981);
  Color get status => dark ? const Color(0xff8e9bb0) : const Color(0xff8594a8);
  Color get leader => dark ? const Color(0xff5d6b82) : const Color(0xffa3afc0);
  Color get track => dark ? const Color(0xff2a3850) : const Color(0xffe3e8ef);
  Color get strong => dark ? const Color(0xfff2f5fa) : const Color(0xff1d2c44);

  /// The default dark value colour turns light on a dark theme.
  Color value(Color c) => dark && (c.toARGB32() & 0xffffff) == 0x293b55 ? const Color(0xfff2f5fa) : c;

  List<Color> get tile => dark
      ? const [Color(0xff1f2b40), Color(0xff18233a), Color(0xff121b2e)]
      : const [Color(0xfff4f6fa), Color(0xffdfe4ec), Color(0xffcfd6e0)];
}

Color socColor(double v) => v >= 50 ? const Color(0xff34b37a) : (v >= 20 ? const Color(0xffe9a23b) : const Color(0xffe0574a));

/// Sky gradients per theme (core.js SCENES / DARK_SCENES).
const _sceneSky = {
  'cloudy': [Color(0xffc3d1e2), Color(0xffeef2f7)],
  'day': [Color(0xffcfe0f5), Color(0xfff5f8fc)],
  'dusk': [Color(0xfff3c9b1), Color(0xfffbefe7)],
  'night': [Color(0xff0d1628), Color(0xff24324b)],
  'rain': [Color(0xff8f9db0), Color(0xffd6dce4)],
};
const _darkSceneSky = {
  'cloudy': [Color(0xff1b2638), Color(0xff334258)],
  'day': [Color(0xff16263f), Color(0xff2b3f5e)],
  'dusk': [Color(0xff271f36), Color(0xff47364f)],
  'night': [Color(0xff0d1628), Color(0xff24324b)],
  'rain': [Color(0xff162133), Color(0xff2c394f)],
};

/// Deterministic rain streaks `[x, y, length]`, computed with the same double arithmetic as JavaScript.
List<List<double>> rainDrops(FlowProject p) {
  var s = 7.0;
  double r() => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648;
  final n = (p.width * p.height / 9000).round();
  return [for (var i = 0; i < n; i++) [r() * p.width * 1.1, r() * p.height, 10 + r() * 14]];
}

/// Cloud puffs `[cx, cy, r]` for the cloudy scene (core.js `cloudPuffs`).
List<List<double>> cloudPuffs(FlowProject p) {
  var s = 11.0;
  double r() => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648;
  final n = math.max(3, (p.width / 260).round()), out = <List<double>>[];
  for (var c = 0; c < n; c++) {
    final cx = (c + .2 + r() * .6) * p.width / n, cy = p.height * (.14 + r() * .2), w = 50 + r() * 50;
    for (var k = 0; k < 6; k++) {
      final x = cx + (k - 2.5) * w * .32 + r() * 10, y = cy + (k.isOdd ? -.25 : .1) * w * .35;
      out.add([x, y, w * (.26 + r() * .14)]);
    }
  }
  return out;
}

/// Scene background (sky gradient, clouds, night stars, falling rain at [time] seconds).
void paintScene(Canvas canvas, FlowProject p, double time) {
  final sky = (p.theme == 'dark' ? _darkSceneSky : _sceneSky)[p.scene];
  if (sky == null) return;
  final rect = Rect.fromLTWH(0, 0, p.width, p.height);
  canvas.drawRect(
    rect,
    Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky).createShader(rect),
  );
  if (p.scene == 'cloudy') {
    // SVG group opacity: puffs merge into one layer before fading
    final dark = p.theme == 'dark';
    canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, dark ? .3 : .55));
    // feGaussianBlur stdDeviation 9
    final fill = Paint()
      ..color = dark ? const Color(0xff4a5a74) : const Color(0xffffffff)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    for (final c in cloudPuffs(p)) {
      canvas.drawCircle(Offset(c[0], c[1]), c[2], fill);
    }
    canvas.restore();
  }
  final drops = p.scene == 'night' || p.scene == 'rain' ? rainDrops(p) : const <List<double>>[];
  if (p.scene == 'night') {
    final star = Paint()..color = const Color.fromRGBO(255, 255, 255, .55);
    for (final d in drops.take(40)) {
      canvas.drawCircle(Offset(d[0] % p.width, d[1] * .45), d[2] > 20 ? 1.1 : .7, star);
    }
  }
  if (p.scene == 'rain') {
    final fall = p.height * .25, t = time % 1;
    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, .55)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (final d in drops) {
      for (final k in [0, 1]) {
        final y = ((d[1] + t * fall) % p.height) - k * p.height;
        canvas.drawLine(Offset(d[0], y), Offset(d[0] - d[2] * .25, y + d[2]), paint);
      }
    }
  }
}

bool sceneMoves(FlowProject p) => p.scene == 'rain';

/// The isometric platform under an element: top, left and right faces.
({List<Offset> top, List<Offset> left, List<Offset> right}) tilePoints(FlowNode n) {
  final tw = n.w * 1.18, q = tw / 4, th = math.max(3.0, tw * .045), cx = n.x, cy = n.y + n.h / 2 - q - th;
  return (
    top: [Offset(cx - tw / 2, cy), Offset(cx, cy - q), Offset(cx + tw / 2, cy), Offset(cx, cy + q)],
    left: [Offset(cx - tw / 2, cy), Offset(cx, cy + q), Offset(cx, cy + q + th), Offset(cx - tw / 2, cy + th)],
    right: [Offset(cx, cy + q), Offset(cx + tw / 2, cy), Offset(cx + tw / 2, cy + th), Offset(cx, cy + q + th)],
  );
}

void paintTile(Canvas canvas, FlowNode n, FlowTheme t) {
  final pts = tilePoints(n), c = t.tile;
  Path poly(List<Offset> o) => Path()..addPolygon(o, true);
  canvas.drawPath(poly(pts.left), Paint()..color = c[1]);
  canvas.drawPath(poly(pts.right), Paint()..color = c[2]);
  canvas.drawPath(poly(pts.top), Paint()..color = c[0]);
  canvas.drawPath(
    poly(pts.top),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = t.dark ? const Color(0xff2c3a54) : const Color(0xffe6ebf2),
  );
}

TextPainter flowText(String s, double size, FontWeight weight, Color color, FlowTextStyle style) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      package: style.package,
      fontSize: size,
      fontWeight: weight,
      color: color,
    ),
  ),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
)..layout();

/// Paints [tp] with its alphabetic baseline at [baseline].
void paintAtBaseline(Canvas canvas, TextPainter tp, double x, double baseline) =>
    tp.paint(canvas, Offset(x, baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));

void _weatherIcon(Canvas canvas, String kind, Offset at, bool dark) {
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (kind == 'sun') {
    const c = Color(0xfff5b638);
    canvas.drawCircle(Offset.zero, 5, Paint()..color = c);
    final ray = Paint()
      ..color = c
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [
      (Offset(0, -11), Offset(0, -7)),
      (Offset(0, 7), Offset(0, 11)),
      (Offset(-11, 0), Offset(-7, 0)),
      (Offset(7, 0), Offset(11, 0)),
      (Offset(-7.8, -7.8), Offset(-5, -5)),
      (Offset(5, 5), Offset(7.8, 7.8)),
      (Offset(-7.8, 7.8), Offset(-5, 5)),
      (Offset(5, -5), Offset(7.8, -7.8)),
    ]) {
      canvas.drawLine(a, b, ray);
    }
  } else if (kind == 'night') {
    // M3-9 a9 9 0 1 0 6 15 a7 7 0 0 1 -6 -15 z
    final moon = Path()
      ..moveTo(3, -9)
      ..arcToPoint(const Offset(9, 6), radius: const Radius.circular(9), largeArc: true, clockwise: false)
      ..arcToPoint(const Offset(3, -9), radius: const Radius.circular(7), clockwise: true)
      ..close();
    canvas.drawPath(moon, Paint()..color = const Color(0xfff3d27a));
  } else {
    // M-9 5h17 a5 5 0 0 0 0-10 a7 7 0 0 0 -13-1 a5 5 0 0 0 -4 11z
    final cloud = Path()
      ..moveTo(-9, 5)
      ..lineTo(8, 5)
      ..arcToPoint(const Offset(8, -5), radius: const Radius.circular(5), clockwise: false)
      ..arcToPoint(const Offset(-5, -6), radius: const Radius.circular(7), clockwise: false)
      ..arcToPoint(const Offset(-9, 5), radius: const Radius.circular(5), clockwise: false)
      ..close();
    canvas.drawPath(cloud, Paint()..color = dark ? const Color(0xff9fb0c8) : const Color(0xffb8c4d4));
    if (kind == 'rain') {
      final drop = Paint()
        ..color = const Color(0xff5f9ad8)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (final dx in [-5.0, 0.0, 5.0]) {
        canvas.drawLine(Offset(dx, 8), Offset(dx - 1.5, 12), drop);
      }
    }
  }
  canvas.restore();
}

/// The top bar: title + status pill on the left, weather + temperature on the right, last update below.
void paintHeader(Canvas canvas, FlowProject p, FlowTheme t, FlowTextStyle style) {
  final h = p.header;
  if (h == null || h.isEmpty) return;
  final painters = <TextPainter>[];
  TextPainter text(String s, double size, FontWeight w, Color c) => flowText(s, size, w, c, style)..let(painters.add);
  var x = 20.0;
  if ((h.title ?? '').isNotEmpty) {
    final tp = text(h.title!, 19, FontWeight.w700, t.strong);
    paintAtBaseline(canvas, tp, x, 36);
    x += tp.width + 12;
  }
  if ((h.status ?? '').isNotEmpty) {
    final (bg, fg) = toneColors(h.statusTone, t.dark);
    final tp = text(h.status!, 12, FontWeight.w700, fg), w = tp.width + 30;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 19, w, 24), const Radius.circular(12)), Paint()..color = bg);
    canvas.drawCircle(Offset(x + 12, 31), 3.5, Paint()..color = fg);
    paintAtBaseline(canvas, tp, x + 21, 35.5);
  }
  if ((h.updated ?? '').isNotEmpty) paintAtBaseline(canvas, text(h.updated!, 11, FontWeight.w400, t.status), 20, 60);
  var rx = p.width - 20;
  if ((h.temperature ?? '').isNotEmpty) {
    final tp = text(h.temperature!, 16, FontWeight.w700, t.strong);
    paintAtBaseline(canvas, tp, rx - tp.width, 37);
    rx -= tp.width + 22;
  }
  if (const ['sun', 'cloud', 'rain', 'night'].contains(h.weather)) _weatherIcon(canvas, h.weather!, Offset(rx, 31), t.dark);
  for (final tp in painters) {
    tp.dispose();
  }
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
