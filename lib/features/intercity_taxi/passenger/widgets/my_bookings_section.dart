import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../models/intercity_booking.dart';
import '../controllers/my_bookings_controller.dart';

/// Entry-экраннинг тепасига жойлашадиган **«Сизнинг бронларингиз»** карти.
///
/// Фойдаланувчининг faol (pending/confirmed) бронлари кўрсатилади. Бўш бўлса —
/// hech нарса. Бекор қилиш ва ҳайдовчига қўнғироқ имкониятлари бор.
class MyBookingsSection extends StatelessWidget {
  const MyBookingsSection({super.key, required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Consumer<MyBookingsController>(
      builder: (context, c, _) {
        if (c.isLoading) return const SizedBox.shrink();
        final list = c.activeBookings;
        if (list.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: primaryColor.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
            border: Border.all(color: primaryColor.withOpacity(0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.bookmark, color: primaryColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Сизнинг бронларингиз',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryColor),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${list.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryColor)),
                ),
              ]),
              const SizedBox(height: 8),
              ...list.map((b) => _BookingRow(
                    booking: b,
                    primaryColor: primaryColor,
                    onCall: () => _callPhone(b.driverPhone),
                    onCancel: () =>
                        _confirmCancel(context, b, c, primaryColor),
                  )),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callPhone(String phone) async {
    if (phone.isEmpty) return;
    final url = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _confirmCancel(
    BuildContext context,
    IntercityBooking b,
    MyBookingsController c,
    Color primaryColor,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Бронни бекор қилиш?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '${b.routeShort}\n${b.passengers} ўрин · ${formatPrice(b.totalAmount)} сўм\n\nҲайдовчига хабар берилади ва ўриничизни бошқага бўш қилади.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ҳа, бекор',
                  style: TextStyle(color: Color(0xFFE53935)))),
        ],
      ),
    );
    if (ok == true) {
      await c.cancel(b.id);
    }
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({
    required this.booking,
    required this.primaryColor,
    required this.onCall,
    required this.onCancel,
  });

  final IntercityBooking booking;
  final Color primaryColor;
  final VoidCallback onCall;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final dep = booking.departureTime;
    final depText =
        '${dep.day}.${dep.month.toString().padLeft(2, "0")} ${dep.hour.toString().padLeft(2, "0")}:${dep.minute.toString().padLeft(2, "0")}';
    final isPending = booking.status == IntercityBookingStatus.pending;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPending ? Icons.hourglass_top : Icons.check_circle,
            size: 18,
            color: isPending ? Colors.orange : primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.routeShort,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    '${booking.driverName} · $depText · #${booking.shortRef}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ]),
        ),
        IconButton(
          onPressed: onCall,
          icon: Icon(Icons.call, color: primaryColor, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Қўнғироқ',
        ),
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close, color: Color(0xFFE53935), size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Бекор қилиш',
        ),
      ]),
    );
  }
}
