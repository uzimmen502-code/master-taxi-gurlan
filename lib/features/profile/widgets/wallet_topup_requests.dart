import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/wallet_topup_request.dart';

/// Эганинг тўлдириш сўровлари ҳолати: «чек кутилмоқда» → «текширувда» →
/// «ҳамёнга тушди» / «рад этилди». Аввал бу фақат ботдаги `/status` орқали
/// маълум эди (2026-10-18).
///
/// Кўрсатилмайдиган ҳол: сўров йўқ — виджет жой эгалламайди.
class WalletTopUpRequests extends StatelessWidget {
  const WalletTopUpRequests({
    super.key,
    required this.uid,
    this.stream,
    this.clock,
  });

  final String uid;

  /// Тест учун алмаштириладиган оқим.
  final Stream<List<WalletTopUpRequest>>? stream;
  final DateTime Function()? clock;

  Stream<List<WalletTopUpRequest>> _defaultStream() => FirebaseFirestore.instance
      .collection('wallet_topup_requests')
      .where('uid', isEqualTo: canonicalPhoneId(uid))
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((s) => [for (final d in s.docs) WalletTopUpRequest.fromMap(d.id, d.data())]);

  @override
  Widget build(BuildContext context) {
    if (stream == null && canonicalPhoneId(uid).length < 12) return const SizedBox.shrink();
    return StreamBuilder<List<WalletTopUpRequest>>(
      stream: stream ?? _defaultStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[WalletTopUpRequests] ${snap.error}');
          return const SizedBox.shrink();
        }
        final now = (clock ?? DateTime.now)();
        final items = visibleTopUpRequests(snap.data ?? const [], now);
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('wallet-topup-requests'),
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('wlt_tu_title'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  for (final r in items) _Row(request: r, now: now),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.request, required this.now});

  final WalletTopUpRequest request;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final status = request.effectiveStatus(now);
    final (Color color, IconData icon) = switch (status) {
      'credited' => (AvaLight.ok, Icons.check_circle),
      'awaiting_review' => (Colors.orange.shade800, Icons.hourglass_top_rounded),
      'awaiting_transfer' => (Colors.blueGrey.shade700, Icons.receipt_long_outlined),
      'rejected' => (Colors.red.shade700, Icons.cancel_outlined),
      _ => (Colors.grey.shade600, Icons.history_toggle_off),
    };
    final when = request.createdAt;
    return Padding(
      key: ValueKey('topup-row-${request.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatMoney(request.amount), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  _label(context, status),
                  key: ValueKey('topup-status-$status'),
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                ),
                if (status == 'rejected' && request.rejectReason.isNotEmpty)
                  Text(request.rejectReason, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                if (when != null)
                  Text(
                    DateFormat('dd.MM.yyyy HH:mm').format(when),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(BuildContext context, String status) {
    switch (status) {
      case 'awaiting_transfer':
        return context.tr('wlt_tu_awaiting_transfer');
      case 'awaiting_review':
        return context.tr('wlt_tu_awaiting_review');
      case 'credited':
        return context.tr('wlt_tu_credited');
      case 'rejected':
        return context.tr('wlt_tu_rejected');
      case 'expired':
        return context.tr('wlt_tu_expired');
      case 'cancelled':
        return context.tr('wlt_tu_cancelled');
      default:
        return status.isEmpty ? '—' : status;
    }
  }
}
