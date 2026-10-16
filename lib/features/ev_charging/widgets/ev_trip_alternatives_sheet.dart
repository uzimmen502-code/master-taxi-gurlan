import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_trip_alternatives.dart';
import 'ev_occupancy_badge.dart';
import 'ev_trip_plan_view.dart' show evTripDurationText, evTripStationSpecLine;

/// ⚡ «Алмаштириш»: режадаги битта тўхташ учун алтернатив станциялар рўйхати
/// (эга қарори, 2026-10-16). Ҳайдовчи қарор қилади — иловa фақат таъсирини
/// кўрсатади: етиб келганда заряд, тўхташлар сони ва «камида» зарядлаш вақти
/// фарқи (ФАҚАТ ҳисоблаш мумкин бўлса), «Тавсия» — энг яхши вариант.
///
/// Ички тушунчалар (зона, босқич...) кўрсатилмайди. [large] — йўлда (катта
/// тугмалар): танлаш тугмаси 56 dp.
class EvTripAlternativesSheet extends StatelessWidget {
  const EvTripAlternativesSheet({
    super.key,
    required this.alternatives,
    this.large = false,
  });

  final List<EvTripAlternative> alternatives;
  final bool large;

  /// Варақани очади; танланган вариантни қайтаради (ҳозирги ёки ёпилса —
  /// `null`). Ҳозирги тўхташнинг ўзи танланса ҳам `null` қайтади (ўзгариш йўқ).
  static Future<EvTripAlternative?> show(
    BuildContext context, {
    required List<EvTripAlternative> alternatives,
    bool large = false,
  }) async {
    final picked = await showModalBottomSheet<EvTripAlternative>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          EvTripAlternativesSheet(alternatives: alternatives, large: large),
    );
    return (picked == null || picked.isCurrent) ? null : picked;
  }

  @override
  Widget build(BuildContext context) {
    final hasAlternatives = alternatives.any((a) => !a.isCurrent);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('ev_alt_title'),
              key: const ValueKey('ev_alt_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('ev_alt_hint'),
              style: const TextStyle(fontSize: 13, color: AvaLight.ink2),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  for (final a in alternatives)
                    _AltTile(
                      key: ValueKey('ev_alt_tile_${a.station.id}'),
                      alt: a,
                      large: large,
                    ),
                  if (!hasAlternatives)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        context.tr('ev_alt_none'),
                        key: const ValueKey('ev_alt_none'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `−7 км` / `+12 км` (ҳозирги тўхташга нисбатан).
String evAltDeltaKmText(BuildContext context, double deltaKm) {
  final n = deltaKm.abs().round();
  if (n == 0) return '0 ${context.tr('ev_trip_km')}';
  return '${deltaKm < 0 ? '−' : '+'}$n ${context.tr('ev_trip_km')}';
}

String _signedInt(int v) => v == 0 ? '0' : (v < 0 ? '−${-v}' : '+$v');

/// `+6 дақ` / `−4 дақ` / `0 дақ`.
String evAltSignedMinutes(BuildContext context, int minutes) {
  if (minutes == 0) return '0 ${context.tr('ev_trip_unit_min')}';
  final text = evTripDurationText(context, minutes.abs());
  return '${minutes < 0 ? '−' : '+'}$text';
}

class _AltTile extends StatelessWidget {
  const _AltTile({super.key, required this.alt, required this.large});

  final EvTripAlternative alt;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = alt.station;
    final km = context.tr('ev_trip_km');
    final title = s.hasName ? s.name!.trim() : context.tr('ev_trip_station');
    final spec = evTripStationSpecLine(s);

    final route = [
      if (!alt.isCurrent) evAltDeltaKmText(context, alt.deltaKm),
      alt.offRouteKm >= 1
          ? '${context.tr('ev_trip_off_route')} ${alt.offRouteKm.round()} $km'
          : context.tr('ev_trip_on_route'),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: alt.isBest ? AppColors.primaryDark : const Color(0xFFE3E7EE),
          width: alt.isBest ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alt.isBest || alt.isCurrent || s.occupancyFresh) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (alt.isBest)
                  _Tag(
                    key: const ValueKey('ev_alt_badge_best'),
                    text: context.tr('ev_trip_badge_recommended'),
                    bg: AppColors.primary,
                    fg: AppColors.onPrimary,
                  ),
                if (alt.isCurrent)
                  _Tag(
                    key: const ValueKey('ev_alt_badge_current'),
                    text: context.tr('ev_alt_current'),
                    bg: const Color(0xFFEEEEEE),
                    fg: AvaLight.ink2,
                  ),
                // Бўш/Банд — фақат янги (30 дақиқа) белги бўлса.
                EvOccupancyBadge(station: s),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(route, style: const TextStyle(fontSize: 13, color: AvaLight.ink2)),
          if (spec.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(spec, style: const TextStyle(fontSize: 13)),
          ],
          if (!alt.powerKnown) ...[
            const SizedBox(height: 2),
            Text(
              context.tr('ev_alt_power_unknown'),
              key: const ValueKey('ev_alt_power_unknown'),
              style: const TextStyle(fontSize: 12, color: AvaLight.warn),
            ),
          ],
          ..._effects(context),
          if (!alt.isCurrent) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: large ? 56 : 48),
              child: ElevatedButton(
                key: ValueKey('ev_alt_choose_${s.id}'),
                onPressed: () => Navigator.of(context).pop(alt),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  context.tr('ev_alt_choose'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: large ? 18 : 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Танлашнинг сафарга таъсири — ФАҚАТ ҳисоблаш мумкин бўлган қаторлар.
  List<Widget> _effects(BuildContext context) {
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    final out = <Widget>[];

    if (!alt.feasible) {
      out.add(const SizedBox(height: 6));
      out.add(Text(
        context.tr('ev_alt_unreachable'),
        key: const ValueKey('ev_alt_unreachable'),
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AvaLight.danger),
      ));
      return out;
    }

    final arrival = alt.arrivalSocPercent;
    if (arrival != null) {
      final d = alt.arrivalDeltaPercent;
      out.add(const SizedBox(height: 6));
      out.add(Text(
        '${context.tr('ev_trip_arrival')} $arrival%'
        '${d == null ? '' : ' (${_signedInt(d)}%)'}',
        key: const ValueKey('ev_alt_arrival'),
        style: style,
      ));
    }

    final stopsDelta = alt.stopCountDelta;
    if (stopsDelta != null && stopsDelta != 0 && alt.stopCount != null) {
      out.add(const SizedBox(height: 2));
      out.add(Text(
        context
            .tr('ev_alt_stops')
            .replaceAll('{n}', '${alt.stopCount}')
            .replaceAll('{d}', _signedInt(stopsDelta)),
        key: const ValueKey('ev_alt_stops'),
        style: style,
      ));
    }

    final minutes = alt.chargeMinutesDelta;
    if (minutes != null) {
      out.add(const SizedBox(height: 2));
      out.add(Text(
        context
            .tr('ev_alt_time_delta')
            .replaceAll('{d}', evAltSignedMinutes(context, minutes)),
        key: const ValueKey('ev_alt_time_delta'),
        style: style,
      ));
    }
    return out;
  }
}

class _Tag extends StatelessWidget {
  const _Tag({super.key, required this.text, required this.bg, required this.fg});

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
