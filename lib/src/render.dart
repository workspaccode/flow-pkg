import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class _Line {
  _Line(this.text, this.size, this.weight, this.color);
  final String text;
  final double size;
  final FontWeight weight;
  final Color color;
}

/// core.js `labelLines`.
List<_Line> _labelLines(FlowNode n) {
  if (!n.showLabel) return const [];
  final s = n.fontSize;
  return [
    _Line(n.name, s, FontWeight.w600, const Color(0xff566981)),
    _Line('${jsString(n.value)} ${n.unit}'.trim(), s + 6, FontWeight.w700, n.color),
    if (n.status.isNotEmpty) _Line(n.status, s - 3, FontWeight.w400, const Color(0xff8594a8)),
    if (n.showDetails)
      _Line(
        '${jsString(n.current)} ${n.currentUnit}  ·  ${jsString(n.efficiency)}%',
        s - 4,
        FontWeight.w400,
        const Color(0xff8594a8),
      ),
  ];
}

// SVG <text> collapses runs of whitespace and trims the ends.
final _spaces = RegExp(r'[ \t\r\n]+');

class _LabelText {
  _LabelText(this.painter, this.origin);
  final TextPainter painter;
  final Offset origin;
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
  _NodeDraw(this.node, this.box, this.image, this.labels, this.labelRect);
  final FlowNode node;
  final Rect box;
  final FlowImage? image;
  final List<_LabelText> labels;
  final Rect? labelRect;
}

/// Everything needed to paint a project, laid out once per change.
class FlowScene {
  FlowScene._(this.project, this._edges, this._nodes);

  final FlowProject project;
  final List<_EdgeDraw> _edges;
  final List<_NodeDraw> _nodes;

  bool get hasMotion => _edges.any((e) => e.edge.state == FlowState.active);

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
      final (labels, rect) = _layoutLabels(n, text);
      nodes.add(_NodeDraw(n, box, p.assets.containsKey(n.kind) ? images[n.kind] : null, labels, rect));
    }
    return FlowScene._(p, edges, nodes);
  }

  /// core.js `labelBox` + `labels`.
  static (List<_LabelText>, Rect?) _layoutLabels(FlowNode n, FlowTextStyle text) {
    final lines = _labelLines(n);
    if (lines.isEmpty) return (const [], null);
    TextPainter make(String s, _Line l) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: text.fontFamily,
          fontFamilyFallback: text.fontFamilyFallback,
          package: text.package,
          fontSize: l.size,
          fontWeight: l.weight,
          color: l.color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();

    // The editor measures the raw string (+4px) to place left/right labels.
    var width = 40.0;
    for (final l in lines) {
      final m = make(l.text, l);
      width = math.max(width, m.width + 4);
      m.dispose();
    }
    final height = lines.fold<double>(0, (s, l) => s + l.size + 9) - 2;
    final side = n.labelSide;
    var x = n.x - width / 2, y = n.y + n.h / 2 + n.labelGap;
    if (side == LabelSide.right) {
      x = n.x + n.w / 2 + n.labelGap;
      y = n.y - height / 2;
    }
    if (side == LabelSide.left) {
      x = n.x - n.w / 2 - n.labelGap - width;
      y = n.y - height / 2;
    }
    if (side == LabelSide.top) y = n.y - n.h / 2 - n.labelGap - height;

    final start = side == LabelSide.left || side == LabelSide.right;
    final out = <_LabelText>[];
    var baseline = y;
    for (final l in lines) {
      baseline += l.size;
      final tp = make(l.text.replaceAll(_spaces, ' ').trim(), l);
      final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final left = start ? x : n.x - tp.width / 2;
      out.add(_LabelText(tp, Offset(left, baseline - ascent)));
      baseline += 9;
    }
    return (out, Rect.fromLTWH(x, y, width, height));
  }

  /// The topmost visible element at [point] (canvas coordinates), including its label.
  FlowNode? nodeAt(Offset point) {
    for (final d in _nodes.reversed) {
      if (d.box.contains(point) || (d.labelRect?.contains(point) ?? false)) return d.node;
    }
    return null;
  }

  /// Paints at canvas scale (1 unit = 1 project pixel) for animation [time] in seconds.
  void paint(Canvas canvas, {required double time, bool transparent = false}) {
    final p = project;
    canvas.clipRect(Rect.fromLTWH(0, 0, p.width, p.height));
    if (!transparent) canvas.drawRect(Rect.fromLTWH(0, 0, p.width, p.height), Paint()..color = p.background);

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
      if (d.image case final image?) {
        image.paint(canvas, d.box);
      } else if (!project.assets.containsKey(n.kind)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(d.box, const Radius.circular(8)),
          Paint()..color = const Color(0xffe5ebf5),
        );
      }
      for (final l in d.labels) {
        l.painter.paint(canvas, l.origin);
      }
      if (faded) canvas.restore();
    }

    for (final d in _edges) {
      if (d.edge.onTop) paintEdge(d);
    }
  }

  void dispose() {
    for (final n in _nodes) {
      for (final l in n.labels) {
        l.painter.dispose();
      }
    }
  }
}
