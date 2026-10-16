import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_station.dart';
import '../controllers/ev_trip_summary.dart';
import '../models/ev_trip_plan.dart';
import 'ev_occupancy_badge.dart';

/// ⚡ Сафар режасининг кўриниши — асосий ва заҳира станциялар, ораларидаги
/// масофа, заряд прогнози.
///
/// Иккита қоида UI'да ҳам сақланади:
///   1. Узилиш бўлса (`gapTooLarge`) — «режа тайёр» деб кўрсатилмайди,
///      очиқ огоҳлантириш чиқади.
///   2. Текширилмаган нуқта ҳар карточкада белгиланади — ҳайдовчи нимага
///      ишонаётганини билиб турсин.
class EvTripPlanView extends StatelessWidget {
  const EvTripPlanView({
    super.key,
    required this.plan,
    required this.onOpenNavigator,
    this.routeMinutes = 0,
    this.car,
  });

  final EvTripPlan plan;
  final VoidCallback onOpenNavigator;

  /// Google маршрутидаги жами йўл вақти (дақиқа); 0 — номаълум (кўрсатилмайди).
  final int routeMinutes;

  /// Режа тузилган автомобил: тўхташда қўшиладиган энергия ва «камида»
  /// зарядлаш вақти шундан ҳисобланади. Йўқ бўлса — бу қаторлар йўқ.
  final EvCarSpec? car;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(context),
        if (plan.status == EvTripPlanStatus.gapTooLarge) _gapBanner(context),
        if (plan.warnings.isNotEmpty) _warnings(context),
        const SizedBox(height: 8),
        for (var i = 0; i < plan.stops.length; i++)
          _StopCard(stop: plan.stops[i], index: i + 1, car: car),
        if (plan.isOk && plan.stops.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onOpenNavigator,
              icon: const Icon(Icons.navigation_rounded, size: 20),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              label: Text(context.tr('ev_trip_open_navigator')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final noCharging = plan.status == EvTripPlanStatus.noChargingNeeded;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: noCharging
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                noCharging
                    ? Icons.check_circle_rounded
                    : Icons.ev_station_rounded,
                size: 20,
                color: AppColors.primaryText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  noCharging
                      ? context.tr('ev_trip_no_charging')
                      : '${plan.chargeStopCount} ${context.tr('ev_trip_charge_stops')}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${context.tr('ev_trip_total_distance')}: '
            '${plan.totalKm.round()} ${context.tr('ev_trip_km')}',
            style: const TextStyle(fontSize: 13),
          ),
          if (routeMinutes > 0)
            Text(
              '${context.tr('ev_trip_drive_time')}: '
              '${evTripDurationText(context, routeMinutes)}',
              key: const ValueKey('ev_trip_summary_drive_time'),
              style: const TextStyle(fontSize: 13),
            ),
          if (plan.isOk)
            Text(
              '${context.tr('ev_trip_arrival')}: ${plan.arrivalSocPercent}%',
              style: const TextStyle(fontSize: 13),
            ),
          ..._chargeTime(context),
        ],
      ),
    );
  }

  /// «Зарядлаш вақти: камида ~X» + изоҳ. Фақат қуввати маълум тўхташлар
  /// йиғиндиси (қуйи чегара); ҳеч бирида қувват маълум бўлмаса — қатор йўқ.
  List<Widget> _chargeTime(BuildContext context) {
    final total = evPlanMinChargeMinutes(plan, car);
    if (total.knownStops == 0) return const [];
    return [
      Text(
        '${context.tr('ev_trip_charge_time')}: '
        '${evTripAtLeastText(context, total.minutes)}',
        key: const ValueKey('ev_trip_summary_charge_time'),
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 2),
      Text(
        context.tr('ev_trip_charge_time_note'),
        key: const ValueKey('ev_trip_summary_charge_note'),
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ];
  }

  Widget _gapBanner(BuildContext context) {
    final from = plan.gapFromKm?.round();
    final reach = plan.gapReachKm?.round();
    final next = plan.gapNextStationKm?.round();
    final km = context.tr('ev_trip_km');

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 20, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('ev_trip_gap_title'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC62828)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(context.tr('ev_trip_gap_body'),
              style: const TextStyle(fontSize: 13)),
          if (from != null && reach != null) ...[
            const SizedBox(height: 4),
            Text(
              next != null
                  ? '$from $km → $reach $km · ${context.tr('ev_trip_gap_next')}: $next $km'
                  : '$from $km → $reach $km · ${context.tr('ev_trip_gap_none')}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _warnings(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in plan.warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(context.tr(w),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// «13 с 10 дақ» — бирликлар жорий тилдан (`ev_trip_unit_h`/`_min`).
String evTripDurationText(BuildContext context, int minutes) =>
    evFormatDuration(
      minutes,
      hourUnit: context.tr('ev_trip_unit_h'),
      minuteUnit: context.tr('ev_trip_unit_min'),
    );

/// «камида ~11 дақ» — зарядлаш вақтининг қуйи чегараси.
String evTripAtLeastText(BuildContext context, int minutes) =>
    context
        .tr('ev_trip_at_least')
        .replaceAll('{t}', evTripDurationText(context, minutes));

/// Станциянинг қисқа тавсифи: зарядлаш турлари · қувват · разъёмлар
/// (режадаги тўхташ карточкаси ва харитадаги станция варағида бир хил).
String evTripStationSpecLine(EvChargingStation s) {
  final power = evStationPowerKw(s);
  final types = s.chargingTypes.join('+');
  return [
    if (types.isNotEmpty) types,
    if (power != null) '$power kW',
    if (s.connectors.isNotEmpty) s.connectors.join(' · '),
  ].join(' · ');
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.stop, required this.index, this.car});

  final EvTripStop stop;
  final int index;
  final EvCarSpec? car;

  @override
  Widget build(BuildContext context) {
    final km = context.tr('ev_trip_km');
    final s = stop.station;
    final title = s.hasName ? s.name!.trim() : context.tr('ev_trip_station');
    final charge = evStopCharge(stop, car);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Text('$index',
                    style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text('${stop.legKm.round()} $km',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            evTripStationSpecLine(s),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            '${stop.arriveSocPercent}% → ${stop.departSocPercent}%'
            '${stop.offRouteKm >= 1 ? '  ·  ${context.tr('ev_trip_off_route')} ${stop.offRouteKm.round()} $km' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (charge != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 16, color: AppColors.primaryText),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    // «+24 kWh · камида ~11 дақ»; қувват номаълум бўлса —
                    // фақат энергия (вақт ўйлаб топилмайди).
                    '+${evFormatKwh(charge.energyKwh)} kWh'
                    '${charge.minMinutes == null ? '' : ' · ${evTripAtLeastText(context, charge.minMinutes!)}'}',
                    key: const ValueKey('ev_trip_stop_charge'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
          if (stop.isUnverifiedImport || s.occupancyFresh) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Бўш/Банд — фақат янги (30 дақиқа) белги бўлса.
                EvOccupancyBadge(station: s),
                if (stop.isUnverifiedImport)
                  _badge(context.tr('ev_trip_unverified'),
                      const Color(0xFFFFF3E0), const Color(0xFFE65100)),
              ],
            ),
          ],
          if (stop.hasBackup) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('ev_trip_backup'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54),
            ),
            const SizedBox(height: 4),
            for (final b in stop.backups)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${b.station.hasName ? b.station.name!.trim() : context.tr('ev_trip_station')}'
                  '  (${b.isBefore ? '−' : '+'}${b.deltaKm.abs().round()} $km)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
