import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../repositories/schedules_repository.dart';
import '../../repositories/taxi_billing_repository.dart';
import 'taxi_agreement_sheet.dart';
import '../../utils/intercity_places.dart';

/// Shaharlararo haydovchi uchun tez ishga chiqish bottom sheet.
///
/// `DriverScheduleScreen` (to'liq ekran) o'rniga — ekran o'tishsiz, faqat
/// bottom sheet. Muvaffaqiyatli saqlansa `Navigator.pop(context, true)`.
/// Saqlash mantig'i `DriverScheduleController`dagi intercity oqimini takrorlaydi
/// (date/expiresAt/startTime/price/stops) va `SchedulesRepository`ni to'g'ridan
/// to'g'ri chaqiradi.
class IntercityQuickStartSheet extends StatefulWidget {
  const IntercityQuickStartSheet({
    super.key,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
    required this.seats,
    required this.primaryColor,
  });

  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  /// Avtomobil sig'imidan olingan o'rindiqlar (UI yo'q — auto).
  final int seats;
  final Color primaryColor;

  @override
  State<IntercityQuickStartSheet> createState() =>
      _IntercityQuickStartSheetState();
}

class _IntercityQuickStartSheetState extends State<IntercityQuickStartSheet> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  String _fromQuery = '';
  String _toQuery = '';
  bool _showFromSug = false;
  bool _showToSug = false;

  TimeOfDay _departure = const TimeOfDay(hour: 8, minute: 0);
  bool _departureIsTomorrow = false;
  bool _saving = false;

  late int _seats;

  /// Avtomobil sig'imi — yuqori chegara.
  int get _maxSeats => widget.seats > 0 ? widget.seats : 4;

  final _repo = SchedulesRepository();

  @override
  void initState() {
    super.initState();
    _seats = _maxSeats;
    _prefill();
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    final from = prefs.getString('route_from_intercity') ?? '';
    final to = prefs.getString('route_to_intercity') ?? '';
    final price = prefs.getString('intercity_price_intercity') ?? '';
    final tomorrow = prefs.getBool('intercity_departure_tomorrow') ?? false;
    final hour = prefs.getString('intercity_departure_hour') ?? '';
    if (!mounted) return;
    setState(() {
      _fromCtrl.text = from;
      _toCtrl.text = to;
      _priceCtrl.text = price;
      _departureIsTomorrow = tomorrow;
      final parts = hour.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          _departure = TimeOfDay(hour: h, minute: m);
        }
      }
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(msg),
    ));
  }

  final TaxiBillingRepository _billing = TaxiBillingRepository();

  String _fmtSum(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Oxirgi ma'lum joylashuv — tez, ruxsat so'ramaydi. Bo'lmasa `null`:
  /// server mismatch'ni «signal» deb oladi, reysni to'xtatmaydi (D-TAXI-14).
  Future<Position?> _lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Komissiya → kelishuv → tasdiq → to'lov. `published` bo'lsa tripId,
  /// aks holda `null` (xabar allaqachon ko'rsatilgan).
  Future<String?> _publishWithBilling({
    required int farePerSeat,
    required String from,
    required String to,
    required String scheduleDate,
    required String startTime,
    required DateTime departureAt,
  }) async {
    TaxiFeeQuote quote;
    try {
      quote = await _billing.quote(farePerSeat: farePerSeat);
    } on TaxiBillingException catch (e) {
      _snack(_billingMessage(e.reason));
      return null;
    }
    if (!mounted) return null;

    // D-TAXI-24.1: kelishuv starter tugagach — tizim o'zi taqdim qiladi.
    // `verification_required` da ham (keyin admin kutiladi). Versiyani
    // server aytadi.
    if (quote.agreementRequired) {
      final ok = await showTaxiAgreementSheet(
        context,
        version: quote.agreementVersion ?? 1,
        primaryColor: widget.primaryColor,
        repository: _billing,
      );
      if (!ok || !mounted) return null;
      try {
        quote = await _billing.quote(farePerSeat: farePerSeat);
      } on TaxiBillingException catch (e) {
        _snack(_billingMessage(e.reason));
        return null;
      }
    }
    if (!mounted) return null;
    if (!quote.allowed) {
      _snack(_billingMessage(quote.reason));
      return null;
    }
    if (quote.feeAmount > 0 && !quote.sufficient) {
      _snack(context.tr('taxi_fee_insufficient'));
      return null;
    }

    // D-TAXI-22: haydovchi summani OLDINDAN ko'radi va tasdiqlaydi. Haqsiz
    // (starter) reysda dialog faqat starter tugashiga 3 kun qolganda
    // chiqadi (ega, 2026-10-15); `starterNotice` ni server belgilaydi.
    if (quote.feeAmount > 0 || quote.starterNotice) {
      final confirmed = await _confirmFee(quote);
      if (!confirmed || !mounted) return null;
    }

    final pos = await _lastKnownPosition();
    try {
      final res = await _billing.publish(
        farePerSeat: farePerSeat,
        from: from,
        to: to,
        scheduleDate: scheduleDate,
        startTime: startTime,
        seats: _seats,
        departureAt: departureAt,
        driverLat: pos?.latitude,
        driverLng: pos?.longitude,
        locationAccuracy: pos?.accuracy,
      );
      if (res.published) return res.tripId;
      // D-TAXI-23: wallet yetmadi — e'lon chiqmaydi.
      if (!mounted) return null;
      _snack(context.tr('taxi_fee_insufficient'));
      return null;
    } on TaxiBillingException catch (e) {
      _snack(_billingMessage(e.reason));
      return null;
    }
  }

  String _billingMessage(String reason) {
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

  Future<bool> _confirmFee(TaxiFeeQuote quote) async {
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
            style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departure,
    );
    if (picked != null && mounted) setState(() => _departure = picked);
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final fromText = _fromCtrl.text.trim();
    final toText = _toCtrl.text.trim();
    final priceText = _priceCtrl.text.trim().replaceAll(' ', '');

    if (fromText.isEmpty) {
      _snack('Қаердан — шаҳарни киритинг');
      return;
    }
    if (toText.isEmpty) {
      _snack('Қаерга — шаҳарни киритинг');
      return;
    }
    if (priceText.isEmpty) {
      _snack('Нархни киритинг');
      return;
    }

    final uid = phoneDigits(widget.driverPhone);
    if (uid.length < 9) {
      _snack('Телефон рақами топилмади');
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final now = DateTime.now();
      final day = _departureIsTomorrow
          ? DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 1))
          : DateTime(now.year, now.month, now.day);
      final dateStr =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final midnight = DateTime(day.year, day.month, day.day, 23, 59, 59);
      final price = int.tryParse(priceText) ?? 0;

      // D-TAXI-13: komissiya → to'lov → publish → shundan KEYIN ro'yxat.
      // Server `published` qaytarmasa reys yaratilmaydi. Sabablar
      // (`agreement_required`, `taxi_verification_required`,
      // `payment_required`) foydalanuvchiga sodda matn bilan ko'rsatiladi.
      final departureAt = DateTime(
          day.year, day.month, day.day, _departure.hour, _departure.minute);
      final billingTripId = await _publishWithBilling(
        farePerSeat: price,
        from: fromText,
        to: toText,
        scheduleDate: dateStr,
        startTime: _fmtTime(_departure),
        departureAt: departureAt,
      );
      if (billingTripId == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      await _repo.registerDriverSchedule(
        driverId: uid,
        taxiType: 'intercity',
        driverName: widget.driverName,
        driverPhone: widget.driverPhone,
        driverCar: widget.driverCar,
        driverPlate: widget.driverPlate,
        date: dateStr,
        expiresAt: midnight,
        seats: _seats,
        fromText: fromText,
        toText: toText,
        stops: [fromText, toText],
        direction: '',
        startTime: _fmtTime(_departure),
        price: price,
        billingTripId: billingTripId,
      );

      // Keyingi safar prefill uchun — DriverScheduleController bilan mos.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('route_from_intercity', fromText);
      await prefs.setString('route_to_intercity', toText);
      await prefs.setString('intercity_departure_hour', _fmtTime(_departure));
      await prefs.setBool('intercity_departure_tomorrow', _departureIsTomorrow);
      await prefs.setString('intercity_price_intercity', priceText);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      if (msg.contains('permission-denied')) {
        _snack('Firestore рухсати йўқ. Admin тасдиғи ва интернетни текширинг.');
      } else if (msg.contains('failed-precondition')) {
        _snack('РРЅРґРµРєСЃ кутилмоқда. Бир неча дақиқа сабр қилинг.');
      } else {
        _snack('Хатолик: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Material(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(children: [
                          const Icon(Icons.route,
                              color: AppColors.primaryText, size: 24),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Шаҳарлараро — ишга чиқиш',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _placeField(
                            ctrl: _fromCtrl,
                            hint: 'Қаердан (шаҳар)',
                            color: AppColors.primaryText,
                            showSug: _showFromSug,
                            query: _fromQuery,
                            onChanged: (q) => setState(() {
                              _fromQuery = q;
                              _showFromSug = q.trim().length >= 2;
                            }),
                            onSelected: (v) => setState(() {
                              _fromCtrl.text = v;
                              _fromQuery = v;
                              _showFromSug = false;
                            }),
                          ),
                          const SizedBox(height: 12),
                          _placeField(
                            ctrl: _toCtrl,
                            hint: 'Қаерга (шаҳар)',
                            color: AppColors.primaryText,
                            showSug: _showToSug,
                            query: _toQuery,
                            onChanged: (q) => setState(() {
                              _toQuery = q;
                              _showToSug = q.trim().length >= 2;
                            }),
                            onSelected: (v) => setState(() {
                              _toCtrl.text = v;
                              _toQuery = v;
                              _showToSug = false;
                            }),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Бугун'),
                                selected: !_departureIsTomorrow,
                                onSelected: (_) => setState(
                                    () => _departureIsTomorrow = false),
                                selectedColor: color.withValues(alpha: 0.18),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: !_departureIsTomorrow
                                      ? AppColors.primaryText
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Эртага'),
                                selected: _departureIsTomorrow,
                                onSelected: (_) => setState(
                                    () => _departureIsTomorrow = true),
                                selectedColor: color.withValues(alpha: 0.18),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _departureIsTomorrow
                                      ? AppColors.primaryText
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.access_time,
                                    size: 18, color: AppColors.primaryText),
                                label: Text(
                                  'Жўнаш: ${_fmtTime(_departure)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  side:
                                      BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _priceCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: InputDecoration(
                                  hintText: 'Нарх (сўм)',
                                  prefixIcon: const Icon(Icons.payments_outlined,
                                      color: AppColors.primaryText, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(children: [
                              const Icon(Icons.event_seat,
                                  color: AppColors.primaryText, size: 20),
                              const SizedBox(width: 8),
                              const Text('Ўриндиқлар',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              IconButton(
                                onPressed: _seats > 1
                                    ? () => setState(() => _seats--)
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                                color: AppColors.primaryText,
                                visualDensity: VisualDensity.compact,
                              ),
                              SizedBox(
                                width: 24,
                                child: Text('$_seats',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                onPressed: _seats < _maxSeats
                                    ? () => setState(() => _seats++)
                                    : null,
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppColors.primaryText,
                                visualDensity: VisualDensity.compact,
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _confirm,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.onPrimary))
                            : const Icon(Icons.check_circle_outline,
                                size: 22),
                        label:
                            Text(_saving ? 'Сақланмоқда...' : 'Тасдиқлаш'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: AppColors.onPrimary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeField({
    required TextEditingController ctrl,
    required String hint,
    required Color color,
    required bool showSug,
    required String query,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
  }) {
    final suggestions = IntercityPlaces.search(query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(Icons.location_on, color: color, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        if (showSug && suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length.clamp(0, 8),
              itemBuilder: (_, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(s, style: const TextStyle(fontSize: 13)),
                  onTap: () => onSelected(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
