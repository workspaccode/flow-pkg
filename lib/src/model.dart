import 'dart:convert';
import 'dart:ui' show Color, Offset;

/// Visibility of an element or a line, matching the editor's states.
///
/// * [active]: fully visible; lines animate.
/// * [inactive]: elements are faded (35%); lines show their track without motion.
/// * [hidden]: not drawn at all.
enum FlowState {
  active,
  inactive,
  hidden;

  static FlowState parse(Object? value) => switch (value) {
    'active' => FlowState.active,
    'inactive' => FlowState.inactive,
    'hidden' => FlowState.hidden,
    _ => throw const FormatException('Invalid state'),
  };
}

/// Where an element's label sits relative to its artwork.
enum LabelSide { bottom, top, left, right }

/// Connection point on an element.
enum FlowPort { top, bottom, left, right, center }

/// How a line travels between its ports.
///
/// * [orthogonal]: right angles with rounded corners (automatic routes avoid the elements' sides).
/// * [straight]: a direct segment (automatic) or a polyline through the waypoints, rounded by `radius`.
/// * [curved]: a smooth curve leaving and entering along the ports' sides, through any waypoints.
enum FlowRoute { orthogonal, straight, curved }

/// Pattern of a line's base track.
enum TrackStyle { solid, dashed, dotted }

/// An embedded image (PNG, JPEG, WebP or SVG data URI) keyed by element kind.
class FlowAsset {
  FlowAsset({required this.src, required this.width, required this.height});

  final String src;
  final double width;
  final double height;

  factory FlowAsset.fromJson(Map<String, dynamic> json) {
    final src = json['src'];
    final width = _finite(json['width'], 1, 10000);
    final height = _finite(json['height'], 1, 10000);
    if (src is! String ||
        width == null ||
        height == null ||
        !RegExp(r'^data:image/(png|jpeg|webp|svg\+xml);base64,', caseSensitive: false).hasMatch(src)) {
      throw const FormatException('Project assets must be embedded images');
    }
    return FlowAsset(src: src, width: width, height: height);
  }

  Map<String, dynamic> toJson() => {'src': src, 'width': width, 'height': height};
}

/// An element on the canvas (solar, battery, inverter, …). [x]/[y] is its center.
class FlowNode {
  FlowNode._(
    this._raw, {
    required this.id,
    required this.kind,
    required this.name,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.state,
    required this.value,
    required this.unit,
    required this.current,
    required this.currentUnit,
    required this.efficiency,
    required this.status,
    required this.showDetails,
    required this.labelSide,
    required this.labelGap,
    required this.fontSize,
    required this.color,
    required this.showLabel,
  });

  final Map<String, dynamic> _raw;
  final String id;
  String kind;
  String name;
  double x, y, w, h;
  FlowState state;

  /// Usually a number; a string (e.g. `'--'`) is shown as-is.
  Object? value;
  String unit;
  Object? current;
  String currentUnit;
  Object? efficiency;
  String status;
  bool showDetails;
  LabelSide labelSide;
  double labelGap;
  double fontSize;
  Color color;
  bool showLabel;

