import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_station.dart';

/// «Бўш» / «Банд» белгиси — фойдаланувчилар белгилаган бандлик (30 дақиқа
/// амал қилади). Қоида [EvChargingStation.occupancyState]да (станция
/// карточкасидаги қатор билан БИР ХИЛ манба, такрорланмайди): янги белги
/// бўлсагина кўринади; эскирган ёки ҳеч ким белгиламаган бўлса — ҳеч нарса
/// чизилмайди (ёлғон «бўш» деб айтмаймиз).
///
/// Матн калитлари мавжуд: `home_ev_free` / `home_ev_busy`.
class EvOccupancyBadge extends StatelessWidget {
  const EvOccupancyBadge({super.key, required this.station});

  final EvChargingStation station;

  @override
  Widget build(BuildContext context) {
    final free = switch (station.occupancyState) {
      'free' => true,
      'busy' => false,
      _ => null,
    };
    if (free == null) return const SizedBox.shrink();

    // Карточкалар доим ёруғ фонда — ёруғ тема токенлари (контраст).
    final tone = free ? AvaLight.ok : AvaLight.warn;
    return Container(
      key: ValueKey(free ? 'ev_occupancy_free' : 'ev_occupancy_busy'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: tone),
          const SizedBox(width: 5),
          Text(
            context.tr(free ? 'home_ev_free' : 'home_ev_busy'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: tone),
          ),
        ],
      ),
    );
  }
}
