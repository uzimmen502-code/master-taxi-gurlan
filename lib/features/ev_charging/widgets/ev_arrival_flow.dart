import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/ev_charging_report.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../screens/add_ev_station_screen.dart';

/// 16–21-bandlar: yetib kelganda avtomatik tekshirish oqimi —
/// "Ҳа, шу ерда" → "Тасдиқланди" → "Текшириш"/"Кейин";
/// "Йўқ, нуқта йўқ" → "Хабар бериш"/"Бекор қилиш".
class EvArrivalFlow {
  const EvArrivalFlow._();

  static Future<void> show(
    BuildContext context, {
    required EvChargingStation station,
    required EvStationRepository repository,
  }) async {
    final isHere = await _confirm(
      context,
      title: '⚡ Зарядлаш нуқтасига етиб келдингиз',
      body: 'Геолокацияда хатолик бўлиши мумкин. Нуқта шу ердами?',
      yes: 'Ҳа, шу ерда',
      no: 'Йўқ, нуқта йўқ',
    );
    if (isHere == null || !context.mounted) return;

    if (isHere) {
      await repository.confirmStation(station.id);
      if (!context.mounted) return;
      final wantsCheck = await _confirm(
        context,
        title: '✅ Тасдиқланди',
        body: 'Зарядлаш нуқтаси жойида эканлиги тасдиқланди. '
            'Маълумотларни текширишни хоҳлайсизми?',
        yes: 'Текшириш',
        no: 'Кейин',
      );
      if (wantsCheck == true && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddEvStationScreen(editing: station),
          ),
        );
      }
      return;
    }

    final wantsReport = await _confirm(
      context,
      title: '⚠️ Зарядлаш нуқтаси топилмади',
      body: 'Бу жойда зарядлаш нуқтаси йўқлиги ҳақида хабар беришингиз мумкин.',
      yes: 'Хабар бериш',
      no: 'Бекор қилиш',
    );
    if (wantsReport != true || !context.mounted) return;

    try {
      await repository.reportStation(
        station.id,
        reason: EvReportReason.stationNotFound,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ Раҳмат!'),
          content: const Text(
              'Хабарингиз қабул қилинди ва маълумотни текшириш учун юборилди.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Яхши'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Хабар юборилмади — бу нуқта учун лимитга етдингиз.'),
        ),
      );
    }
  }

  static Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String yes,
    required String no,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(no),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
            ),
            child: Text(yes),
          ),
        ],
      ),
    );
  }
}
