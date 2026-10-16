import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_navigation_waypoints.dart';

/// «Навигация» босилганда, режада заҳира станциялар бўлса, чиқадиган
/// кичик варақа (эга қарори, 2026-10-16): заҳиралар ИХТИЁРИЙ.
///
/// Google Maps'да ихтиёрий оралиқ нуқта йўқ — танланган ҳар бир заҳира
/// йўлда мажбурий тўхташга айланади. Шунинг учун ҳаммаси ЎЧИҚ бошланади
/// ва ҳайдовчи ўзи танлайди. Асосий тўхташлар бу ерда йўқ: улар доим
/// киради.
///
/// Натижа ([show]): танланган заҳира станция id'лари; «Фақат асосий» —
/// бўш тўплам; варақа ёпилса (тагидан босиш/орқага) — `null` (ҳеч нарса
/// очилмайди).
class EvNavigationBackupSheet extends StatefulWidget {
  const EvNavigationBackupSheet({
    super.key,
    required this.options,
    required this.capacity,
    required this.maxWaypoints,
  });

  final List<EvNavigationBackupOption> options;

  /// Навигацияга яна нечта заҳира сиғади (чекловдан асосийлар айрилгач).
  final int capacity;

  /// Амалдаги умумий чеклов (мобил веб 3, бошқа 9) - огоҳлантириш матнида.
  final int maxWaypoints;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<EvNavigationBackupOption> options,
    required int capacity,
    required int maxWaypoints,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EvNavigationBackupSheet(
        options: options,
        capacity: capacity,
        maxWaypoints: maxWaypoints,
      ),
    );
  }

  @override
  State<EvNavigationBackupSheet> createState() =>
      _EvNavigationBackupSheetState();
}

class _EvNavigationBackupSheetState extends State<EvNavigationBackupSheet> {
  final Set<String> _selected = <String>{};

  bool get _full => _selected.length >= widget.capacity;

  @override
  Widget build(BuildContext context) {
    final km = context.tr('ev_trip_km');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('ev_trip_nav_backups_title'),
              key: const ValueKey('ev_nav_backups_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('ev_trip_nav_backups_hint'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in widget.options) _tile(context, o, km),
                ],
              ),
            ),
            if (_full)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context
                      .tr('ev_trip_nav_backups_limit')
                      .replaceAll('{n}', '${widget.maxWaypoints}'),
                  key: const ValueKey('ev_nav_backups_limit'),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFFC62828)),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                key: const ValueKey('ev_nav_backups_continue'),
                onPressed: () => Navigator.of(context).pop(<String>{..._selected}),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  context.tr('ev_trip_nav_continue'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('ev_nav_backups_primary_only'),
              onPressed: () => Navigator.of(context).pop(<String>{}),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(
                context.tr('ev_trip_nav_primary_only'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, EvNavigationBackupOption o, String km) {
    final b = o.backup;
    final on = _selected.contains(o.id);
    final name =
        b.station.hasName ? b.station.name!.trim() : context.tr('ev_trip_station');
    return SwitchListTile(
      key: ValueKey('ev_nav_backup_${o.id}'),
      contentPadding: EdgeInsets.zero,
      value: on,
      activeThumbColor: AppColors.onPrimary,
      activeTrackColor: AppColors.primary,
      // Жой тугаган бўлса, танланмаганлар ўчирилади (ҳозиргилар ўчирилиши мумкин).
      onChanged: (!on && _full)
          ? null
          : (v) => setState(() {
                if (v) {
                  _selected.add(o.id);
                } else {
                  _selected.remove(o.id);
                }
              }),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${b.isBefore ? '−' : '+'}${b.deltaKm.abs().round()} $km',
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}
