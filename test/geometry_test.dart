import 'dart:convert';
import 'dart:io';

import 'package:flow_studio/flow_studio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every line must produce exactly the same SVG path data as the editor's
/// engine (src/core.js). Regenerate with `node tool/geometry_fixtures.js`.
void main() {
  final cases = jsonDecode(File('test/fixtures/geometry.json').readAsStringSync()) as List;

  for (final c in cases.cast<Map<String, dynamic>>()) {
    final project = FlowProject.fromJson(c['project'] as Map<String, dynamic>);
    test('paths match core.js: ${project.title}', () {
      final expected = (c['paths'] as Map).cast<String, String>();
      for (final e in project.edges) {
        expect(edgeShape(project, e).toPathData(), expected[e.id], reason: 'line ${e.id}');
      }
      final dashes = (c['dashes'] as Map).cast<String, dynamic>();
      for (final e in project.edges) {
        final d = dashes[e.id] as Map<String, dynamic>;
        final track = d['track'] as List?, pulse = d['pulse'] as List;
        expect(trackDash(e), track?.map((v) => (v as num).toDouble()).toList(), reason: 'track ${e.id}');
        final (dash, gap) = pulseDash(1000, e);
        expect([dash, gap], [for (final v in pulse) (v as num).toDouble()], reason: 'pulse ${e.id}');
      }
    });
  }

  Map<String, dynamic> line([Map<String, dynamic> extra = const {}]) => {
    'id': 'l', 'from': 'a', 'to': 'b', 'sourcePort': 'right', 'targetPort': 'left', 'waypoints': [],
    'state': 'active', 'color': '#6688ff', 'trackColor': '#c9d7ff', 'width': 5, 'trackWidth': 2,
    'radius': 12, 'duration': 3.5, 'direction': 1, ...extra,
  };

  test('optional line fields default to the original look', () {
    final e = FlowEdge.fromJson(line());
    expect(e.route, FlowRoute.orthogonal);
    expect([e.sourceOffset, e.targetOffset, e.pulses, e.pulseLength, e.glow], [0, 0, 1, .12, .13]);
    expect(e.trackStyle, TrackStyle.solid);
    expect(trackDash(e), isNull);
    // Same numbers as the original `len*.12 len*.88`.
    final (dash, gap) = pulseDash(731.4159, e);
    expect([dash, gap], [731.4159 * .12, 731.4159 * .88]);
    final json = e.toJson();
    expect(FlowEdge.fromJson(json).toJson(), json);
    expect(json['route'], 'orthogonal');
    expect(json['trackStyle'], 'solid');
  });

  test('dash and pulse formulas', () {
    final dashed = FlowEdge.fromJson(line({'trackStyle': 'dashed', 'trackWidth': 2.4}));
    expect(trackDash(dashed), [9.6, 7.2]);
    final dotted = FlowEdge.fromJson(line({'trackStyle': 'dotted', 'trackWidth': 2.4}));
    expect(trackDash(dotted), [.001, 6]);
    final e = FlowEdge.fromJson(line({'pulses': 4, 'pulseLength': .25}));
    final (dash, gap) = pulseDash(800, e);
    expect([dash, gap], [50, 150]);
    expect(dash + gap, 800 / 4);
    final one = FlowEdge.fromJson(line({'pulses': 3.0, 'pulseLength': .9}));
    expect(one.pulses, 3);
    final (d1, g1) = pulseDash(300, one);
    expect(d1, closeTo(90, 1e-9));
    expect(g1, closeTo(10, 1e-9));
  });

  test('invalid optional line fields are rejected', () {
    for (final bad in <Map<String, dynamic>>[
      {'route': 'zigzag'}, {'route': null}, {'sourceOffset': 2049}, {'targetOffset': '4'}, {'pulses': 0},
      {'pulses': 13}, {'pulses': 2.5}, {'pulseLength': .01}, {'pulseLength': .95}, {'glow': -.1},
      {'glow': 1.5}, {'trackStyle': 'wavy'},
    ]) {
      expect(() => FlowEdge.fromJson(line(bad)), throwsFormatException, reason: '$bad');
    }
    final ok = FlowEdge.fromJson(line({'route': 'curved', 'sourceOffset': -2048, 'targetOffset': 2048, 'glow': 0}));
    expect([ok.route, ok.sourceOffset, ok.targetOffset, ok.glow], [FlowRoute.curved, -2048, 2048, 0]);
  });

  test('edge ports shift along their side', () {
    final project = FlowProject.fromJson({
      'format': 'flow-studio', 'version': 1, 'title': 't', 'width': 400, 'height': 300, 'background': '#ffffff',
      'assets': {},
      'nodes': [
        for (final (id, x) in [('a', 100), ('b', 300)])
          {'id': id, 'kind': 'k', 'name': id, 'x': x, 'y': 150, 'w': 40, 'h': 20, 'state': 'active',
           'fontSize': 16, 'color': '#293b55', 'labelSide': 'bottom'},
      ],
      'edges': [line({'auto': true, 'route': 'straight', 'sourceOffset': 5, 'targetOffset': -5})],
    });
    expect(routePoints(project, project.edges.single), [const Offset(120, 155), const Offset(280, 145)]);
  });

  test('jsString formats numbers like JavaScript', () {
    expect(jsString(3.0), '3');
    expect(jsString(-0.0), '0');
    expect(jsString(7.2), '7.2');
    expect(jsString(96.8), '96.8');
    expect(jsString(12), '12');
    expect(jsString('--'), '--');
  });
}
