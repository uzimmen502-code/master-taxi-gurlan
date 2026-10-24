import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/taxi_billing_reason.dart';
import '../../repositories/taxi_billing_repository.dart';
import '../../utils/intercity_departure.dart';
import 'taxi_agreement_sheet.dart';
import 'wallet_topup_ui.dart';

/// Шаҳарлараро рейс эълонининг ягона тўлов оқими (D-TAXI-13): ҳақ →
/// келишув → тасдиқ → тўлов. Рейс очишнинг барча йўллари (тез бошлаш
/// ойнаси, «қайтиш рейси») шу оқимдан ўтади — тўловсиз эълон йўли қолмайди.
class IntercityBillingFlow {
  IntercityBillingFlow({
    TaxiBillingRepository? repository,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  })  : _billing = repository ?? TaxiBillingRepository(),
        _newRequestId = requestIdFactory ?? generateRequestId,
        _now = clock ?? DateTime.now;

  final TaxiBillingRepository _billing;
  final String Function() _newRequestId;
  final DateTime Function() _now;

  /// `publishTaxiTrip.requestId` — server kontrakti: 8..64 belgi, `[A-Za-z0-9_-]`.
  static String generateRequestId() {
    final r = Random.secure();
    final b = StringBuffer('pub_');
    for (var i = 0; i < 24; i++) {
      b.write(r.nextInt(36).toRadixString(36));
    }
    return b.toString();
  }

  // Idempotentlik: bitta "e'lon qilish harakati" (bir xil ma'lumot) uchun
  // bitta `requestId`. Javob ANIQ kelsa (muvaffaqiyat yoki server rad etdi)
  // harakat tugagan — keyingi bosish YANGI id oladi. Javob noaniq bo'lsa
  // (tarmoq uzildi, timeout, server xatosi) so'rov serverda bajarilgan
  // bo'lishi mumkin — qayta urinishda AYNI id yuboriladi, shunda server
  // komissiyani ikkinchi marta yechmaydi. Ma'lumot (narx/vaqt/yo'nalish...)
  // o'zgarsa — bu yangi harakat, id yangilanadi.
  String? _requestId;
  String? _requestFingerprint;

  /// Shu harakat uchun id (ma'lumot o'zgargan bo'lsa yangisi).
  String _requestIdFor(String fingerprint) {
    if (_requestId == null || _requestFingerprint != fingerprint) {
      _requestId = _newRequestId();
      _requestFingerprint = fingerprint;
    }
    return _requestId!;
  }

  void _finishAttempt() {
    _requestId = null;
    _requestFingerprint = null;
  }

  /// Javob noaniqmi (so'rov serverda bajarilgan bo'lishi mumkin)?
  static bool _isAmbiguousFailure(Object e) {
    if (e is TaxiBillingException) {
      const ambiguous = {
        'unavailable',
        'deadline-exceeded',
        'internal',
        'unknown',
        'cancelled',
        'aborted',
      };
      return ambiguous.contains(e.code);
    }
    return true; // Firebase bo'lmagan xato (tarmoq/parse) — noaniq.
  }

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
    // O'tib ketgan vaqt bilan to'lov oqimiga kirmaymiz (serverda ham
    // `departure_in_past` tekshiruvi bor; bu — oldindan sodda xabar).
    if (IntercityDeparture.isAtInPast(departureAt, _now())) {
      _snack(context, context.tr('taxi_reason_departure_in_past'));
      return null;
    }
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
      final have = quote.walletBalance;
      _snack(context, context.tr('taxi_fee_insufficient'),
          topUp: true, suggested: have == null ? null : quote.feeAmount - have);
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
    final requestId = _requestIdFor(
        '$farePerSeat|$from|$to|$scheduleDate|$startTime|$seats|${departureAt.toUtc().toIso8601String()}');
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
        requestId: requestId,
      );
      // Server aniq javob berdi — harakat tugadi (keyingi bosish yangi id).
      _finishAttempt();
      if (res.published) return res.tripId;
      // D-TAXI-23: ҳамён етмади — эълон чиқмайди.
      if (context.mounted) _snack(context, context.tr('taxi_fee_insufficient'), topUp: true);
      return null;
    } on TaxiBillingException catch (e) {
      if (!_isAmbiguousFailure(e)) _finishAttempt();
      if (context.mounted) _snack(context, _message(context, e.reason));
      return null;
    } catch (_) {
      // Noaniq: id saqlanadi — qayta urinish komissiyani ikkilantirmaydi.
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

  /// Server `details.reason` → foydalanuvchi matni (barcha ma'lum sabablar
  /// `taxiReasonKey` xaritasida, noma'lum → umumiy matn).
  String _message(BuildContext context, String reason) =>
      context.tr(taxiReasonKey(reason));

  /// [topUp] — ҳамён етмаганда «Ҳамённи тўлдириш» тугмаси (аввал фақат
  /// матн эди, ҳайдовчи тўлдириш йўлини топа олмасди).
  void _snack(BuildContext context, String msg, {bool topUp = false, int? suggested}) {
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(msg),
      action: topUp
          ? SnackBarAction(
              label: context.tr('wlt_topup_btn'),
              textColor: Colors.white,
              onPressed: () => openWalletTopUp(
                navigator,
                suggestedAmount: (suggested != null && suggested > 0) ? suggested : null,
              ),
            )
          : null,
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
                  ? '${_fmtSum(fee)} ${ctx.tr('currency_sum')}'
                  : ctx.tr('taxi_fee_free_starter'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(ctx.tr('taxi_fee_formula_note'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            if (fee > 0 && quote.walletBalance != null) ...[
              const SizedBox(height: 8),
              Text(
                '${ctx.tr('taxi_fee_wallet_balance')}: ${_fmtSum(quote.walletBalance!)} ${ctx.tr('currency_sum')}',
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
