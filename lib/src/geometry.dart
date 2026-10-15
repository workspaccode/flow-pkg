// Port of the routing and Bézier code in src/core.js. Keep the two in sync:
// the same vertices drive the editor, SVG, PNG, Lottie and Flutter.
import 'dart:math' as math;
import 'dart:ui';

import 'model.dart';

/// Rounds to 3 decimals exactly like `Math.round(v*1000)/1000`.
double rnd(double v) => (v * 1000 + .5).floorToDouble() / 1000;

Offset portPoint(FlowNode n, FlowPort p) => switch (p) {
  FlowPort.left => Offset(n.x - n.w / 2, n.y),
  FlowPort.right => Offset(n.x + n.w / 2, n.y),
  FlowPort.top => Offset(n.x, n.y - n.h / 2),
  FlowPort.bottom => Offset(n.x, n.y + n.h / 2),
  FlowPort.center => Offset(n.x, n.y),
};

/// core.js `edgePort`: a line's port point shifted along its side by [offset].
Offset edgePortPoint(FlowNode n, FlowPort p, double offset) {
  final q = portPoint(n, p);
  return switch (p) {
    FlowPort.left || FlowPort.right => Offset(q.dx, q.dy + offset),
    FlowPort.top || FlowPort.bottom => Offset(q.dx + offset, q.dy),
    FlowPort.center => q,
  };
}

Offset _direction(FlowPort p) => switch (p) {
  FlowPort.left => const Offset(-1, 0),
  FlowPort.right => const Offset(1, 0),
  FlowPort.top => const Offset(0, -1),
  FlowPort.bottom => const Offset(0, 1),
  FlowPort.center => Offset.zero,
};

List<Offset> _dedupe(List<Offset> pts) => [
  for (var i = 0; i < pts.length; i++)
    if (i == 0 || (pts[i] - pts[i - 1]).distance > .01) pts[i],
];

/// The corner points of a line, before rounding.
List<Offset> routePoints(FlowProject p, FlowEdge e) {
  final a = p.node(e.from), b = p.node(e.to);
  if (a == null || b == null) return const [];
  // An anchor pins an end to an exact point relative to the element's centre.
  final s = e.sourceAnchor != null ? Offset(a.x, a.y) + e.sourceAnchor! : edgePortPoint(a, e.sourcePort, e.sourceOffset);
  final t = e.targetAnchor != null ? Offset(b.x, b.y) + e.targetAnchor! : edgePortPoint(b, e.targetPort, e.targetOffset);
  if (!e.auto) return [s, ...e.waypoints, t];
  if (e.route != FlowRoute.orthogonal) return [s, t];
  final d1 = _direction(e.sourcePort), d2 = _direction(e.targetPort);
  final s1 = s + d1 * 30, t1 = t + d2 * 30;
  List<Offset> mid;
  if (d1.dx != 0 && d2.dx != 0) {
    final x = (s1.dx + t1.dx) / 2;
    mid = [Offset(x, s1.dy), Offset(x, t1.dy)];
  } else if (d1.dy != 0 && d2.dy != 0) {
    final y = (s1.dy + t1.dy) / 2;
    mid = [Offset(s1.dx, y), Offset(t1.dx, y)];
  } else {
    mid = d1.dy != 0 ? [Offset(s1.dx, t1.dy)] : [Offset(t1.dx, s1.dy)];
  }
  return _dedupe([s, s1, ...mid, t1, t]);
}

/// Cubic Bézier shape in Lottie form: vertices with in/out tangents.
class BezierShape {
  final List<Offset> v = [], i = [], o = [];

  int _push(Offset p) {
    v.add(Offset(rnd(p.dx), rnd(p.dy)));
    i.add(Offset.zero);
    o.add(Offset.zero);
    return v.length - 1;
  }

  /// SVG path data, byte-identical to core.js `pathData`.
  String toPathData() {
    if (v.isEmpty) return '';
    String pt(Offset p) => '${jsString(p.dx)} ${jsString(p.dy)}';
    final d = StringBuffer('M${pt(v[0])}');
    for (var j = 1; j < v.length; j++) {
      final a = v[j - 1], b = v[j], out = o[j - 1], inn = i[j];
      if (out != Offset.zero || inn != Offset.zero) {
        d.write('C${jsString(rnd(a.dx + out.dx))} ${jsString(rnd(a.dy + out.dy))} '
            '${jsString(rnd(b.dx + inn.dx))} ${jsString(rnd(b.dy + inn.dy))} ${pt(b)}');
      } else {
        d.write('L${pt(b)}');
      }
    }
    return d.toString();
  }

