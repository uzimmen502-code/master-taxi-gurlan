import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/intercity_booking.dart';
import '../../intercity_driver_alert_text.dart';

/// Янги pending брон — қабул/рад диалоги (овозли push билан бирга).
Future<void> showIntercityBookingRequestDialog({
  required BuildContext context,
  required IntercityBooking booking,
  required String routeDisplay,
  required Future<void> Function() onAccept,
  required Future<void> Function() onReject,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.notifications_active, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(ctx.tr('intercity_new_booking'))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ctx.trMsg(booking.userName),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(routeDisplay, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            ctx
                .tr('booking_seats_amount')
                .replaceAll('{passengers}', '${booking.passengers}')
                .replaceAll('{amount}', formatPrice(booking.totalAmount))
                .replaceAll('{sum}', ctx.tr('sum')),
          ),
          const SizedBox(height: 8),
          Text(
            ctx.tr('pickup_line').replaceAll(
              '{address}',
              booking.hasPickupAddress
                  ? booking.pickupAddress
                  : ctx.tr('pickup_not_entered'),
            ),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              ctx.tr('call_passenger_hint').replaceAll(
                '{phone}',
                formatPhoneForCallHint(booking.userPhone),
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await onReject();
          },
          child: Text(ctx.tr('reject_booking'),
              style: const TextStyle(color: Colors.red)),
        ),
        FilledButton.icon(
          onPressed: () => callPhone(booking.userPhone),
          icon: const Icon(Icons.call, size: 18),
          label: const Text('Қўнғироқ'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await onAccept();
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
          child: Text(ctx.tr('accept_booking')),
        ),
      ],
    ),
  );
}
