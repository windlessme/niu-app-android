import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import '../home/campus_services.dart';

/// Small utilities that don't need a place on home.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context) => const NiuScrollPage(
    title: '小工具',
    children: [CampusServiceGrid(services: CampusServices.toolbox)],
  );
}