  /// The same curve as [toPathData], as a Flutter [Path].
  Path toPath() {
    final path = Path();
    if (v.isEmpty) return path;
    path.moveTo(v[0].dx, v[0].dy);
    for (var j = 1; j < v.length; j++) {
      final a = v[j - 1], b = v[j], out = o[j - 1], inn = i[j];
      if (out != Offset.zero || inn != Offset.zero) {
        path.cubicTo(
          rnd(a.dx + out.dx), rnd(a.dy + out.dy),
          rnd(b.dx + inn.dx), rnd(b.dy + inn.dy),
          b.dx, b.dy,
        );
      } else {
        path.lineTo(b.dx, b.dy);
      }
    }
    return path;
  }
}

/// Rounds each corner with [radius] using a cubic arc approximation.
BezierShape roundedRoute(List<Offset> pts, double radius) {
  final clean = _dedupe(pts);
  final sh = BezierShape();
  if (clean.isEmpty) return sh;
  sh._push(clean[0]);
  for (var j = 1; j < clean.length - 1; j++) {
    final a = clean[j - 1], b = clean[j], c = clean[j + 1];
    final l1 = (b - a).distance, l2 = (c - b).distance;
    final u = (b - a) / l1, v = (c - b) / l2;
    final dot = u.dx * v.dx + u.dy * v.dy;
    if (dot.abs() > .9999 || radius <= 0) {
      sh._push(b);
      continue;
    }
    final angle = math.acos(dot.clamp(-1.0, 1.0)), tangent = math.tan(angle / 2);
    final cut = math.min(radius * tangent, math.min(l1 / 2, l2 / 2));
    final k = (4 / 3) * math.tan(angle / 4) * (cut / tangent);
    final n1 = sh._push(b - u * cut), n2 = sh._push(b + v * cut);
    sh.o[n1] = Offset(rnd(u.dx * k), rnd(u.dy * k));
    sh.i[n2] = Offset(rnd(-v.dx * k), rnd(-v.dy * k));
  }
  if (clean.length > 1) sh._push(clean.last);
  return sh;
}

double _dist(Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}

Offset _rnd(Offset o) => Offset(rnd(o.dx), rnd(o.dy));

/// core.js `curve`: a smooth curve through [pts]. The ends leave/enter along the
/// port directions [d1]/[d2] (zero for center ports); interior points use
/// Catmull-Rom tangents.
BezierShape curvedRoute(List<Offset> pts, Offset d1, Offset d2) {
  final pt = _dedupe(pts), sh = BezierShape(), n = pt.length - 1;
  for (final q in pt) {
    sh._push(q);
  }
  if (n < 1) return sh;
  Offset sub(Offset a, Offset b, double f) => Offset((a.dx - b.dx) / f, (a.dy - b.dy) / f);
  Offset sc(Offset d, double k) => Offset(d.dx * k, d.dy * k);
  final on1 = d1 != Offset.zero, on2 = d2 != Offset.zero;
  Offset o0, i1;
  if (n == 1) {
    final k = math.max(30.0, _dist(pt[0], pt[1]) * .4);
    o0 = on1 ? sc(d1, k) : sub(pt[1], pt[0], 3);
    i1 = on2 ? sc(d2, k) : sub(pt[0], pt[1], 3);
  } else {
    o0 = on1 ? sc(d1, _dist(pt[0], pt[1]) / 3) : sub(pt[1], pt[0], 3);
    i1 = on2 ? sc(d2, _dist(pt[n - 1], pt[n]) / 3) : sub(pt[n - 1], pt[n], 3);
    for (var j = 1; j < n; j++) {
      final t = sub(pt[j + 1], pt[j - 1], 6);
      sh.o[j] = _rnd(t);
      sh.i[j] = Offset(rnd(-t.dx), rnd(-t.dy));
    }
  }
  sh.o[0] = _rnd(o0);
  sh.i[n] = _rnd(i1);
  return sh;
}

/// core.js `shape`: the drawn Bézier shape of a line, for its route mode.
BezierShape edgeShape(FlowProject p, FlowEdge e) {
  final pts = routePoints(p, e);
  return e.route == FlowRoute.curved
      ? curvedRoute(pts, _direction(e.sourcePort), _direction(e.targetPort))
      : roundedRoute(pts, e.radius);
}

/// core.js `trackDash`: the base track's dash pattern, or null for a solid track.
List<double>? trackDash(FlowEdge e) => switch (e.trackStyle) {
  TrackStyle.solid => null,
  TrackStyle.dashed => [rnd(e.trackWidth * 4), rnd(e.trackWidth * 3)],
  TrackStyle.dotted => [.001, rnd(e.trackWidth * 2.5)],
};

/// core.js `pulseDash`: lit length and gap of each pulse on a path of length [len].
(double dash, double gap) pulseDash(double len, FlowEdge e) {
  final period = len / e.pulses;
  return (period * e.pulseLength, period * (1 - e.pulseLength));
}