  factory FlowNode.fromJson(Map<String, dynamic> json) {
    final x = _finite(json['x'], -4096, 8192), y = _finite(json['y'], -4096, 8192);
    final w = _finite(json['w'], 1, 4096), h = _finite(json['h'], 1, 4096);
    final fontSize = _finite(json['fontSize'], 8, 60);
    final color = _color(json['color']);
    final side = LabelSide.values.asNameMap()[json['labelSide']];
    if (json['id'] is! String ||
        x == null ||
        y == null ||
        w == null ||
        h == null ||
        fontSize == null ||
        color == null ||
        side == null) {
      throw const FormatException('Invalid element data');
    }
    return FlowNode._(
      Map.of(json),
      id: json['id'] as String,
      kind: '${json['kind']}',
      name: _text(json['name']),
      x: x,
      y: y,
      w: w,
      h: h,
      state: _state(json['state'], 'Invalid element data'),
      value: json['value'],
      unit: _text(json['unit']),
      current: json['current'],
      currentUnit: _text(json['currentUnit']),
      efficiency: json['efficiency'],
      status: _text(json['status']),
      showDetails: json['showDetails'] == true,
      labelSide: side,
      // core.js: num(n.labelGap, 12)
      labelGap: _number(json['labelGap']) ?? 12,
      fontSize: fontSize,
      color: color,
      showLabel: json['showLabel'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    ..._raw,
    'id': id,
    'kind': kind,
    'name': name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'state': state.name,
    'value': value,
    'unit': unit,
    'current': current,
    'currentUnit': currentUnit,
    'efficiency': efficiency,
    'status': status,
    'showDetails': showDetails,
    'labelSide': labelSide.name,
    'labelGap': labelGap,
    'fontSize': fontSize,
    'color': _hex(color),
    if (!showLabel || _raw.containsKey('showLabel')) 'showLabel': showLabel,
  };
}

/// An animated line between two elements.
class FlowEdge {
  FlowEdge._(
    this._raw, {
    required this.id,
    required this.name,
    required this.from,
    required this.to,
    required this.sourcePort,
    required this.targetPort,
    required this.waypoints,
    required this.auto,
    required this.state,
    required this.color,
    required this.trackColor,
    required this.width,
    required this.trackWidth,
    required this.radius,
    required this.duration,
    required this.direction,
    required this.route,
    required this.sourceOffset,
    required this.targetOffset,
    required this.pulses,
    required this.pulseLength,
    required this.glow,
    required this.trackStyle,
    required this.onTop,
    this.sourceAnchor,
    this.targetAnchor,
  });

  final Map<String, dynamic> _raw;
  final String id;
  String name;
  String from, to;
  FlowPort sourcePort, targetPort;
  List<Offset> waypoints;

  /// When true the route is computed from the ports and [waypoints] are ignored.
  bool auto;
  FlowState state;

  /// Moving pulse color.
  Color color;

  /// Base line color.
  Color trackColor;
  double width, trackWidth, radius;

  /// Seconds for one full cycle of the pulse.
  double duration;

  /// `1` = from → to, `-1` = to → from.
  int direction;

  /// Route shape (`route`, default [FlowRoute.orthogonal]).
  FlowRoute route;

  /// Pixels the start / end point moves along its side (`y` for left/right ports,
  /// `x` for top/bottom, ignored for center). -2048…2048, default 0.
  double sourceOffset, targetOffset;

  /// Number of moving pulses, 1…12 (default 1).
  int pulses;

  /// Lit fraction of each pulse period, 0.02…0.9 (default 0.12).
  double pulseLength;

  /// Opacity of the wide glow behind the pulses, 0…1 (default 0.13; 0 draws none).
  double glow;

  /// Base track pattern (default [TrackStyle.solid]).
  TrackStyle trackStyle;

  /// Drawn above the elements instead of beneath them (default false), e.g. a
  /// cable running across a house from its roof panels to a wall inverter.
  bool onTop;

  /// Optional exact end points, as offsets from the element's centre. When set they
  /// replace the port point (`sourcePort` still gives the direction for automatic curves).
  Offset? sourceAnchor, targetAnchor;

  factory FlowEdge.fromJson(Map<String, dynamic> json) {
    const error = 'Invalid line data';
    final ports = FlowPort.values.asNameMap();
    final sourcePort = ports[json['sourcePort']], targetPort = ports[json['targetPort']];
    final color = _color(json['color']), trackColor = _color(json['trackColor']);
    final width = _finite(json['width'], .5, 30), trackWidth = _finite(json['trackWidth'], .5, 30);
    final radius = _finite(json['radius'], 0, 100), duration = _finite(json['duration'], .5, 20);
    final direction = json['direction'];
    final rawPoints = json['waypoints'];
    // Optional fields: missing means the default, present must be valid.
    T? opt<T>(String key, T def, T? Function(Object?) parse) => json.containsKey(key) ? parse(json[key]) : def;
    final route = opt('route', FlowRoute.orthogonal, (v) => FlowRoute.values.asNameMap()[v]);
    final trackStyle = opt('trackStyle', TrackStyle.solid, (v) => TrackStyle.values.asNameMap()[v]);
    final sourceOffset = opt('sourceOffset', 0.0, (v) => _finite(v, -2048, 2048));
    final targetOffset = opt('targetOffset', 0.0, (v) => _finite(v, -2048, 2048));
    final pulses = opt('pulses', 1, (v) => v is num && v == v.roundToDouble() && v >= 1 && v <= 12 ? v.toInt() : null);
    final pulseLength = opt('pulseLength', .12, (v) => _finite(v, .02, .9));
    final glow = opt('glow', .13, (v) => _finite(v, 0, 1));
    final onTop = opt('onTop', false, (v) => v is bool ? v : null);
    Offset? anchor(String key) {
      final v = json[key];
      if (v is! List || v.length != 2) throw const FormatException(error);
      final x = _finite(v[0], -4096, 4096), y = _finite(v[1], -4096, 4096);
      if (x == null || y == null) throw const FormatException(error);
      return Offset(x, y);
    }

    final sourceAnchor = json.containsKey('sourceAnchor') ? anchor('sourceAnchor') : null;
    final targetAnchor = json.containsKey('targetAnchor') ? anchor('targetAnchor') : null;
    if (json['id'] is! String ||
        json['from'] is! String ||
        json['to'] is! String ||
        sourcePort == null ||
        targetPort == null ||
        color == null ||
        trackColor == null ||
        width == null ||
        trackWidth == null ||
        radius == null ||
        duration == null ||
        (direction != 1 && direction != -1) ||
        rawPoints is! List ||
        rawPoints.length > 80 ||
        route == null ||
        trackStyle == null ||
        sourceOffset == null ||
        targetOffset == null ||
        pulses == null ||
        pulseLength == null ||
        glow == null ||
        onTop == null) {
      throw const FormatException(error);
    }
    final waypoints = <Offset>[];
    for (final q in rawPoints) {
      if (q is! List || q.length != 2) throw const FormatException(error);
      final px = _finite(q[0], -4096, 8192), py = _finite(q[1], -4096, 8192);
      if (px == null || py == null) throw const FormatException(error);
      waypoints.add(Offset(px, py));
    }
    return FlowEdge._(
      Map.of(json),
      id: json['id'] as String,
      name: _text(json['name'] ?? json['id']),
      from: json['from'] as String,
      to: json['to'] as String,
      sourcePort: sourcePort,
      targetPort: targetPort,
      waypoints: waypoints,
      auto: json['auto'] == true,
      state: _state(json['state'], error),
      color: color,
      trackColor: trackColor,
      width: width,
      trackWidth: trackWidth,
      radius: radius,
      duration: duration,
      direction: direction as int,
      route: route,
      sourceOffset: sourceOffset,
      targetOffset: targetOffset,
      pulses: pulses,
      pulseLength: pulseLength,
      glow: glow,
      trackStyle: trackStyle,
      onTop: onTop,
      sourceAnchor: sourceAnchor,
      targetAnchor: targetAnchor,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
    ..._raw,
    'id': id,
    'name': name,
    'from': from,
    'to': to,
    'sourcePort': sourcePort.name,
    'targetPort': targetPort.name,
    'waypoints': [
      for (final q in waypoints) [q.dx, q.dy],
    ],
    'auto': auto,
    'state': state.name,
    'color': _hex(color),
    'trackColor': _hex(trackColor),
    'width': width,
    'trackWidth': trackWidth,
    'radius': radius,
    'duration': duration,
    'direction': direction,
    'route': route.name,
    'sourceOffset': sourceOffset,
    'targetOffset': targetOffset,
    'pulses': pulses,
    'pulseLength': pulseLength,
    'glow': glow,
    'trackStyle': trackStyle.name,
    if (onTop || _raw.containsKey('onTop')) 'onTop': onTop,
    if (sourceAnchor case final a?) 'sourceAnchor': [a.dx, a.dy],
    if (targetAnchor case final a?) 'targetAnchor': [a.dx, a.dy],
    };
    // A cleared anchor must not survive from the original file.
    if (sourceAnchor == null) json.remove('sourceAnchor');
    if (targetAnchor == null) json.remove('targetAnchor');
    return json;
  }
}

/// A Flow Studio project — the `.flow.json` file saved or exported by the editor.
class FlowProject {
  FlowProject._(
    this._raw, {
    required this.title,
    required this.width,
    required this.height,
    required this.background,
    required this.nodes,
    required this.edges,
    required this.assets,
  });

  final Map<String, dynamic> _raw;
  String title;
  double width, height;
  Color background;
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  final Map<String, FlowAsset> assets;

  /// Parses and validates a project with the same rules as the editor.
  factory FlowProject.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'flow-studio' ||
        json['version'] != 1 ||
        json['nodes'] is! List ||
        json['edges'] is! List ||
        json['assets'] is! Map) {
      throw const FormatException(
        'Choose a Flow Studio project JSON. Lottie JSON is an export, not an editable project.',
      );
    }
    final rawNodes = json['nodes'] as List, rawEdges = json['edges'] as List;
    if (rawNodes.length > 100 || rawEdges.length > 200) {
      throw const FormatException('Project is too large (100 elements / 200 lines maximum).');
    }
    final width = _finite(json['width'], 100, 4096), height = _finite(json['height'], 100, 4096);
    final background = _color(json['background']);
    if (width == null || height == null || background == null) {
      throw const FormatException('Invalid canvas settings');
    }
    final nodes = <FlowNode>[];
    final nodeIds = <String>{};
    for (final raw in rawNodes) {
      if (raw is! Map) throw const FormatException('Invalid element data');
      final node = FlowNode.fromJson(raw.cast<String, dynamic>());
      if (!nodeIds.add(node.id)) throw const FormatException('Invalid element data');
      nodes.add(node);
    }
    final edges = <FlowEdge>[];
    final edgeIds = <String>{};
    for (final raw in rawEdges) {
      if (raw is! Map) throw const FormatException('Invalid line data');
      final edge = FlowEdge.fromJson(raw.cast<String, dynamic>());
      if (!edgeIds.add(edge.id) || !nodeIds.contains(edge.from) || !nodeIds.contains(edge.to)) {
        throw const FormatException('Invalid line data');
      }
      edges.add(edge);
    }
    final assets = <String, FlowAsset>{};
    for (final MapEntry(:key, :value) in (json['assets'] as Map).entries) {
      if (value is! Map) throw const FormatException('Project assets must be embedded images');
      assets['$key'] = FlowAsset.fromJson(value.cast<String, dynamic>());
    }
    return FlowProject._(
      Map.of(json),
      title: _text(json['title']),
      width: width,
      height: height,
      background: background,
      nodes: nodes,
      edges: edges,
      assets: assets,
    );
  }

