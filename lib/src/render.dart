import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dashboard.dart';
import 'geometry.dart';
import 'model.dart';

/// A decoded element artwork: a raster image or a vector picture.
class FlowImage {
  FlowImage._(this.size, {this.image, this.picture});

  final Size size;
  final ui.Image? image;
  final ui.Picture? picture;

  static Future<FlowImage> decode(FlowAsset asset) async {
    final data = UriData.parse(asset.src);
    final bytes = data.contentAsBytes();
    if (data.mimeType == 'image/svg+xml') {
      final info = await vg.loadPicture(SvgStringLoader(utf8.decode(bytes)), null);
      return FlowImage._(info.size, picture: info.picture);
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    return FlowImage._(Size(image.width.toDouble(), image.height.toDouble()), image: image);
  }

  /// Draws into [box] like `preserveAspectRatio="xMidYMid meet"`.
  void paint(Canvas canvas, Rect box) {
    if (size.isEmpty) return;
    final scale = math.min(box.width / size.width, box.height / size.height);
    final dest = Rect.fromCenter(center: box.center, width: size.width * scale, height: size.height * scale);
    if (image case final image?) {
      canvas.drawImageRect(
        image,
        Offset.zero & size,
        dest,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
    } else if (picture case final picture?) {
      canvas
        ..save()
        ..clipRect(dest)
        ..translate(dest.left, dest.top)
        ..scale(scale)
        ..drawPicture(picture)
        ..restore();
    }
  }

  void dispose() {
    image?.dispose();
    picture?.dispose();
  }
}

/// Typography used for element labels. The editor and its exports use Arial.
class FlowTextStyle {
  const FlowTextStyle({
    this.fontFamily = 'Arial',
    this.fontFamilyFallback = const ['Helvetica', 'Arimo', 'Liberation Sans', 'Roboto', 'sans-serif'],
    this.package,
  });

  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final String? package;

  @override
  bool operator ==(Object other) =>
      other is FlowTextStyle &&
      other.fontFamily == fontFamily &&
      other.package == package &&
      _listEquals(other.fontFamilyFallback, fontFamilyFallback);

  @override
  int get hashCode => Object.hash(fontFamily, package, Object.hashAll(fontFamilyFallback ?? const []));
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum _Kind { text, badge, soc }

/// One label line (core.js `labelLines`): text, a status badge or a battery gauge.
class _Line {
  _Line.text(this.text, this.size, this.weight, this.color) : kind = _Kind.text, h = size, bg = null, value = 0;
  _Line.badge(this.text, this.size, this.bg, this.color)
    : kind = _Kind.badge,
      weight = FontWeight.w600,
      h = size + 9,
      value = 0;
  _Line.soc(this.value, this.color, this.bg) : kind = _Kind.soc, text = '', size = 0, weight = FontWeight.w400, h = 6;
  final _Kind kind;
  final String text;
  final double size, h, value;
  final FontWeight weight;
  final Color color;
  final Color? bg;
}

List<_Line> _labelLines(FlowNode n, FlowTheme t) {
  if (!n.showLabel) return const [];
  final s = n.fontSize, soc = n.soc?.clamp(0, 100).toDouble();
  final (bg, fg) = toneColors(n.badgeTone, t.dark);
  return [
    _Line.text(soc == null ? n.name : '${n.name}  ${soc.round()}%', s, FontWeight.w600, t.name),
    _Line.text('${jsString(n.value)} ${n.unit}'.trim(), s + 6, FontWeight.w700, t.value(n.color)),
    if (soc != null) _Line.soc(soc, socColor(soc), t.track),
    if (n.status.isNotEmpty) _Line.text(n.status, s - 3, FontWeight.w400, t.status),
    if (n.showDetails)
      _Line.text('${jsString(n.current)} ${n.currentUnit}  ·  ${jsString(n.efficiency)}%', s - 4, FontWeight.w400, t.status),
    if ((n.badge ?? '').isNotEmpty) _Line.badge(n.badge!, math.max(9, s - 4), bg, fg),
  ];
}

// SVG <text> collapses runs of whitespace and trims the ends.
final _spaces = RegExp(r'[ \t\r\n]+');

/// A laid-out label: positioned text painters, badge/gauge shapes and an optional callout leader.
class _Label {
  final texts = <(TextPainter, Offset)>[];
  final shapes = <(RRect, Color)>[];
  List<Offset>? leader;
  Rect? rect;
  Color leaderColor = const Color(0xffa3afc0);

  void paint(Canvas canvas) {
    if (leader case final pts?) {
      final path = Path()..addPolygon(pts, false);
      final metric = path.computeMetrics().firstOrNull;
      canvas.drawPath(
        _dashed(path, metric, const [2, 3]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = leaderColor,
      );
      canvas.drawCircle(pts.last, 2.6, Paint()..color = leaderColor);
    }
    for (final (r, c) in shapes) {
      canvas.drawRRect(r, Paint()..color = c);
    }
    for (final (tp, at) in texts) {
      tp.paint(canvas, at);
    }
  }

  void dispose() {
    for (final (tp, _) in texts) {
      tp.dispose();
    }
  }
}

class _EdgeDraw {
  _EdgeDraw(this.edge, this.path, this.metric, this.track);
  final FlowEdge edge;
  final Path path;
  final ui.PathMetric? metric;

  /// The base track: [path] itself, or its dashes for dashed/dotted tracks.
  final Path track;
}

/// SVG `stroke-dasharray` semantics: the pattern starts at distance 0 with offset 0.
Path _dashed(Path path, ui.PathMetric? metric, List<double>? pattern) {
  if (pattern == null || metric == null) return path;
  final out = Path(), period = pattern[0] + pattern[1];
  if (period <= 0) return path;
  for (var at = 0.0; at < metric.length; at += period) {
    out.addPath(metric.extractPath(at, math.min(at + pattern[0], metric.length)), Offset.zero);
  }
  return out;
}

class _NodeDraw {
  _NodeDraw(this.node, this.box, this.image, this.lit, this.label);
  final FlowNode node;
  final Rect box;
  final FlowImage? image, lit;
  final _Label label;
}

/// Everything needed to paint a project, laid out once per change.
class FlowScene {
  FlowScene._(this.project, this._edges, this._nodes, this._text);

  final FlowTextStyle _text;

  final FlowProject project;
  final List<_EdgeDraw> _edges;
  final List<_NodeDraw> _nodes;

  bool get hasMotion => _edges.any((e) => e.edge.state == FlowState.active) || sceneMoves(project);

  static FlowScene build(FlowProject p, Map<String, FlowImage> images, FlowTextStyle text) {
    final edges = <_EdgeDraw>[];
    for (final e in p.edges) {
      if (e.state == FlowState.hidden) continue;
      final sh = edgeShape(p, e);
      if (sh.v.isEmpty) continue;
      final path = sh.toPath();
      final metrics = path.computeMetrics().toList();
      final metric = metrics.isEmpty ? null : metrics.first;
      edges.add(_EdgeDraw(e, path, metric, _dashed(path, metric, trackDash(e))));
    }
    final nodes = <_NodeDraw>[];
    for (final n in p.nodes) {
      if (n.state == FlowState.hidden) continue;
      final box = Rect.fromCenter(center: Offset(n.x, n.y), width: n.w, height: n.h);
      final has = p.assets.containsKey(n.kind);
      nodes.add(
        _NodeDraw(
          n,
          box,
          has ? images[n.kind] : null,
          has && n.lit ? images['${n.kind}#lit'] : null,
          _layoutLabel(n, FlowTheme(p), text),
        ),
      );
    }
    return FlowScene._(p, edges, nodes, text);
  }

  /// core.js `labelBox` + `labels`.
  static _Label _layoutLabel(FlowNode n, FlowTheme t, FlowTextStyle text) {
    final out = _Label()..leaderColor = t.leader;
    final lines = _labelLines(n, t);
    if (lines.isEmpty) return out;
    TextPainter make(String s, _Line l) => flowText(s, l.size, l.weight, l.color, text);
    double measure(_Line l) {
      if (l.kind == _Kind.soc) return 64;
      final m = make(l.text, l), w = m.width;
      m.dispose();
      return l.kind == _Kind.badge ? w + 18 : w + 4;
    }

    final widths = [for (final l in lines) measure(l)];
    final width = math.max(40.0, widths.reduce(math.max));
    final height = lines.fold<double>(0, (s, l) => s + l.h + 9) - 2;
    late double x, y;
    var middle = false;
    if (n.callout case final c?) {
      x = n.x + c.dx;
      y = n.y + c.dy;
      final tx = n.x + (n.calloutTarget?.dx ?? 0), ty = n.y + (n.calloutTarget?.dy ?? 0);
      final lx = tx > x + width ? x + width + 7 : x - 7, below = ty > y + height / 2;
      final start = Offset(lx, below ? y + 2 : y + height - 2);
      out.leader = (tx - lx).abs() < 1 ? [start, Offset(tx, ty)] : [start, Offset(lx, ty), Offset(tx, ty)];
    } else {
      final side = n.labelSide;
      x = n.x - width / 2;
      y = n.y + n.h / 2 + n.labelGap;
      if (side == LabelSide.right) {
        x = n.x + n.w / 2 + n.labelGap;
        y = n.y - height / 2;
      }
      if (side == LabelSide.left) {
        x = n.x - n.w / 2 - n.labelGap - width;
        y = n.y - height / 2;
      }
      if (side == LabelSide.top) y = n.y - n.h / 2 - n.labelGap - height;
      middle = side == LabelSide.top || side == LabelSide.bottom;
    }
    final ax = middle ? n.x : x;
    var top = y;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      switch (l.kind) {
        case _Kind.text:
          final tp = make(l.text.replaceAll(_spaces, ' ').trim(), l);
          final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          out.texts.add((tp, Offset(middle ? ax - tp.width / 2 : ax, top + l.size - ascent)));
        case _Kind.soc:
          final x0 = middle ? ax - 32 : ax;
          out.shapes.add((RRect.fromRectAndRadius(Rect.fromLTWH(x0, top, 64, l.h), Radius.circular(l.h / 2)), l.bg!));
          final fill = math.max(l.h, 64 * l.value / 100);
          out.shapes.add((RRect.fromRectAndRadius(Rect.fromLTWH(x0, top, fill, l.h), Radius.circular(l.h / 2)), l.color));
        case _Kind.badge:
          final w = widths[i], x0 = middle ? ax - w / 2 : ax;
          out.shapes.add((RRect.fromRectAndRadius(Rect.fromLTWH(x0, top, w, l.h), Radius.circular(l.h / 2)), l.bg!));
          final tp = make(l.text, l);
          final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          out.texts.add((tp, Offset(x0 + w / 2 - tp.width / 2, top + l.h / 2 + l.size * .36 - ascent)));
      }
      top += l.h + 9;
    }
    out.rect = Rect.fromLTWH(x, y, width, height);
    return out;
  }

  /// The topmost visible element at [point] (canvas coordinates), including its label.
  FlowNode? nodeAt(Offset point) {
    for (final d in _nodes.reversed) {
      if (d.box.contains(point) || (d.label.rect?.contains(point) ?? false)) return d.node;
    }
    return null;
  }

  /// Paints at canvas scale (1 unit = 1 project pixel) for animation [time] in seconds.
  void paint(Canvas canvas, {required double time, bool transparent = false}) {
    final p = project;
    canvas.clipRect(Rect.fromLTWH(0, 0, p.width, p.height));
    if (!transparent) {
      canvas.drawRect(Rect.fromLTWH(0, 0, p.width, p.height), Paint()..color = p.background);
      paintScene(canvas, p, time);
    }
    final theme = FlowTheme(p);

    void paintEdge(_EdgeDraw d) {
      final e = d.edge;
      Paint stroke(Color c, double opacity, double width) => Paint()
        ..style = PaintingStyle.stroke
        ..color = c.withValues(alpha: opacity)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(d.track, stroke(e.trackColor, e.state == FlowState.inactive ? .3 : .85, e.trackWidth));
      final metric = d.metric;
      if (e.state != FlowState.active || metric == null) return;

      // stroke-dasharray: dash gap (see pulseDash) with
      // stroke-dashoffset: -len*direction*(time % duration)/duration
      final len = math.max(1.0, metric.length);
      final phase = (time % e.duration) / e.duration;
      final (dash, _) = pulseDash(len, e);
      final period = len / e.pulses;
      final pulse = Path();
      void add(double a, double b) {
        if (b > a) pulse.addPath(metric.extractPath(a, math.min(b, metric.length)), Offset.zero);
      }

      for (var k = 0; k < e.pulses; k++) {
        var start = (len * e.direction * phase + k * period) % len;
        if (start < 0) start += len;
        add(start, start + dash);
        if (start + dash > len) add(0, start + dash - len);
      }
      if (e.glow > 0) canvas.drawPath(pulse, stroke(e.color, e.glow, e.width * 2.8));
      canvas.drawPath(pulse, stroke(e.color, .95, e.width));
    }

    // Lines marked onTop are painted after the elements.
    for (final d in _edges) {
      if (!d.edge.onTop) paintEdge(d);
    }

    for (final d in _nodes) {
      final n = d.node;
      final faded = n.state == FlowState.inactive;
      if (faded) canvas.saveLayer(null, Paint()..color = const Color.fromRGBO(0, 0, 0, .35));
      if (n.tile) paintTile(canvas, n, theme);
      if (d.image case final image?) {
        image.paint(canvas, d.box);
        d.lit?.paint(canvas, d.box);
      } else if (!project.assets.containsKey(n.kind)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(d.box, const Radius.circular(8)),
          Paint()..color = const Color(0xffe5ebf5),
        );
      }
      d.label.paint(canvas);
      if (faded) canvas.restore();
    }

    for (final d in _edges) {
      if (d.edge.onTop) paintEdge(d);
    }
    paintHeader(canvas, p, theme, _text);
  }

  void dispose() {
    for (final n in _nodes) {
      n.label.dispose();
    }
  }
}
