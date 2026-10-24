import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/intercity_booking.dart';
import '../../intercity_driver_alert_text.dart';

/// Янги pending брон — қабул/рад диалоги (овозли push билан бирга).
///
/// Битта асосий амал — «Қабул қилиш»; «Қўнғироқ» иккинчи даражали (контур),
/// «Рад этиш» — хавфли амал ранги билан алоҳида.
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
        const ExcludeSemantics(
          child: Icon(Icons.notifications_active, color: AvaLight.warn),
        ),
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
          Text(routeDisplay, style: const TextStyle(fontSize: 14)),
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
            style: const TextStyle(fontSize: 13, color: AvaLight.ink2),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AvaLight.brandSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AvaLight.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(Icons.phone_in_talk_outlined,
                      size: 18, color: AvaLight.brandText),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ctx.tr('call_passenger_hint').replaceAll(
                      '{phone}',
                      formatPhoneForCallHint(booking.userPhone),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AvaLight.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: AvaLight.danger,
          ),
          onPressed: () async {
            Navigator.pop(ctx);
            await onReject();
          },
          child: Text(ctx.tr('reject_booking')),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => callPhone(booking.userPhone),
          icon: const Icon(Icons.call, size: 18),
          label: Text(ctx.tr('call_lowercase')),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await onAccept();
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.button,
            foregroundColor: AppColors.onPrimary,
            minimumSize: const Size(0, 48),
          ),
          child: Text(ctx.tr('accept_booking')),
        ),
      ],
    ),
  );
}
