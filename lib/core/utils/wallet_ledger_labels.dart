import '../../models/wallet_ledger_entry.dart';
import 'formatters.dart';

/// Таржима функцияси: `key` ва ихтиёрий `{param}` қийматлари. Виджетда
/// `context.tr` / `context.trMsg` га боғланади, тестда оддий функция берилади.
///
/// Аввал ёрлиқлар қаттиқ ёзилган, кирилл ва лотин ҳатто бир сўз ичида
/// аралашиб кетган эди («Қaytim»): лотин ва рус фойдаланувчи ўз тилида
/// кўрмасди (2026-10-18).
typedef WalletTr = String Function(String key, [Map<String, String>? params]);

String walletLedgerTitle(WalletLedgerEntry e, WalletTr tr) {
  final module = _moduleLabel(e.module, tr);
  String withModule(String plainKey, String modKey) =>
      module.isEmpty ? tr(plainKey) : tr(modKey, {'module': module});

  switch (e.type) {
    case 'purchase_debit':
      return withModule('wlt_l_purchase', 'wlt_l_purchase_mod');
    case 'change_accrued':
    case 'settlement_credit':
      return withModule('wlt_l_change', 'wlt_l_change_mod');
    case 'settlement_debit':
      return withModule('wlt_l_change_given', 'wlt_l_change_given_mod');
    case 'cash_to_wallet':
      return tr('wlt_l_cash_to_wallet');
    case 'wallet_to_cash':
      return tr('wlt_l_wallet_to_cash');
    case 'float_to_wallet_migration':
      return tr('wlt_l_float_migration');
    case 'wallet_p2p_credit':
      return tr('wlt_l_p2p_credit');
    case 'wallet_p2p_debit':
      return tr('wlt_l_p2p_debit');
    case 'supplier_credit':
      return withModule('wlt_l_credit', 'wlt_l_credit_mod');
    case 'payout_request':
      return tr('wlt_l_payout_request');
    case 'payout_paid':
      return tr('wlt_l_payout_paid');
    case 'admin_adjust':
      return tr('wlt_l_admin_adjust');
    case 'birthday_bonus':
      return tr('wlt_l_birthday');
    default:
      if (module.isNotEmpty) return module;
      return e.type.isEmpty ? tr('wlt_l_operation') : e.type;
  }
}

String walletLedgerSubtitle(WalletLedgerEntry e, WalletTr tr) {
  final parts = <String>[];
  final note = (e.meta['note'] ?? '').toString().trim();
  if (note.isNotEmpty) parts.add(note);

  final orderTotal = (e.meta['orderTotal'] as num?)?.toInt();
  if (orderTotal != null && orderTotal > 0) {
    parts.add(tr('wlt_l_order', {'amount': formatMoney(orderTotal)}));
  }

  final cashPaid = (e.meta['cashPaid'] as num?)?.toInt();
  if (cashPaid != null && cashPaid > 0) {
    parts.add(tr('wlt_l_cash', {'amount': formatMoney(cashPaid)}));
  }

  if (e.refId.isNotEmpty && e.refType == 'order') {
    parts.add('№ ${e.refId.length > 8 ? e.refId.substring(0, 8) : e.refId}');
  }

  return parts.join(' · ');
}

/// Модул номи фойдаланувчи тилида; номаълум модул — ўз номи билан.
String _moduleLabel(String module, WalletTr tr) {
  switch (module) {
    case 'bread':
      return tr('wlt_m_bread');
    case 'food':
      return tr('wlt_m_food');
    case 'milk':
      return tr('wlt_m_milk');
    case 'rice':
      return tr('wlt_m_rice');
    case 'taxi-core':
    case 'taxi':
      return tr('wlt_m_taxi');
    default:
      return module;
  }
}
