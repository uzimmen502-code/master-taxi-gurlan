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
  // «AVA Супермаркет» (эга 2026-11-20): сервер module 'platform' + meta.subtype 'supermarket' ёзади.
  final module = e.module == 'platform' && e.meta['subtype'] == 'supermarket'
      ? tr('wlt_m_supermarket')
      : _moduleLabel(e.module, tr);
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
    // AVA Logistics LEG ҳақи — сервер `courier_payout.js` (хизмат ҳақи ушланган).
    case 'courier_payout':
      return tr('wlt_l_courier_payout');
    // Улгуржи буюртма занжири — сервер `functions/wholesale_orders.js` (`mirrorWallet`
    // ва `walletLedgerType`), feat/ulg-card 2fec8ce8. Калит = `wlt_l_` + тур номи.
    case 'wholesale_hold':
    case 'wholesale_card_hold':
    case 'wholesale_refund':
    case 'wholesale_refusal_refund':
    case 'wholesale_payout':
    case 'wholesale_unearned_delivery_refund':
    case 'wholesale_return_hold':
    case 'wholesale_lost_refund':
    case 'wholesale_lost_fee_refund':
    case 'wholesale_lost_fee_charge':
    case 'wholesale_lost_fee_payment':
    // Харидор қарзини ҳамёндан тўлаш (`payWholesaleBuyerDebt`, 2026-11-15): харидор (−) ва йиғувчи курьер (+).
    case 'wholesale_debt_payment':
    case 'logistics_cash_debt_payout':
      return tr('wlt_l_${e.type}');
    // Relay `functions/relay_escrow.js` (`mirrorBonus`): бир хил тур ИККИ ҳамёнга
    // ёзилади — мижоз (+, қоплама) ва масъул курьер (−, ундирилди).
    case 'logistics_lost_refund':
      return tr(e.amount < 0 ? 'wlt_l_logistics_lost_charge' : 'wlt_l_logistics_lost_refund');
    // Буюртманинг бир қисми қайтди (супермаркет: тортилгандан кейин / маҳсулот олинди — supermarket.js).
    case 'order_partial_refund':
      return withModule('wlt_l_partial_refund', 'wlt_l_partial_refund_mod');
    case 'admin_adjust':
      return tr('wlt_l_admin_adjust');
    case 'birthday_bonus':
      return tr('wlt_l_birthday');
    // «Автомобил суғуртаси» агент бекор қилди (functions/car_insurance.js, эга 2026-11-28).
    case 'insurance_cancel_refund':
      return tr('wlt_l_insurance_cancel_refund');
    default:
      if (module.isNotEmpty) return module;
      return e.type.isEmpty ? tr('wlt_l_operation') : e.type;
  }
}

/// Сервер изоҳи (эга 2026-11-20; сервер 18b4ca04): аввал `meta.messages{uz_Cyrl,uz_Latn,ru}` (жорий тил →
/// uz_Cyrl), кейин `meta.noteKey` (`sm_refund_weigh` | `sm_refund_line_removed`, lang калити), охири — эски `meta.note`.
String walletLedgerNote(WalletLedgerEntry e, WalletTr tr, {String lang = 'uz_Cyrl'}) {
  final m = e.meta['messages'];
  if (m is Map) {
    final own = (m[lang] ?? '').toString().trim();
    if (own.isNotEmpty) return own;
    final cyr = (m['uz_Cyrl'] ?? '').toString().trim();
    if (cyr.isNotEmpty) return cyr;
  }
  final key = (e.meta['noteKey'] ?? '').toString().trim();
  if (key.isNotEmpty) {
    final t = tr(key);
    if (t.isNotEmpty && t != key) return t;
  }
  return (e.meta['note'] ?? '').toString().trim();
}

String walletLedgerSubtitle(WalletLedgerEntry e, WalletTr tr, {String lang = 'uz_Cyrl'}) {
  final parts = <String>[];
  final note = walletLedgerNote(e, tr, lang: lang);
  if (note.isNotEmpty) parts.add(note);

  final orderTotal = (e.meta['orderTotal'] as num?)?.toInt();
  if (orderTotal != null && orderTotal > 0) {
    parts.add(tr('wlt_l_order', {'amount': formatMoney(orderTotal)}));
  }

  final cashPaid = (e.meta['cashPaid'] as num?)?.toInt();
  if (cashPaid != null && cashPaid > 0) {
    parts.add(tr('wlt_l_cash', {'amount': formatMoney(cashPaid)}));
  }

  if (e.type == 'courier_payout') {
    final fee = (e.meta['fee'] as num?)?.toInt();
    if (fee != null && fee > 0) {
      parts.add(tr('wlt_l_courier_fee', {'amount': formatMoney(fee)}));
    }
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
    case 'insurance':
      return tr('wlt_m_insurance');
    default:
      return module;
  }
}
