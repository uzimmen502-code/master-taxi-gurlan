import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../models/intercity_ride.dart';
import '../controllers/intercity_taxi_controller.dart';
import 'loyal_client_badge.dart';

/// Бронь тасдиқлаш sheet'и — ҳақиқий бронь яратишдан **олдин** кўрсатилади.
///
/// `ride` танланиши билан controllerда `loadLoyaltyFor(ride)` чақирилади ва
/// «Доимий мижоз» badge кўрсатилади (агар фойдаланувчи шу ҳайдовчида
/// илгари brон қилган бўлса).
class BookingConfirmationSheet extends StatefulWidget {
  const BookingConfirmationSheet({
    super.key,
    required this.ride,
    required this.primaryColor,
    required this.greenColor,
    required this.redColor,
  });

  final IntercityRide ride;
  final Color primaryColor;
  final Color greenColor;
  final Color redColor;

  @override
  State<BookingConfirmationSheet> createState() =>
      _BookingConfirmationSheetState();
}

class _BookingConfirmationSheetState extends State<BookingConfirmationSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IntercityTaxiController>().loadLoyaltyFor(widget.ride);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<IntercityTaxiController>();
    final ride = widget.ride;
    final totalAmount = ride.price * c.passengers;
    final dep = ride.departureTime;
    final depText =
        '${dep.hour.toString().padLeft(2, "0")}:${dep.minute.toString().padLeft(2, "0")}';

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: widget.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    Icon(Icons.event_seat, color: widget.primaryColor, size: 22)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Бронни тасдиқланг',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (c.loyaltyForSelected != null)
              LoyalClientBadge(stats: c.loyaltyForSelected, compact: true),
          ]),
          if (c.loyaltyForSelected != null &&
              (c.loyaltyForSelected!.isLoyal ||
                  c.loyaltyForSelected!.isVip)) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: LoyalClientBadge(stats: c.loyaltyForSelected),
            ),
          ],
          const SizedBox(height: 16),
          _row(Icons.person, 'Ҳайдовчи', ride.driverName),
          const Divider(height: 18),
          _row(Icons.directions_car, 'Машина', ride.carNumber),
          const Divider(height: 18),
          _row(Icons.access_time, 'Жўнаш', depText),
          const Divider(height: 18),
          _row(Icons.airline_seat_recline_normal, 'Йўловчилар',
              '${c.passengers} та'),
          const Divider(height: 18),
          _row(
              Icons.payments,
              'Жами',
              '${formatPrice(totalAmount)} сўм',
              valueColor: const Color(0xFFE65100),
              valueBold: true),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: c.isBooking ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Йўқ'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: c.isBooking
                    ? null
                    : () async {
                        final booking = await c.bookRide(ride);
                        if (!context.mounted) return;
                        // Faqat muvaffaqiyatda yopamiz — xato bo'lsa
                        // foydalanuvchi snackbar'ni ko'rib qayta urinishi mumkin.
                        if (booking != null) {
                          Navigator.pop(context, booking);
                        }
                      },
                icon: c.isBooking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(c.isBooking ? 'Юкланмоqда...' : 'Тасдиқлаш'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor, bool valueBold = false}) {
    return Row(children: [
      Icon(icon, size: 18, color: widget.primaryColor),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: valueBold ? FontWeight.bold : FontWeight.w600,
          color: valueColor ?? const Color(0xFF1A1A2E),
        ),
      ),
    ]);
  }
}

/// Бронь муваффақиятли яратилгандан сўнг кўрсатиладиган тасдиқ sheet'и.
class BookingSuccessSheet extends StatelessWidget {
  const BookingSuccessSheet({
    super.key,
    required this.booking,
    required this.primaryColor,
    required this.greenColor,
    required this.onCall,
  });

  final IntercityBooking booking;
  final Color primaryColor;
  final Color greenColor;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final dep = booking.departureTime;
    final depText =
        '${dep.hour.toString().padLeft(2, "0")}:${dep.minute.toString().padLeft(2, "0")}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        Container(
          width: 64,
          height: 64,
          decoration:
              BoxDecoration(color: greenColor.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(Icons.check_circle, color: greenColor, size: 40),
        ),
        const SizedBox(height: 12),
        const Text('Брон қабул қилинди!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Брон #${booking.shortRef}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        _row(Icons.person, 'Ҳайдовчи', booking.driverName),
        const Divider(height: 18),
        _row(Icons.directions_car, 'Машина', booking.carNumber),
        const Divider(height: 18),
        _row(Icons.access_time, 'Жўнаш', depText),
        const Divider(height: 18),
        _row(Icons.payments, 'Йўлкира',
            '${formatPrice(booking.totalAmount)} сўм'),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: greenColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: greenColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: greenColor, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Ҳайдовчига хабар юборилди. Бронингиз "Сизнинг бронларингиз" рўйхатида.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Қўнғироқ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('OK',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: primaryColor),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      const Spacer(),
      Text(value,
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }
}
