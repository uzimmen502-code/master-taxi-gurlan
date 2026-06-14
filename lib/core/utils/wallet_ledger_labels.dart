import '../../models/wallet_ledger_entry.dart';
import 'formatters.dart';

String walletLedgerTitle(WalletLedgerEntry e) {
  final module = _moduleLabel(e.module);
  switch (e.type) {
    case 'purchase_debit':
      return module.isEmpty ? 'Кошелёкдан тўлов' : '$module — тўлов';
    case 'change_accrued':
      return module.isEmpty ? 'Қaytim' : '$module — qaytim';
    case 'supplier_credit':
      return module.isEmpty ? 'Kredit' : '$module — kredit';
    case 'payout_request':
      return 'Pul yechish arizasi';
    case 'payout_paid':
      return 'Pul yechildi';
    case 'admin_adjust':
      return 'Admin tuzatishi';
    case 'birthday_bonus':
      return 'Tug‘ilgan kun bonusi';
    default:
      if (module.isNotEmpty) return module;
      return e.type.isEmpty ? 'Operatsiya' : e.type;
  }
}

String walletLedgerSubtitle(WalletLedgerEntry e) {
  final parts = <String>[];
  final note = (e.meta['note'] ?? '').toString().trim();
  if (note.isNotEmpty) parts.add(note);

  final orderTotal = (e.meta['orderTotal'] as num?)?.toInt();
  if (orderTotal != null && orderTotal > 0) {
    parts.add('Buyurtma: ${formatPrice(orderTotal)} so‘m');
  }

  final cashPaid = (e.meta['cashPaid'] as num?)?.toInt();
  if (cashPaid != null && cashPaid > 0) {
    parts.add('Naqd: ${formatPrice(cashPaid)} so‘m');
  }

  if (e.refId.isNotEmpty && e.refType == 'order') {
    parts.add('№ ${e.refId.length > 8 ? e.refId.substring(0, 8) : e.refId}');
  }

  return parts.join(' · ');
}

String _moduleLabel(String module) {
  switch (module) {
    case 'bread':
      return 'Non';
    case 'food':
      return 'Taom';
    case 'milk':
      return 'Sut';
    case 'rice':
      return 'Guruch';
    case 'taxi-core':
    case 'taxi':
      return 'Taksi';
    default:
      if (module.isEmpty) return '';
      return module;
  }
}
