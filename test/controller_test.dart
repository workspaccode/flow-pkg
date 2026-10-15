import 'dart:convert';
import 'dart:io';

import 'package:flow_studio/flow_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> example() =>
    jsonDecode(File('../../examples/hybrid-energy-flow.flow.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('rejects files that are not Flow Studio projects', () {
    expect(() => FlowProject.fromJson({'v': '5.12.2', 'layers': []}), throwsFormatException);
    final bad = example();
    (bad['edges'] as List).first['to'] = 'missing';
    expect(() => FlowProject.fromJson(bad), throwsFormatException);
  });

  test('lines can be drawn above the elements (onTop)', () {
    final json = example();
    final edges = json['edges'] as List;
    edges[0]['onTop'] = true;
    final project = FlowProject.fromJson(json);
    expect(project.edges[0].onTop, isTrue);
    expect(project.edges[1].onTop, isFalse);
    expect(project.edges[0].toJson()['onTop'], isTrue);
    expect(project.edges[1].toJson().containsKey('onTop'), isFalse, reason: 'older files stay unchanged');
    edges[0]['onTop'] = 'yes';
    expect(() => FlowProject.fromJson(json), throwsFormatException);
  });

  test('line anchors pin ends to exact points', () {
    final json = example();
    final e = (json['edges'] as List)[0] as Map<String, dynamic>;
    e['sourceAnchor'] = [10, -5];
    final project = FlowProject.fromJson(json);
    final edge = project.edges[0], from = project.node(edge.from)!;
    expect(routePoints(project, edge).first, Offset(from.x + 10, from.y - 5));
    expect(edge.toJson()['sourceAnchor'], [10.0, -5.0]);
    edge.sourceAnchor = null;
    expect(edge.toJson().containsKey('sourceAnchor'), isFalse);
    e['sourceAnchor'] = [1];
    expect(() => FlowProject.fromJson(json), throwsFormatException);
  });

  test('round-trips the editor file', () {
    final project = FlowProject.fromJson(example());
    final again = FlowProject.fromJson(jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);
    expect(again.nodes.map((n) => n.id), project.nodes.map((n) => n.id));
    expect(again.edges.first.waypoints, project.edges.first.waypoints);
    expect(again.node('junction')!.showLabel, isFalse);
  });

  testWidgets('applies updates made before loading and reacts to changes', (tester) async {
    final flow = FlowController();
    flow.setNodeData('solar', value: 8.7, status: 'Online');
    flow.setFlowState('grid', FlowState.active);
    FlowNode? tapped;

    await tester.pumpWidget(MaterialApp(
      home: FlowStudioView(controller: flow, onNodeTap: (n) => tapped = n),
    ));
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.runAsync(() => flow.loadJson(example()));
    await tester.pump();
    expect(flow.project!.node('solar')!.value, 8.7);
    expect(flow.project!.node('solar')!.status, 'Online');
    expect(flow.project!.edge('grid')!.state, FlowState.active);
    expect(find.bySemanticsLabel('Hybrid energy flow'), findsOneWidget);

    // Tap the middle of the inverter artwork (canvas 340,315 of 1000×650).
    final box = tester.getRect(find.byType(AspectRatio));
    await tester.tapAt(box.topLeft + Offset(340 * box.width / 1000, 315 * box.height / 650));
    expect(tapped?.id, 'inverter');

    flow.applyData({
      'nodes': {'battery': {'value': 1.5, 'state': 'hidden'}},
      'flows': {'battery': {'state': 'inactive', 'direction': 1}},
    });
    await tester.pump();
    expect(flow.project!.node('battery')!.state, FlowState.hidden);
    expect(flow.project!.edge('battery')!.direction, 1);

    expect(() => flow.setNodeState('nope', FlowState.active), throwsArgumentError);
    expect(() => flow.setFlowDirection('solar', 2), throwsArgumentError);

    flow.pause();
    await tester.pump();
    expect(flow.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox());
    flow.dispose();
  });
}
