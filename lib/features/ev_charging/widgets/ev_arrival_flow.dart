import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
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
      title: context.tr('ev_arrival_title'),
      body: context.tr('ev_arrival_body'),
      yes: context.tr('ev_arrival_yes'),
      no: context.tr('ev_arrival_no'),
    );
    if (isHere == null || !context.mounted) return;

    if (isHere) {
      await repository.confirmStation(station.id);
      if (!context.mounted) return;
      final wantsCheck = await _confirm(
        context,
        title: context.tr('ev_confirmed_title'),
        body: context.tr('ev_confirmed_body'),
        yes: context.tr('ev_confirmed_check'),
        no: context.tr('ev_confirmed_later'),
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
      title: context.tr('ev_not_found_title'),
      body: context.tr('ev_not_found_body'),
      yes: context.tr('ev_not_found_report'),
      no: context.tr('cancel'),
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
          title: Text(ctx.tr('ev_report_thanks_title')),
          content: Text(ctx.tr('ev_report_thanks_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tr('ev_report_thanks_ok')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('ev_report_limit_reached')),
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
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text(yes),
          ),
        ],
      ),
    );
  }
}
