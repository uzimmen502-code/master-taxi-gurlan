import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_trip_selection.dart';
import '../models/ev_trip_plan.dart';
import 'ev_occupancy_badge.dart';
import 'ev_trip_plan_view.dart' show evTripStationSpecLine;
import 'ev_trip_stop_icon.dart';

/// ⚡ Харитадаги станция маркери босилганда чиқадиган ихчам варақа (эга
/// қарори, 2026-10-16): ҳайдовчи станцияни кўради ва «Тўхташ режасига
/// қўшиш» / «Режадан олиб ташлаш» тугмаси билан ўзи ҳал қилади. Илова фақат
/// ТАВСИЯ қилади («Тавсия» — асосий, «Заҳира» — заҳира; бошқаларда белги
/// йўқ). Ички тушунчалар (зона, босқич...) кўрсатилмайди.
///
/// Чеклов тўлган бўлса (Google Maps оралиқ нуқталар сони) янги станцияни
/// қўшиб бўлмайди: тугма ўчиқ ва сабаби ёзилади.
class EvTripStationSheet extends StatelessWidget {
  const EvTripStationSheet({
    super.key,
    required this.candidate,
    required this.number,
    required this.canAdd,
    required this.maxWaypoints,
    required this.onToggle,
    this.onReplace,
  });

  final EvTripCandidate candidate;

  /// Тавсия этилган (режадаги) тўхташ учун «Алмаштириш». `null` — тугма йўқ.
  final VoidCallback? onReplace;

  /// Танланган бўлса — йўл бўйича тартиб рақами (1'дан); бўлмаса `null`.
  final int? number;

  /// Танланмаган станцияни яна қўшиш мумкинми (чеклов тўлмаган).
  final bool canAdd;

  /// Амалдаги чеклов (мобил веб 3, бошқа 9) — огоҳлантириш матнида.
  final int maxWaypoints;

  final VoidCallback onToggle;

  bool get selected => number != null;

  /// Варақани очиш. Тугма босилса танлов ўзгаради ва варақа ёпилади (ҳайдовчи
  /// харитада янги рақамларни кўради).
  static Future<void> show(
    BuildContext context, {
    required EvTripSelection selection,
    required EvTripCandidate candidate,
    VoidCallback? onReplace,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => EvTripStationSheet(
        candidate: candidate,
        number: selection.numbers[candidate.id],
        canAdd: selection.canAdd(candidate.id),
        maxWaypoints: selection.maxWaypoints,
        onToggle: () {
          selection.toggle(candidate.id);
          Navigator.of(sheetContext).pop();
        },
        onReplace: onReplace == null
            ? null
            : () {
                // Avval varaqa yopiladi, keyin almashtirish varag'i ochiladi.
                Navigator.of(sheetContext).pop();
                onReplace();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final km = context.tr('ev_trip_km');
    final s = candidate.station;
    final title = s.hasName ? s.name!.trim() : context.tr('ev_trip_station');
    final spec = evTripStationSpecLine(s);
    final blocked = !selected && !canAdd;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (candidate.kind != EvTripMarkerKind.other ||
                s.occupancyFresh) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (candidate.kind != EvTripMarkerKind.other)
                      _KindBadge(kind: candidate.kind),
                    // Бўш/Банд — фақат янги (30 дақиқа) белги бўлса.
                    EvOccupancyBadge(station: s),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selected) ...[
                  Container(
                    key: const ValueKey('ev_station_sheet_number'),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: EvTripStopIcon.color,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('ev_station_sheet_title'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(
              Icons.route_rounded,
              '${context.tr('ev_trip_from_start')}: '
              '${candidate.alongKm.round()} $km',
            ),
            _line(
              Icons.alt_route_rounded,
              candidate.offRouteKm >= 1
                  ? '${context.tr('ev_trip_off_route')} '
                      '${candidate.offRouteKm.round()} $km'
                  : context.tr('ev_trip_on_route'),
            ),
            if (spec.isNotEmpty) _line(Icons.ev_station_rounded, spec),
            if (evStationIsUnverifiedImport(s))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Chip(
                    text: context.tr('ev_trip_unverified'),
                    bg: const Color(0xFFFFF3E0),
                    fg: const Color(0xFFE65100),
                  ),
                ),
              ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  context
                      .tr('ev_trip_sel_full')
                      .replaceAll('{n}', '$maxWaypoints'),
                  key: const ValueKey('ev_station_sheet_limit'),
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFFC62828)),
                ),
              ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: ElevatedButton.icon(
                key: const ValueKey('ev_station_sheet_toggle'),
                onPressed: blocked ? null : onToggle,
                icon: Icon(
                    selected ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    size: 24),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: const Color(0xFFBDBDBD),
                  disabledForegroundColor: const Color(0xFF616161),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                label: Text(
                  context.tr(selected ? 'ev_trip_remove_stop' : 'ev_trip_add_stop'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (onReplace != null) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: OutlinedButton.icon(
                  key: const ValueKey('ev_station_sheet_replace'),
                  onPressed: onReplace,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 24),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: const BorderSide(
                        color: AppColors.primaryText, width: 1.4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  label: Text(
                    context.tr('ev_alt_swap'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primaryText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final EvTripMarkerKind kind;

  @override
  Widget build(BuildContext context) {
    final recommended = kind == EvTripMarkerKind.primary;
    return _Chip(
      key: ValueKey(recommended
          ? 'ev_station_badge_recommended'
          : 'ev_station_badge_backup'),
      text: context.tr(
          recommended ? 'ev_trip_badge_recommended' : 'ev_trip_legend_backup'),
      bg: recommended ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0),
      fg: recommended ? EvTripStopIcon.color : const Color(0xFFE65100),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
