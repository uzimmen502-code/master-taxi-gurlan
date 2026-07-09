import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../services/settlement_service.dart';

/// Intercity yo'lovchi — booking doc'dagi pending settlement'ni kuzatadi.
class IntercitySettlementWatcher extends StatefulWidget {
  const IntercitySettlementWatcher({
    super.key,
    required this.bookingId,
  });

  final String bookingId;

  @override
  State<IntercitySettlementWatcher> createState() =>
      _IntercitySettlementWatcherState();
}

class _IntercitySettlementWatcherState extends State<IntercitySettlementWatcher> {
  String? _handledSettlementId;

  @override
  Widget build(BuildContext context) {
    if (widget.bookingId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('intercity_bookings')
          .doc(widget.bookingId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? {};
        final settlementId = (data['settlementId'] ?? '').toString();
        final settlementState = (data['settlementState'] ?? '').toString();
        final settlementAmount =
            ((data['settlementAmount'] as num?) ?? 0).toInt();
        if (settlementState == 'pending' &&
            settlementId.isNotEmpty &&
            settlementAmount > 0 &&
            settlementId != _handledSettlementId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSettlementDialog(settlementId, settlementAmount);
          });
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _showSettlementDialog(String settlementId, int amount) async {
    if (!mounted || _handledSettlementId == settlementId) return;
    _handledSettlementId = settlementId;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Qaytim — hamyonga'),
        content: Text(
          'Haydovchi ${formatPrice(amount)} so\'m qaytimni hamyoningizga '
          'o\'tkazmoqchi. Tasdiqlaysizmi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Naqd kerak'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'confirm'),
            child: const Text('Tasdiqlayman'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'confirm') {
        await SettlementService.confirmSettlement(settlementId: settlementId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${formatPrice(amount)} so\'m hamyoningizga qo\'shildi'),
          backgroundColor: Colors.green,
        ));
      } else {
        await SettlementService.cancelSettlement(
          settlementId: settlementId,
          reason: 'passenger_wants_cash',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _handledSettlementId = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Settlement: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }
}
