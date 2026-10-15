import 'dart:async';
import 'dart:math';

import 'package:flow_studio/flow_studio.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: EnergyScreen()));

class EnergyScreen extends StatefulWidget {
  const EnergyScreen({super.key});

  @override
  State<EnergyScreen> createState() => _EnergyScreenState();
}

class _EnergyScreenState extends State<EnergyScreen> {
  // 1. Load the file exported from Flow Studio.
  final flow = FlowController.asset('assets/json/Hybrid-inverter-with-generator-backup.flow.json');
  final random = Random();
  late final Timer timer;
  bool gridOn = true; // Grid starts active in this project

  @override
  void initState() {
    super.initState();
    // 3. Push live readings — here, fake ones every two seconds.
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      double reading(double min, double max) =>
          double.parse((min + random.nextDouble() * (max - min)).toStringAsFixed(1));
      flow.setNodeData('solar', value: reading(5, 8));
      flow.setNodeData('inverter', value: reading(4, 6));
    });
  }

  @override
  void dispose() {
    timer.cancel();
    flow.dispose();
    super.dispose();
  }

  void toggleGrid(bool on) {
    setState(() => gridOn = on);
    flow.setNodeState('grid', on ? FlowState.active : FlowState.inactive);
    flow.setFlowState('flow', on ? FlowState.active : FlowState.inactive); // line grid → inverter
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Flow Studio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 2. Show it.
          FlowStudioView(
            controller: flow,
            onNodeTap: (node) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${node.name}: ${jsString(node.value)} ${node.unit}')),
            ),
          ),
          SwitchListTile(title: const Text('Grid backup'), value: gridOn, onChanged: toggleGrid),
          ListenableBuilder(
            listenable: flow,
            builder: (context, _) => SwitchListTile(
              title: const Text('Animate lines'),
              value: flow.isPlaying,
              onChanged: (on) => on ? flow.play() : flow.pause(),
            ),
          ),
        ],
      ),
    );
  }
}
