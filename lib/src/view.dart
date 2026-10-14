import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'model.dart';
import 'render.dart';

/// Displays a Flow Studio project with its animated lines.
///
/// ```dart
/// FlowStudioView.asset('assets/hybrid.flow.json')
/// ```
///
/// The view keeps the canvas aspect ratio and, like the HTML export, never
/// grows beyond the canvas width; wrap it in a [SizedBox] or [FittedBox] to
/// change that.
class FlowStudioView extends StatefulWidget {
  const FlowStudioView({
    super.key,
    required FlowController this.controller,
    this.transparent = false,
    this.textStyle = const FlowTextStyle(),
    this.time,
    this.expand = false,
    this.onNodeTap,
    this.placeholder,
    this.errorBuilder,
  }) : assetPath = null,
       bundle = null;

  /// Loads a `.flow.json` asset. Pass a [controller] to update data later.
  const FlowStudioView.asset(
    String this.assetPath, {
    super.key,
    this.controller,
    this.bundle,
    this.transparent = false,
    this.textStyle = const FlowTextStyle(),
    this.time,
    this.expand = false,
    this.onNodeTap,
    this.placeholder,
    this.errorBuilder,
  });

  final FlowController? controller;
  final String? assetPath;
  final AssetBundle? bundle;

  /// Skips the canvas background color.
  final bool transparent;

  /// Font used for labels. Bundle Arial (or a metric-compatible font such as
  /// Arimo, plus an Arabic font) for pixel-identical labels on Android.
  final FlowTextStyle textStyle;

  /// Shows a still frame at this many seconds instead of animating.
  final double? time;

  /// Fills the available width even if it is wider than the canvas.
  final bool expand;

  /// Called with the element (artwork or label) under a tap.
  final ValueChanged<FlowNode>? onNodeTap;

  /// Shown while the project loads.
  final Widget? placeholder;

  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<FlowStudioView> createState() => _FlowStudioViewState();
}

class _FlowStudioViewState extends State<FlowStudioView> with SingleTickerProviderStateMixin {
  FlowController? _owned;
  late FlowController _controller;
  FlowScene? _scene;
  FlowProject? _sceneProject;
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _time = ValueNotifier(0);
  double _base = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final given = widget.controller;
    if (given == null) {
      _owned = FlowController.asset(widget.assetPath!, bundle: widget.bundle);
      _controller = _owned!;
    } else {
      _controller = given;
      final path = widget.assetPath;
      if (path != null) given.loadAsset(path, bundle: widget.bundle).catchError(_reportLoadError);
    }
    _controller.addListener(_changed);
    _rebuildScene();
  }

  void _reportLoadError(Object e, StackTrace s) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s, library: 'flow_studio'));
  }

  void _detach() {
    _controller.removeListener(_changed);
    _owned?.dispose();
    _owned = null;
  }

  @override
  void didUpdateWidget(FlowStudioView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.assetPath != widget.assetPath || old.bundle != widget.bundle) {
      _detach();
      _attach();
    } else if (old.textStyle != widget.textStyle) {
      _rebuildScene();
    }
    _syncTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  void _changed() {
    setState(_rebuildScene);
    _syncTicker();
  }

  void _rebuildScene() {
    final project = _controller.project;
    if (project == null) {
      _scene?.dispose();
      _scene = null;
      return;
    }
    _scene?.dispose();
    _scene = FlowScene.build(project, _controller.images, widget.textStyle);
    _sceneProject = project;
  }

  bool get _animating =>
      widget.time == null && !_reduceMotion && _controller.isPlaying && (_scene?.hasMotion ?? false);

  void _syncTicker() {
    if (widget.time case final time?) {
      _time.value = time;
    }
    if (_animating && !_ticker.isActive) {
      _base = _time.value;
      _ticker.start();
    } else if (!_animating && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    _time.value = _base + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _scene?.dispose();
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final error = _controller.error;
    if (scene == null) {
      if (error != null && widget.errorBuilder != null) return widget.errorBuilder!(context, error);
      return widget.placeholder ?? const SizedBox.shrink();
    }
    final project = _sceneProject!;
    final paint = CustomPaint(
      painter: _FlowPainter(scene, _time, widget.transparent),
      isComplex: true,
      willChange: _animating,
    );
    Widget child = paint;
    if (widget.onNodeTap != null) {
      child = LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final scale = project.width / constraints.maxWidth;
            final node = scene.nodeAt(details.localPosition * scale);
            if (node != null) widget.onNodeTap!(node);
          },
          child: paint,
        ),
      );
    }
    child = Semantics(
      image: true,
      label: project.title,
      child: AspectRatio(aspectRatio: project.width / project.height, child: child),
    );
    if (!widget.expand) child = ConstrainedBox(constraints: BoxConstraints(maxWidth: project.width), child: child);
    return Center(widthFactor: 1, heightFactor: 1, child: child);
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.scene, this.time, this.transparent) : super(repaint: time);

  final FlowScene scene;
  final ValueNotifier<double> time;
  final bool transparent;

  @override
  void paint(Canvas canvas, Size size) {
    final p = scene.project;
    canvas.save();
    canvas.scale(size.width / p.width, size.height / p.height);
    scene.paint(canvas, time: time.value, transparent: transparent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.scene != scene || old.transparent != transparent;
}
