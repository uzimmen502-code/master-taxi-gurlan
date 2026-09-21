import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_station.dart';

/// 13-band: faqat mavjud maydonlar ko'rsatiladi, "jamoa tomonidan kiritilgan"
/// ishonchlilik ogohlantirishi doimiy — narx/quvvat mavjud bo'lganda ayniqsa
/// ko'rinadigan (170-band).
class EvStationCard extends StatelessWidget {
  const EvStationCard({
    super.key,
    required this.station,
    required this.distanceKm,
    required this.onNavigate,
  });

  final EvChargingStation station;
  final double? distanceKm;
  final VoidCallback onNavigate;

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
            Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                const Text(
                  'Зарядлаш нуқтаси',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (distanceKm != null) _line('📍', '${distanceKm!.toStringAsFixed(1)} км'),
            if (station.hasChargingType)
              _line('⚡', station.chargingTypes.join(' + ')),
            if (station.hasConnectors) _line('🔌', station.connectors.join(', ')),
            if (station.hasPowerKw) _line('🔋', '${station.powerKw} kW'),
            if (station.hasPrice)
              _line('💰', '1 kWh — ${station.price} сўм${hasPriceOrPower ? " *" : ""}'),
            if (station.hasOperatorName) _line('🏢', station.operatorName!),
            if (station.hasNote) _line('📝', station.note!),
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
}
