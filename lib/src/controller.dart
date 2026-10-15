import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'model.dart';
import 'render.dart';

/// Loads a Flow Studio project and updates its data, states and motion.
///
/// The methods mirror `energyFlow` in the editor's HTML export. Calls made
/// before the project finishes loading are applied once it is ready.
class FlowController extends ChangeNotifier {
  FlowController();

  /// Starts loading [json] (a decoded `.flow.json`).
  FlowController.fromJson(Map<String, dynamic> json) {
    unawaited(_guard(loadJson(json)));
  }

  /// Starts loading a `.flow.json` asset declared in `pubspec.yaml`.
  FlowController.asset(String path, {AssetBundle? bundle}) {
    unawaited(_guard(loadAsset(path, bundle: bundle)));
  }

  FlowProject? _project;
  Map<String, FlowImage> _images = {};
  final List<void Function()> _pending = [];
  Completer<void> _ready = Completer<void>();
  Object? _error;
  bool _playing = true;
  bool _disposed = false;
  int _generation = 0;

  /// The current project, or `null` while loading.
  FlowProject? get project => _project;

  /// Decoded artwork keyed by element kind.
  Map<String, FlowImage> get images => _images;

  bool get isReady => _project != null;

  /// Completes when the first project and its artwork are loaded.
  Future<void> get ready => _ready.future;

  /// The last loading error, if any.
  Object? get error => _error;

  bool get isPlaying => _playing;

  Future<void> loadAsset(String path, {AssetBundle? bundle}) async =>
      loadJsonString(await (bundle ?? rootBundle).loadString(path, cache: false));

  Future<void> loadJsonString(String source) => setProject(FlowProject.fromJsonString(source));

  Future<void> loadJson(Map<String, dynamic> json) => setProject(FlowProject.fromJson(json));

