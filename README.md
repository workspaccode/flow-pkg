# flow_studio

Renders [Flow Studio](../../README.md) energy-flow diagrams natively in Flutter:
the same routes, rounded corners, animated pulses, artwork, labels and states as
the editor, with no WebView. You design in the editor; your app only loads the
exported file.

## Use

1. In the editor choose **Export → Flutter (native)**. It downloads the
   `.flow.json` file and shows a complete widget with your element ids.
2. Add the file and the package to your app:

   ```yaml
   dependencies:
     flow_studio:
       path: ../flow_studio

   flutter:
     assets:
       - assets/hybrid.flow.json
   ```

3. Show it and push data:

   ```dart
   import 'package:flow_studio/flow_studio.dart';

   final flow = FlowController.asset('assets/hybrid.flow.json');

   FlowStudioView(controller: flow, onNodeTap: (node) => print(node.id));

   flow.setNodeData('solar', value: 8.7, unit: 'kW', status: 'Online');
   flow.setNodeState('grid', FlowState.inactive);
   flow.setFlowState('grid', FlowState.hidden);
   flow.setFlowDirection('battery', -1);
   flow.pause();
   flow.play();
   ```

Calls made before the file finishes loading are applied once it is ready.
`FlowStudioView.asset('assets/hybrid.flow.json')` is the shortest form when you
don't need to update data.

| Editor (HTML export) | Flutter |
| --- | --- |
| `energyFlow.setNodeState(id, 'active')` | `flow.setNodeState(id, FlowState.active)` |
| `energyFlow.setFlowState(id, 'hidden')` | `flow.setFlowState(id, FlowState.hidden)` |
| `energyFlow.setNodeData(id, {value: 8.7})` | `flow.setNodeData(id, value: 8.7)` |
| `energyFlow.setFlowDirection(id, -1)` | `flow.setFlowDirection(id, -1)` |
| `energy-flow-data` event | `flow.applyData({'nodes': {...}, 'flows': {...}})` |
| `pause()` / `play()` | `flow.pause()` / `flow.play()` |

### `FlowStudioView` options

| Option | Default | |
| --- | --- | --- |
| `transparent` | `false` | Skip the canvas background color. |
| `textStyle` | Arial | `FlowTextStyle(fontFamily: ..., package: ...)` for labels. |
| `time` | animate | A fixed time in seconds for a still frame. |
| `expand` | `false` | Grow beyond the canvas width (like the HTML export, it caps by default). |
| `onNodeTap` | | Called with the element whose artwork or label was tapped. |
| `placeholder`, `errorBuilder` | | Shown while loading / on an invalid file. |

The view keeps the canvas aspect ratio and pauses motion when the system asks
to reduce animations.

### Line options

Lines (`edges`) may carry these optional fields. Missing fields take the
default, so older files render exactly as before; present fields are validated
(an out-of-range value rejects the file with `Invalid line data`).

| Field | Dart | Default | Range |
| --- | --- | --- | --- |
| `route` | `FlowRoute` | `orthogonal` | `orthogonal`, `straight`, `curved` |
| `sourceOffset`, `targetOffset` | `double` | `0` | -2048…2048 px, along the port's side |
| `pulses` | `int` | `1` | 1…12 moving pulses |
| `pulseLength` | `double` | `0.12` | 0.02…0.9 of each pulse period |
| `glow` | `double` | `0.13` | 0…1 glow opacity (0 = no glow) |
| `trackStyle` | `TrackStyle` | `solid` | `solid`, `dashed`, `dotted` |

`edgeShape(project, edge)` returns the drawn curve for any route;
`trackDash(edge)` and `pulseDash(length, edge)` give the dash numbers used by
the editor's SVG and Lottie exports.

## Fidelity

* **Routes** are a line-by-line port of `src/core.js`. `test/geometry_test.dart`
  checks that 344 lines across 45 projects (the presets, the example, 40
  random layouts with every route mode and port offsets, and a curves/offsets
  sheet) produce character-identical SVG path data and dash numbers.
* **Pixels**: `test/parity_test.dart` renders `examples/hybrid-energy-flow.flow.json`
  and compares it with the editor's PNG export of the same file at 2×, 0.75 s.
  0.31% of pixels differ, all on anti-aliased glyph edges; the mean channel
  difference is 0.65/255.
* **Fonts** are the one thing that depends on the device. Labels use Arial, as
  in the editor. iOS and macOS have it; on Android, bundle Arial or a
  metric-compatible font such as Arimo, plus an Arabic font for Arabic labels,
  and pass it with `textStyle`.

## Develop

```sh
flutter test                    # parity + controller tests
node tool/geometry_fixtures.js  # regenerate expected paths after changing src/core.js
cd example && flutter run       # demo app with live values
```

## Lines above elements

A line with `"onTop": true` is painted after the elements instead of beneath them — the editor uses
it for cables that run across a house from its roof panels to a wall inverter. `FlowEdge.onTop`
defaults to `false`, and older files stay unchanged.

## Anchored line ends

`"sourceAnchor": [dx, dy]` / `"targetAnchor": [dx, dy]` pin a line end to an exact point relative to the
element's centre instead of a side port — the editor uses them for cables that enter a wall inverter or a
battery at a specific point. `FlowEdge.sourceAnchor` / `targetAnchor` are `null` when not set.
