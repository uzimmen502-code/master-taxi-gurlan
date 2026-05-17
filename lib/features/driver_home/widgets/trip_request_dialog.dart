import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/trip_request.dart';
import '../../../utils/app_theme.dart';

/// Янги буюртма келганда чиқадиган диалог.
///
/// Қайтариш: `'accept'` | `'reject'` | `null` (диалог автоматик ёпилди).
Future<String?> showTripRequestDialog(
  BuildContext context,
  TripRequest ride,
) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TripRequestDialog(ride: ride),
  );
}

class _TripRequestDialog extends StatelessWidget {
  const _TripRequestDialog({required this.ride});

  final TripRequest ride;

  static const _blue = Color(0xFF1565C0);
  static const _green = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);
  static const _red = Color(0xFFB71C1C);

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppText.bodySmall, color: Colors.grey)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: const [
        Icon(Icons.person_pin, color: _blue, size: 26),
        SizedBox(width: 8),
        Text('Янги буюртма!',
            style: TextStyle(fontSize: AppText.titleMedium)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('📍 Қаердан:', ride.from),
          if (ride.to.isNotEmpty) _infoRow('🏁 Қаерга:', ride.to),
          _infoRow('📞 Телефон:', ride.userPhone),
          _infoRow('🚕 Тури:', ride.typeLabel),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: Stream.periodic(
                    const Duration(seconds: 1), (i) => ride.secsLeft - i)
                .cast<int>()
                .take(ride.secsLeft),
            builder: (ctx, snap) {
              final secs = snap.data ?? ride.secsLeft;
              final color = secs > 60 ? _green : secs > 30 ? _orange : _red;
              final m = secs ~/ 60;
              final s = secs % 60;
              return Row(children: [
                const Icon(Icons.timer, size: 14),
                const SizedBox(width: 4),
                Text('$m:${s.toString().padLeft(2, '0')} қолди',
                    style: TextStyle(
                        fontSize: AppText.bodyMedium,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ]);
            },
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () async {
            if (ride.userPhone.isEmpty) return;
            final url = Uri(scheme: 'tel', path: ride.userPhone);
            if (await canLaunchUrl(url)) await launchUrl(url);
          },
          icon: const Icon(Icons.call, color: _green, size: 28),
          tooltip: 'Қўнғироқ',
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('reject'),
          child: const Text('РАД ЭТИШ',
              style: TextStyle(
                  color: Colors.red, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop('accept'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          child: const Text('ҚАБУЛ',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