  /// Replaces the whole project. The project is copied; edit it through this controller.
  Future<void> setProject(FlowProject project) async {
    final generation = ++_generation;
    final next = project.copy();
    final images = <String, FlowImage>{};
    try {
      for (final MapEntry(:key, :value) in next.assets.entries) {
        if (!next.nodes.any((n) => n.kind == key)) continue;
        images[key] = await FlowImage.decode(value);
        // the lights-on overlay is decoded alongside its artwork
        if (value.lit case final lit?) {
          images['$key#lit'] = await FlowImage.decode(FlowAsset(src: lit, width: value.width, height: value.height));
        }
      }
    } catch (e) {
      for (final image in images.values) {
        image.dispose();
      }
      _error = e;
      if (!_disposed) notifyListeners();
      rethrow;
    }
    if (_disposed || generation != _generation) {
      for (final image in images.values) {
        image.dispose();
      }
      return;
    }
    final old = _images;
    _project = next;
    _images = images;
    _error = null;
    final pending = List.of(_pending);
    _pending.clear();
    for (final apply in pending) {
      try {
        apply();
      } catch (e, s) {
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'flow_studio'));
      }
    }
    if (!_ready.isCompleted) _ready.complete();
    notifyListeners();
    // Old pictures may still be referenced by the frame being drawn.
    scheduleMicrotask(() {
      for (final image in old.values) {
        image.dispose();
      }
    });
  }

  /// A copy of the current project as `.flow.json` data.
  Map<String, dynamic> toJson() => _require().toJson();

  void setNodeState(String id, FlowState state) => _apply(() => _node(id).state = state);

  void setFlowState(String id, FlowState state) => _apply(() => _edge(id).state = state);

  /// Updates the label data of an element. `null` arguments are left unchanged.
  ///
  /// [value], [current] and [efficiency] are usually numbers; strings are shown as-is.
  ///
  /// Dashboard extras: [soc] (battery level 0–100), [badge] with [badgeTone] (green, blue, amber,
  /// red, gray) and [lit] (lights-on overlay). Pass `clearSoc` / an empty [badge] to remove them.
  void setNodeData(
    String id, {
    String? name,
    Object? value,
    String? unit,
    Object? current,
    String? currentUnit,
    Object? efficiency,
    String? status,
    bool? showDetails,
    double? soc,
    bool clearSoc = false,
    String? badge,
    String? badgeTone,
    bool? lit,
  }) => _apply(() {
    final n = _node(id);
    if (name != null) n.name = name;
    if (value != null) n.value = value;
    if (unit != null) n.unit = unit;
    if (current != null) n.current = current;
    if (currentUnit != null) n.currentUnit = currentUnit;
    if (efficiency != null) n.efficiency = efficiency;
    if (status != null) n.status = status;
    if (showDetails != null) n.showDetails = showDetails;
    if (soc != null) n.soc = soc.clamp(0, 100).toDouble();
    if (clearSoc) n.soc = null;
    if (badge != null) n.badge = badge.isEmpty ? null : badge;
    if (badgeTone != null) {
      if (!badgeTones.contains(badgeTone)) throw ArgumentError.value(badgeTone, 'badgeTone');
      n.badgeTone = badgeTone;
    }
    if (lit != null) n.lit = lit;
  });

  /// Recolours a line, e.g. green while charging and orange while importing.
  void setFlowColor(String id, Color color, {Color? trackColor}) => _apply(() {
    final e = _edge(id);
    e.color = color;
    if (trackColor != null) e.trackColor = trackColor;
  });

  /// Updates the dashboard header; `null` arguments are left unchanged, empty strings clear a field.
  void setHeader({String? title, String? status, String? statusTone, String? weather, String? temperature, String? updated}) {
    if (statusTone != null && !badgeTones.contains(statusTone)) throw ArgumentError.value(statusTone, 'statusTone');
    if (weather != null && !const ['', 'sun', 'cloud', 'rain', 'night'].contains(weather)) {
      throw ArgumentError.value(weather, 'weather');
    }
    _apply(() {
      final h = _require().header ??= FlowHeader();
      String? keep(String? next, String? old) => next == null ? old : (next.isEmpty ? null : next);
      h
        ..title = keep(title, h.title)
        ..status = keep(status, h.status)
        ..statusTone = statusTone ?? h.statusTone
        ..weather = keep(weather, h.weather)
        ..temperature = keep(temperature, h.temperature)
        ..updated = keep(updated, h.updated);
    });
  }

  /// Background scene: none, day, dusk, night or rain.
  void setScene(String scene) {
    if (!flowScenes.contains(scene)) throw ArgumentError.value(scene, 'scene');
    _apply(() => _require().scene = scene);
  }

  /// `light` or `dark`.
  void setTheme(String theme) {
    if (theme != 'light' && theme != 'dark') throw ArgumentError.value(theme, 'theme');
    _apply(() => _require().theme = theme);
  }

  /// `1` = from → to, `-1` = to → from.
  void setFlowDirection(String id, int direction) {
    if (direction != 1 && direction != -1) throw ArgumentError.value(direction, 'direction', 'Must be 1 or -1');
    _apply(() => _edge(id).direction = direction);
  }

  /// Applies a batch update in the shape of the HTML `energy-flow-data` event:
  ///
  /// ```dart
  /// flow.applyData({
  ///   'nodes': {'solar': {'value': 8.7, 'unit': 'kW'}},
  ///   'flows': {'solar': 'active', 'grid': 'inactive'},
  /// });
  /// ```
  ///
  /// Node entries may also contain `state`; flow entries may be a state string
  /// or a map with `state` and `direction`.
  void applyData(Map<String, dynamic> data) => _apply(() {
    final nodes = data['nodes'], flows = data['flows'];
    if (nodes is Map) {
      for (final MapEntry(:key, :value) in nodes.entries) {
        final n = _node('$key');
        if (value is! Map) throw ArgumentError.value(value, 'nodes.$key', 'Must be a map');
        if (value.containsKey('name')) n.name = jsString(value['name']);
        if (value.containsKey('value')) n.value = value['value'];
        if (value.containsKey('unit')) n.unit = jsString(value['unit']);
        if (value.containsKey('current')) n.current = value['current'];
        if (value.containsKey('currentUnit')) n.currentUnit = jsString(value['currentUnit']);
        if (value.containsKey('efficiency')) n.efficiency = value['efficiency'];
        if (value.containsKey('status')) n.status = jsString(value['status']);
        if (value.containsKey('showDetails')) n.showDetails = value['showDetails'] == true;
        if (value.containsKey('state')) n.state = FlowState.parse(value['state']);
        if (value.containsKey('soc')) n.soc = value['soc'] == null ? null : (value['soc'] as num).clamp(0, 100).toDouble();
        if (value.containsKey('badge')) n.badge = (value['badge'] ?? '') == '' ? null : jsString(value['badge']);
        if (value['badgeTone'] case final String tone when badgeTones.contains(tone)) n.badgeTone = tone;
        if (value.containsKey('lit')) n.lit = value['lit'] == true;
      }
    }
    if (flows is Map) {
      for (final MapEntry(:key, :value) in flows.entries) {
        final e = _edge('$key');
        if (value is Map) {
          if (value.containsKey('state')) e.state = FlowState.parse(value['state']);
          if (value['color'] case final String c) e.color = parseHexColor(c);
          if (value['trackColor'] case final String c) e.trackColor = parseHexColor(c);
          final direction = value['direction'];
          if (direction != null) {
            if (direction != 1 && direction != -1) throw ArgumentError.value(direction, 'direction');
            e.direction = direction as int;
          }
        } else {
          e.state = FlowState.parse(value);
        }
      }
    }
  });

  /// Freezes the line motion in place.
  void pause() {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
  }

  /// Resumes the line motion.
  void play() {
    if (_playing) return;
    _playing = true;
    notifyListeners();
  }

  FlowProject _require() => _project ?? (throw StateError('The Flow Studio project is not loaded yet'));

  FlowNode _node(String id) => _require().node(id) ?? (throw ArgumentError.value(id, 'id', 'Unknown node'));

  FlowEdge _edge(String id) => _require().edge(id) ?? (throw ArgumentError.value(id, 'id', 'Unknown line'));

  void _apply(void Function() change) {
    if (_project == null) {
      _pending.add(change);
      return;
    }
    change();
    notifyListeners();
  }

  Future<void> _guard(Future<void> load) async {
    try {
      await load;
    } catch (e, s) {
      _error = e;
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'flow_studio'));
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images = {};
    if (!_ready.isCompleted) {
      _ready.future.ignore();
      _ready.completeError(StateError('FlowController was disposed'));
    }
    _ready = Completer<void>();
    super.dispose();
  }
}
