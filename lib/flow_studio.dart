/// Render Flow Studio energy-flow diagrams natively in Flutter.
///
/// Export a `.flow.json` from the Flow Studio editor, add it to your assets,
/// then:
///
/// ```dart
/// final flow = FlowController.asset('assets/hybrid.flow.json');
/// FlowStudioView(controller: flow);
/// flow.setNodeData('solar', value: 8.7, status: 'Online');
/// ```
library;

export 'src/controller.dart' show FlowController;
export 'src/geometry.dart'
    show BezierShape, curvedRoute, edgePortPoint, edgeShape, pulseDash, routePoints, roundedRoute, trackDash;
export 'src/model.dart'
    show FlowAsset, FlowEdge, FlowNode, FlowPort, FlowProject, FlowRoute, FlowState, LabelSide, TrackStyle, jsString, parseHexColor;
export 'src/render.dart' show FlowImage, FlowScene, FlowTextStyle;
export 'src/view.dart' show FlowStudioView;
