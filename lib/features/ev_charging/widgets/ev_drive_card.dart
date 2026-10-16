import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_drive_mode.dart';
import 'ev_occupancy_badge.dart';

/// ⚡ «Йўл режими» карточкаси (эга қарори, 2026-10-16): машина ҳаракатда
/// бўлганда хаританинг пастида ихчам «Кейинги зарядлаш» кўрсатилади. Бир
/// қарашда ўқиладиган: масофа, келишдаги заряд, станция номи, банд/бўш
/// белгиси ва ИККИТА катта тугма (≥ 56 dp): «Банд» ва «Алмаштириш».
/// Матн киритиш майдони йўқ.
///
/// Станцияга етганда (150 м ичида) «Етиб келдингиз» ҳолати: бетараф
/// «Зарядлаш бошланди» тасдиғи (карточкани шу тўхташ учун яширади).
/// Бу ҳолатда қўшимча катта тугма бор — ҳайдовчи станция банд бўлса шу
/// ерда «Банд»/«Алмаштириш»ни босиши мумкин.
class EvDriveCard extends StatelessWidget {
  const EvDriveCard({
    super.key,
    required this.target,
    required this.onBusy,
    required this.onAlternatives,
    required this.onConfirmCharging,
    this.onUpdateSoc,
    this.busyInFlight = false,
  });

  final EvDriveTarget target;

  /// «Банд» — станция банд эканини хабар қилиш (жамоа белгиси).
  final VoidCallback onBusy;

  /// «Алмаштириш». `null` — ўчиқ (қайта ҳисоблаш учун маълумот йўқ).
  final VoidCallback? onAlternatives;

  /// «Зарядлаш бошланди» (фақат етиб келганда).
  final VoidCallback onConfirmCharging;

  /// «Зарядни янгилаш» (кичик ҳаволa-тугма, катта тугма эмас).
  final VoidCallback? onUpdateSoc;

  /// «Банд» хабари юборилмоқда — тугма вақтинча ўчиқ (қайта босилмасин).
  final bool busyInFlight;

  static const double bigButtonHeight = 56;

  @override
  Widget build(BuildContext context) {
    final station = target.stop.station;
    final name =
        station.hasName ? station.name!.trim() : context.tr('ev_trip_station');
    final arrived = target.arrived;

    return Material(
      key: const ValueKey('ev_drive_card'),
      color: Colors.white,
      elevation: 10,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  arrived ? Icons.check_circle_rounded : Icons.ev_station_rounded,
                  size: 26,
                  color: AppColors.primaryText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    arrived
                        ? context.tr('ev_drive_arrived')
                        : context.tr('ev_drive_next').replaceAll(
                            '{d}', _distanceText(context, target.distanceKm)),
                    key: const ValueKey('ev_drive_title'),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              key: const ValueKey('ev_drive_station_name'),
              maxLines: 2,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!arrived)
                  Text(
                    context
                        .tr('ev_drive_arrival_soc')
                        .replaceAll('{p}', '${target.arriveSocPercent}'),
                    key: const ValueKey('ev_drive_arrival_soc'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                // Бўш/Банд — фақат янги (30 дақиқа) белги бўлса.
                EvOccupancyBadge(station: station),
              ],
            ),
            const SizedBox(height: 10),
            if (arrived) ...[
              _BigButton(
                key: const ValueKey('ev_drive_charging_started'),
                label: context.tr('ev_drive_charging_started'),
                icon: Icons.bolt_rounded,
                filled: true,
                onPressed: onConfirmCharging,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: _BigButton(
                    key: const ValueKey('ev_drive_busy_button'),
                    label: context.tr('ev_mark_busy'),
                    icon: Icons.hourglass_bottom_rounded,
                    filled: false,
                    onPressed: busyInFlight ? null : onBusy,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigButton(
                    key: const ValueKey('ev_drive_alt_button'),
                    label: context.tr('ev_alt_swap'),
                    icon: Icons.swap_horiz_rounded,
                    filled: !arrived,
                    onPressed: onAlternatives,
                  ),
                ),
              ],
            ),
            if (onUpdateSoc != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('ev_drive_update_soc'),
                  onPressed: onUpdateSoc,
                  icon: const Icon(Icons.battery_charging_full_rounded, size: 20),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  label: Text(context.tr('ev_soc_update')),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// `42 км`; 1 км дан кам — `<1 км`; 10 км гача — битта ўнлик (`3.4 км`).
  static String _distanceText(BuildContext context, double km) {
    final unit = context.tr('ev_trip_km');
    if (km < 1) return '<1 $unit';
    if (km < 10) return '${km.toStringAsFixed(1)} $unit';
    return '${km.round()} $unit';
  }
}

/// Катта тугма (≥ 56 dp): матн кичрайиб бир қаторга сиғади (катта шрифтда ҳам).
class _BigButton extends StatelessWidget {
  const _BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 8),
          Text(label,
              maxLines: 1,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
    return SizedBox(
      height: EvDriveCard.bigButtonHeight,
      child: filled
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor: const Color(0xFFBDBDBD),
                disabledForegroundColor: const Color(0xFF616161),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: shape,
              ),
              child: text,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                side: const BorderSide(color: AppColors.primaryText, width: 1.4),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: shape,
              ),
              child: text,
            ),
    );
  }
}
