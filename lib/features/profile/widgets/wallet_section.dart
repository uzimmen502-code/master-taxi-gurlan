import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/wallet_ledger_entry.dart';
import '../../../repositories/user_repository.dart';

class WalletSection extends StatelessWidget {
  const WalletSection({
    super.key,
    required this.phone,
  });

  final String phone;

  static const _green = Color(0xFF2E7D32);
  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    final uid = phoneDigits(phone);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: StreamBuilder<int>(
        stream: repo.watchBonusBalance(uid),
        builder: (context, snap) {
          final bal = snap.data ?? 0;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💳 Кошелёк',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                  '${formatPrice(bal)} сўм',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _green),
                ),
                const SizedBox(height: 8),
                Text(
                  'Тўлов: нон ва тайёр овқат буюртмасида кошелёкдан '
                  'миқдор автоматик ҳисобланади. '
                  'Қайтим ва сут бўйича кредит ҳам шу ерда кўринади.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Охирги операциялар',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 140,
                  child: StreamBuilder<List<WalletLedgerEntry>>(
                    stream: repo.watchWalletLedger(uid, limit: 12),
                    builder: (ctx, q) {
                      if (q.hasError) {
                        return Text('${q.error}',
                            style: const TextStyle(fontSize: 12));
                      }
                      if (!q.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _blue),
                        );
                      }
                      final items = q.data!;
                      if (items.isEmpty) {
                        return Text('Ҳали ёзувлар йўқ',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600));
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final e = items[i];
                          return _LedgerRow(entry: e);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}

/// Кошелёк дафтаридаги битта ёзув — `Қайтим • Нон буюртма • 12.05 14:30 +500`.
///
/// Эски рўйхатда битта матнли "Қайтим" 3 марта такрорланиб турарди — бу
/// фойдаланувчига қайси буюртмадан / қачон тушганини билдирмасди. Энди ҳар
/// ёзув: тур-нишон (icon), асосий лейбл, модул + вақт, миқдор.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final WalletLedgerEntry entry;

  static const _green = Color(0xFF2E7D32);
  static const _redLed = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    final color = entry.isPositive ? _green : _redLed;
    final meta = _moduleAndTime();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(_iconFor(entry.type),
                style: const TextStyle(fontSize: 14)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labelFor(entry.type),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (meta.isNotEmpty)
                Text(meta,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${entry.isPositive ? '+' : '−'}${formatPrice(entry.amount.abs())}',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 13),
        ),
      ]),
    );
  }

  String _moduleAndTime() {
    final parts = <String>[];
    final m = _moduleLabel(entry.module, entry.refType);
    if (m.isNotEmpty) parts.add(m);
    final t = entry.createdAt;
    if (t != null) parts.add(_shortDateTime(t));
    return parts.join(' • ');
  }

  static String _shortDateTime(DateTime t) {
    final d = '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')}';
    final tm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return '$d $tm';
  }

  static String _moduleLabel(String module, String refType) {
    switch (module) {
      case 'bread':
        return 'Нон буюртма';
      case 'food':
        return 'Тайёр овқат';
      case 'milk':
        return 'Сут топшириш';
      case 'eggs':
      case 'egg':
        return 'Тухум топшириш';
      case 'rice':
        return 'Гуруч топшириш';
      case 'meat':
      case 'gosht':
        return 'Гўшт топшириш';
      case 'yogurt':
      case 'qatiq':
        return 'Қатиқ / йогурт';
      case 'taxi':
      case 'local_taxi':
        return 'Маҳаллий такси';
      case 'marshrut':
        return 'Маршрут такси';
      case 'intercity':
        return 'Шаҳарлараро такси';
    }
    switch (refType) {
      case 'milk_day':
      case 'supplier_day':
        return 'Таъминотчи кредити';
      case 'payout_request':
        return 'Нақд олиш';
      case 'order':
        return 'Буюртма';
    }
    return '';
  }

  static String _iconFor(String type) {
    switch (type) {
      case 'change_accrued':
        return '💰';
      case 'supplier_credit':
        return '📦';
      case 'purchase_debit':
        return '🛒';
      case 'payout_request':
        return '⏳';
      case 'payout_paid':
        return '💸';
      case 'admin_adjust':
        return '🔧';
      default:
        return '•';
    }
  }

  static String _labelFor(String type) {
    switch (type) {
      case 'change_accrued':
        return 'Қайтим';
      case 'supplier_credit':
        return 'Таъминот кредити';
      case 'purchase_debit':
        return 'Кошелёкдан ечиш';
      case 'payout_request':
        return 'Чиқариш талаби';
      case 'payout_paid':
        return 'Нақд чиқарилди';
      case 'admin_adjust':
        return 'Админ ўзгартирди';
      default:
        return type;
    }
  }
}
