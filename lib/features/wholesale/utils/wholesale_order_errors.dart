import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/user_error.dart';
import '../repositories/wholesale_orders_repository.dart';

/// Сервер `details.reason` → фойдаланувчи матни калити (25-банд: ички код
/// кўрсатилмайди). Бир нечта сабаб битта тушунарли матнга йиғилади.
const Map<String, String> kWholesaleOrderReasonKeys = {
  // Дарвоза / созлама
  'module_disabled': 'wholesale_order_err_unavailable',
  'module_internal_only': 'wholesale_order_err_unavailable',
  'fee_settings_invalid': 'wholesale_order_err_unavailable',
  // Товар
  'own_product': 'wholesale_order_err_own_product',
  'product_unavailable': 'wholesale_order_err_product_unavailable',
  'product_not_found': 'wholesale_order_err_product_unavailable',
  'foreign_market': 'wholesale_order_err_foreign_market',
  'pack_not_found': 'wholesale_order_err_pack',
  'pack_required': 'wholesale_order_err_pack',
  'pack_price_missing': 'wholesale_order_err_pack',
  'below_moq': 'wholesale_order_err_below_moq',
  'qty_invalid': 'wholesale_order_err_qty_invalid',
  'stock_unknown': 'wholesale_order_err_stock_unknown',
  'insufficient_stock': 'wholesale_order_err_insufficient_stock',
  // Етказиш
  'no_shipping_data': 'wholesale_order_err_no_shipping_data',
  'over_weight': 'wholesale_order_err_no_shipping_data',
  'seller_location_missing': 'wholesale_order_err_seller_location',
  'zone_not_found': 'wholesale_order_err_delivery_price',
  'tariff_extra_price_missing': 'wholesale_order_err_delivery_price',
  'delivery_price_invalid': 'wholesale_order_err_delivery_price',
  'address_required': 'wholesale_order_err_address',
  'destination_required': 'wholesale_order_err_address',
  'amount_too_large': 'wholesale_order_err_amount_too_large',
  // Буюртма бериш
  'insufficient_balance': 'wholesale_order_err_insufficient_balance',
  'quote_expired': 'wholesale_order_err_quote_expired',
  'quote_used': 'wholesale_order_err_quote_expired',
  'quote_not_found': 'wholesale_order_err_quote_expired',
  'quote_invalid': 'wholesale_order_err_quote_expired',
  'idempotency_key_reused': 'wholesale_order_err_retry',
  'hold_conflict': 'wholesale_order_err_retry',
  // Буюртма амаллари
  'order_not_found': 'wholesale_order_err_order_not_found',
  'not_order_party': 'wholesale_order_err_not_party',
  'not_recipient': 'wholesale_order_err_not_party',
  'invalid_transition': 'wholesale_order_err_invalid_transition',
  'shipment_not_ready': 'wholesale_order_err_shipment_not_ready',
  'shipment_missing': 'wholesale_order_err_shipment_not_ready',
  'shipment_closed': 'wholesale_order_err_shipment_closed',
  // 3b карта
  'card_payment_unconfirmed': 'wholesale_order_err_card_payment_unconfirmed',
  'card_invalid': 'wholesale_order_err_card_invalid',
};

/// Квота/ўтказишда «буюртма бериш бу фойдаланувчига ёпиқ» маъносидаги
/// сабаблар — тугма яширинади, қўнғироқ қолади.
bool isWholesaleOrdersClosed(Object error) =>
    error is WholesaleOrderException &&
    (error.reason == 'module_disabled' || error.reason == 'module_internal_only');

/// Хато → матн калити (соф, тестланади).
String wholesaleOrderErrorKey(Object error) {
  if (error is WholesaleOrderException) {
    final byReason = kWholesaleOrderReasonKeys[error.reason];
    if (byReason != null) return byReason;
    // Сабаби йўқ (тармоқ, вақт, рухсат) — умумий код харитаси.
    return userErrorKeyFromCode(error.code, fallbackKey: 'wholesale_order_err_generic');
  }
  return userErrorKey(error, fallbackKey: 'wholesale_order_err_generic');
}

String wholesaleOrderErrorText(BuildContext context, Object error) {
  // Ички диагностика — фақат лог (матнсиз: код ва сабаб).
  debugPrint('[WholesaleOrder] $error');
  return context.tr(wholesaleOrderErrorKey(error));
}

/// Карта тўлови ёпиқлигининг сабаби (квота `cardUnavailableReason`) → матн.
/// Маълум сабаб матни бўлмаса — умумий «бу буюртмада карта мавжуд эмас».
String wholesaleCardUnavailableKey(String reason) => switch (reason) {
      'seller_debt' => 'wholesale_pay_card_unavailable_seller_debt',
      _ => 'wholesale_pay_card_unavailable',
    };
