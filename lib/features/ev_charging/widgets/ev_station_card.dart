import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_station.dart';

/// 13-band: faqat mavjud maydonlar ko'rsatiladi, "jamoa tomonidan kiritilgan"
/// ishonchlilik ogohlantirishi doimiy — narx/quvvat mavjud bo'lganda ayniqsa
/// ko'rinadigan (170-band).
///
/// 2026-09-22: очиқ манба импорти учун ном + «Очиқ манбадан • ...» белгиси
/// қўшилди ([EvChargingStation.isImported]) — фойдаланувчи манба (OSM/TOK
/// BOR/Yashil Energiya) кимлигини кўради, лекин бу ҳам жамоа огоҳлантириши
/// каби «жойида текширилмаган» деган маънони англатади.
class EvStationCard extends StatelessWidget {
  const EvStationCard({
    super.key,
    required this.station,
    required this.distanceKm,
    required this.onNavigate,
    this.onSetOccupancy,
  });

  final EvChargingStation station;
  final double? distanceKm;
  final VoidCallback onNavigate;

  /// «Ҳозир банд / бўш» — жамоа хабари. `null` бўлса тугмалар йўқ.
  final Future<void> Function({required bool busy})? onSetOccupancy;

  @override
  Widget build(BuildContext context) {
    final hasPriceOrPower = station.hasPrice || station.hasPowerKw;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onSetOccupancy != null) ...[
              _OccupancyRow(
                state: station.occupancyState,
                onSet: onSetOccupancy!,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    station.hasName ? station.name! : 'Зарядлаш нуқтаси',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (station.isImported) ...[
              const SizedBox(height: 4),
              Text(
                'Очиқ манбадан${station.sourceProvider?.isNotEmpty == true ? " • ${station.sourceProvider}" : ""}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ],
            if (station.isPaidListing) ...[
              const SizedBox(height: 4),
              const Text(
                '💳 Расмий рўйхат (пуллик қўшилган)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AvaLight.ok,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (distanceKm != null) _line('📍', '${distanceKm!.toStringAsFixed(1)} км'),
            if (station.region?.isNotEmpty == true) _line('🗺️', station.region!),
            if (station.hasAddress) _line('🏠', station.address!),
            if (station.hasChargingType)
              _line('⚡', station.chargingTypes.join(' + ')),
            if (station.hasConnectors) _line('🔌', station.connectors.join(', ')),
            if (station.hasPowerKw) _line('🔋', '${station.powerKw} kW'),
            if (!station.hasPowerKw && station.hasPowerRatingsKw)
              _line('🔋', 'Қувват вариантлари: ${station.powerRatingsKw.join(" / ")} kW'),
            if (station.hasSitePowerKw)
              _line('🏭', 'Майдон умумий қуввати: ${station.sitePowerKw} kW'),
            if (station.hasPrice)
              _line('💰', '1 kWh — ${station.price} сўм${hasPriceOrPower ? " *" : ""}'),
            if (station.hasOperatorName) _line('🏢', station.operatorName!),
            if (station.hasWorkingHours) _line('🕒', station.workingHours!),
            if (station.hasPhone) _linkLine('📞', station.phone!, 'tel:${station.phone}'),
            if (station.hasWebsite) _linkLine('🌐', station.website!, station.website!),
            if (station.hasNote) _line('📝', station.note!),
            if (station.hasSourceReportedStatus)
              _line('ℹ️', 'Манба хабари (реал вақт эмас): ${station.sourceReportedStatus}'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.black54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasPriceOrPower
                        ? 'ℹ️ Маълумотлар жамоа (foydalanuvchilar) tomonidan kiritilgan, aniqligiga kafolat berilmaydi.*'
                        : 'ℹ️ Маълумотлар жамоа (foydalanuvchilar) tomonidan kiritilgan, aniqligiga kafolat berilmaydi.',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Йўл кўрсатиш'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String emoji, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
          ],
        ),
      );

  Widget _linkLine(String emoji, String text, String url) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: InkWell(
          onTap: () => launchUrl(
            Uri.parse(url.startsWith('http') || url.startsWith('tel:') ? url : 'https://$url'),
            mode: LaunchMode.externalApplication,
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
}

/// «Ҳозир қандай?» — жамоа белгиси.
///
/// Бу `status` (станция умуман ишлайдими) ДАН БОШҚА нарса: у ҳозирги
/// бандликни билдиради ва `EvChargingStation.occupancyTtl` (30 дақиқа)
/// давомида амал қилади.
class _OccupancyRow extends StatelessWidget {
  const _OccupancyRow({required this.state, required this.onSet});

  final String state;
  final Future<void> Function({required bool busy}) onSet;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final (label, tone) = switch (state) {
      'free' => (context.tr('home_ev_free'), c.ok),
      'busy' => (context.tr('home_ev_busy'), c.warn),
      _ => (context.tr('home_ev_unknown'), c.ink3),
    };

    Future<void> mark(BuildContext ctx, {required bool busy}) async {
      await onSet(busy: busy);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(ctx.tr('ev_occupancy_saved'))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 10, color: tone),
            const SizedBox(width: 6),
            Text(
              label,
              style: AvaText.productName.copyWith(color: tone),
            ),
            const Spacer(),
            Text(
              context.tr('ev_occupancy_question'),
              style: AvaText.caption.copyWith(color: c.ink3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => mark(context, busy: false),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(context.tr('ev_mark_free')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ok,
                  side: BorderSide(color: c.ok),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => mark(context, busy: true),
                icon: const Icon(Icons.hourglass_bottom_rounded, size: 18),
                label: Text(context.tr('ev_mark_busy')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.warn,
                  side: BorderSide(color: c.warn),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}