  factory FlowProject.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Choose a Flow Studio project JSON.');
    return FlowProject.fromJson(decoded.cast<String, dynamic>());
  }

  FlowNode? node(String id) => _find(nodes, (n) => n.id == id);
  FlowEdge? edge(String id) => _find(edges, (e) => e.id == id);

  Map<String, dynamic> toJson() => {
    ..._raw,
    'title': title,
    'width': width,
    'height': height,
    'background': _hex(background),
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
    'assets': {for (final MapEntry(:key, :value) in assets.entries) key: value.toJson()},
  };

  FlowProject copy() => FlowProject.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

/// Formats a value the way JavaScript template strings do (`3` not `3.0`).
String jsString(Object? value) {
  if (value is double) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
    if (value == value.truncateToDouble() && value.abs() < 1e21) return value.toInt().toString();
    return value.toString();
  }
  if (value == null) return 'null';
  return '$value';
}

T? _find<T>(List<T> list, bool Function(T) test) {
  for (final item in list) {
    if (test(item)) return item;
  }
  return null;
}

double? _number(Object? v) {
  final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
  return n != null && n.isFinite ? n : null;
}

double? _finite(Object? v, double min, double max) {
  if (v is! num) return null;
  final n = v.toDouble();
  return n.isFinite && n >= min && n <= max ? n : null;
}

String _text(Object? v) => v == null ? '' : jsString(v);

FlowState _state(Object? v, String error) {
  try {
    return FlowState.parse(v);
  } on FormatException {
    throw FormatException(error);
  }
}

final _hexColor = RegExp(r'^#[\da-f]{6}$', caseSensitive: false);

Color? _color(Object? v) {
  if (v is! String || !_hexColor.hasMatch(v)) return null;
  return Color(0xff000000 | int.parse(v.substring(1), radix: 16));
}

/// Parses `#rrggbb`.
Color parseHexColor(String hex) => _color(hex) ?? (throw FormatException('Invalid color: $hex'));

String _hex(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
