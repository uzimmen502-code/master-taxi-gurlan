// «Менинг бизнесим» буюртмаси — сервер диагностика коди (`details.code`) → фойдаланувчи матни калити (25-қоида).
// Ички код экранга чиқмайди; номаълум код — умумий матн. Калитлар 3 тилда (`assets/lang`, тест қулфлайди).

/// Ҳар бир сервер коди → l10n калити. Бир нечта код бир матнга тушиши мумкин (мазмуни бир хил).
const Map<String, String> bizOrderErrorKeys = {
  'MODULE_OFF': 'biz_order_err_module_off',
  'MODULE_INTERNAL_ONLY': 'biz_order_err_module_internal_only',
  'MODULE_NOT_IN_PILOT': 'biz_order_err_module_not_in_pilot',
  'TARIFF_NOT_CONFIGURED': 'biz_order_err_tariff_not_configured',
  'AVA_FEE_NOT_SUPPORTED': 'biz_order_err_tariff_not_configured',
  'AVA_FEE_CONFIG_INVALID': 'biz_order_err_tariff_not_configured',
  'DELIVERY_TOO_FAR': 'biz_order_err_delivery_too_far',
  'DELIVERY_ADDRESS_REQUIRED': 'biz_order_err_address_required',
  'BUSINESS_NOT_FOUND': 'biz_order_err_business_not_found',
  'BUSINESS_NOT_ACTIVE': 'biz_order_err_business_not_active',
  'BUSINESS_LOCATION_MISSING': 'biz_order_err_business_not_active',
  'BUSINESS_NO_OWNER': 'biz_order_err_business_not_active',
  'BUSINESS_ONLINE_NO_PICKUP': 'biz_order_err_business_online_no_pickup',
  'OWN_BUSINESS': 'biz_order_err_own_business',
  'ITEM_NOT_FOUND': 'biz_order_err_item_not_found',
  'ITEM_NOT_IN_BUSINESS': 'biz_order_err_item_not_found',
  'ITEM_UNAVAILABLE': 'biz_order_err_item_unavailable',
  'ITEM_INVALID': 'biz_order_err_item_unavailable',
  'ITEMS_REQUIRED': 'biz_order_err_item_unavailable',
  'ITEM_NOT_PRODUCT': 'biz_order_err_item_not_product',
  'PRICE_NOT_FIXED': 'biz_order_err_price_not_fixed',
  'ITEM_PRICE_INVALID': 'biz_order_err_price_not_fixed',
  'QTY_LIMIT_EXCEEDED': 'biz_order_err_qty_limit_exceeded',
  'IDEMPOTENCY_KEY_CONFLICT': 'biz_order_err_idempotency_key_conflict',
  'NOT_ORDER_SELLER': 'biz_order_err_not_order_seller',
  'NOT_ORDER_OWNER': 'biz_order_err_not_order_seller',
  'ORDER_INVALID_TRANSITION': 'biz_order_err_order_invalid_transition',
  'ORDER_NOT_READY': 'biz_order_err_order_not_ready',
  'CANCEL_NOT_ALLOWED': 'biz_order_err_cancel_not_allowed',
  'ORDER_NOT_CLAIMABLE': 'biz_order_err_order_not_claimable',
  'COURIER_IS_SELLER': 'biz_order_err_order_not_claimable',
  'COURIER_OWN_ORDER': 'biz_order_err_order_not_claimable',
  'COURIER_ASSIGNMENT_CONFLICT': 'biz_order_err_courier_assignment_conflict',
  'BUYOUT_LIMIT_EXCEEDED': 'biz_order_err_buyout_limit_exceeded',
  'PICKUP_CODE_MISMATCH': 'biz_order_err_pickup_code_mismatch',
  'PICKUP_CODE_LOCKED': 'biz_order_err_pickup_code_locked',
  'CONTENTION_RETRY': 'biz_order_err_contention_retry',
};

/// Умумий (номаълум) хато матни.
const bizOrderErrorGeneric = 'biz_order_err_generic';

/// Код → калит; номаълум код — `null` (чақирувчи умумий/тармоқ калитини танлайди).
String? bizOrderErrorKeyOrNull(String code) => bizOrderErrorKeys[code.trim()];

/// Матндаги `{param}`лар учун сервер `details` қийматлари (масалан `maxKm`, `attemptsLeft`).
Map<String, String> bizOrderErrorParams(String code, Map<String, dynamic>? details) {
  final d = details ?? const <String, dynamic>{};
  String n(Object? v, String fallback) => v is num ? '${v.toInt()}' : fallback;
  return switch (code) {
    'DELIVERY_TOO_FAR' => {'km': n(d['maxKm'], '—')},
    'QTY_LIMIT_EXCEEDED' => {'max': n(d['maxQty'], '100')},
    'PICKUP_CODE_MISMATCH' => {'n': n(d['attemptsLeft'], '—')},
    _ => const {},
  };
}
