import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../repositories/taxi_billing_repository.dart';
import 'taxi_agreement_sheet.dart';

/// Шаҳарлараро рейс эълонининг ягона тўлов оқими (D-TAXI-13): ҳақ →
/// келишув → тасдиқ → тўлов. Рейс очишнинг барча йўллари (тез бошлаш
/// ойнаси, «қайтиш рейси») шу оқимдан ўтади — тўловсиз эълон йўли қолмайди.
class IntercityBillingFlow {
  IntercityBillingFlow({TaxiBillingRepository? repository})
      : _billing = repository ?? TaxiBillingRepository();

  final TaxiBillingRepository _billing;

  /// `published` бўлса `taxi_trips` id, акс ҳолда `null` (хабар кўрсатилган).
  Future<String?> publish(
    BuildContext context, {
    required Color primaryColor,
    required int farePerSeat,
    required String from,
    required String to,
    required String scheduleDate,
    required String startTime,
    required int seats,
    required DateTime departureAt,
  }) async {
    TaxiFeeQuote quote;
    try {
      quote = await _billing.quote(farePerSeat: farePerSeat);
    } on TaxiBillingException catch (e) {
      if (context.mounted) _snack(context, _message(context, e.reason));
      return null;
    } catch (_) {
      if (context.mounted) _snack(context, context.tr('taxi_publish_failed'));
      return null;
    }
    if (!context.mounted) return null;

    // D-TAXI-24.1: келишув starter тугагач — тизим ўзи тақдим қилади.
    if (quote.agreementRequired) {
      final ok = await showTaxiAgreementSheet(
        context,
        version: quote.agreementVersion ?? 1,
        primaryColor: primaryColor,
        repository: _billing,
      );
      if (!ok || !context.mounted) return null;
      try {
        quote = await _billing.quote(farePerSeat: farePerSeat);
      } on TaxiBillingException catch (e) {
        if (context.mounted) _snack(context, _message(context, e.reason));
        return null;
      } catch (_) {
        if (context.mounted) _snack(context, context.tr('taxi_publish_failed'));
        return null;
      }
    }
    if (!context.mounted) return null;
    if (!quote.allowed) {
      _snack(context, _message(context, quote.reason));
      return null;
    }
    if (quote.feeAmount > 0 && !quote.sufficient) {
      _snack(context, context.tr('taxi_fee_insufficient'));
      return null;
    }

    // D-TAXI-22: ҳақ бор бўлса ҳайдовчи суммани ОЛДИНДАН кўриб тасдиқлайди.
    // Ҳақсиз (starter) рейсда диалог фақат starter тугашига 3 кун қолганда
    // чиқади (эга, 2026-10-15); `starterNotice` ни сервер белгилайди.
    if (quote.feeAmount > 0 || quote.starterNotice) {
      final confirmed = await _confirmFee(context, quote, primaryColor);
      if (!confirmed || !context.mounted) return null;
    }

    final pos = await _lastKnownPosition();
    try {
      final res = await _billing.publish(
        farePerSeat: farePerSeat,
        from: from,
        to: to,
        scheduleDate: scheduleDate,
        startTime: startTime,
        seats: seats,
        departureAt: departureAt,
        driverLat: pos?.latitude,
        driverLng: pos?.longitude,
        locationAccuracy: pos?.accuracy,
      );
      if (res.published) return res.tripId;
      // D-TAXI-23: ҳамён етмади — эълон чиқмайди.
      if (context.mounted) _snack(context, context.tr('taxi_fee_insufficient'));
      return null;
    } on TaxiBillingException catch (e) {
      if (context.mounted) _snack(context, _message(context, e.reason));
      return null;
    } catch (_) {
      if (context.mounted) _snack(context, context.tr('taxi_publish_failed'));
      return null;
    }
  }

  /// Тўлов ўтди, лекин рейс рўйхатга тушмади — комиссия қайтарилади
  /// (`cancelTaxiTrip` идемпотент). Хато бўлса ҳам асл хатони яширмаймиз.
  Future<void> refundQuietly(String tripId) async {
    if (tripId.isEmpty) return;
    try {
      await _billing.cancel(tripId: tripId);
    } catch (_) {}
  }

  Future<Position?> _lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  String _message(BuildContext context, String reason) {
    switch (reason) {
      case 'taxi_verification_required':
        return context.tr('taxi_verification_required');
      case 'taxi_not_allowed':
      case 'no_capability':
      case 'no_user':
        return context.tr('taxi_not_allowed');
      case 'agreement_required':
        return context.tr('taxi_agreement_title');
      default:
        return context.tr('taxi_publish_failed');
    }
  }

  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(msg),
    ));
  }

  String _fmtSum(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<bool> _confirmFee(
    BuildContext context,
    TaxiFeeQuote quote,
    Color primaryColor,
  ) async {
    final fee = quote.feeAmount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('taxi_fee_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fee > 0
                  ? '${_fmtSum(fee)} сўм'
                  : ctx.tr('taxi_fee_free_starter'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(ctx.tr('taxi_fee_formula_note'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (fee > 0 && quote.walletBalance != null) ...[
              const SizedBox(height: 8),
              Text(
                '${ctx.tr('taxi_fee_wallet_balance')}: ${_fmtSum(quote.walletBalance!)} сўм',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(fee > 0
                ? ctx.tr('taxi_fee_pay_publish').replaceAll('{fee}', _fmtSum(fee))
                : ctx.tr('confirm')),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
