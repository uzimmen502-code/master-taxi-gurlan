import 'package:flutter/material.dart';

import '../../core/widgets/zone_gate.dart';
import '../../features/home/home_screen.dart';

/// Barcha Home kirishlari shu route orqali — ZoneGate majburiy.
Route<void> appHomeRoute() => MaterialPageRoute<void>(
      builder: (_) => const ZoneGate(child: HomeScreen()),
    );

void pushAppHome(BuildContext context) {
  Navigator.of(context).pushReplacement(appHomeRoute());
}
