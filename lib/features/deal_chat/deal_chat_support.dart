/// «Буюртма ёзиш» чати — умумий кичик ёрдамчилар (экранлар, push, fcm_service).
library;

/// Ҳозир очиқ турган чат (олд режимдаги push шу чат учун кўрсатилмайди — хабар экранда).
class DealChatPresence {
  DealChatPresence._();

  static String? _open;

  static String? get openChatId => _open;
  static void enter(String chatId) => _open = chatId;
  static void leave(String chatId) {
    if (_open == chatId) _open = null;
  }

  /// Олд режимдаги push'ни кўрсатмаслик керакми.
  static bool suppressForeground(Map<String, dynamic> data) =>
      (data['type'] ?? '') == 'deal_chat' && _open != null && (data['chatId'] ?? '') == _open;
}

/// Push'даги `chatId` — сервер шакли (`[ad-|si-|bz-]<productId>_<рақам>`; объект ID'си ичида ҳам `_` бор —
/// `bz-998…_b17…_998…`); бошқаси — `null`.
String? dealChatIdFromPush(Map<String, String> data) {
  final type = (data['type'] ?? '').trim();
  final screen = (data['screen'] ?? '').trim();
  if (type != 'deal_chat' && screen != 'deal_chat') return null;
  final id = (data['chatId'] ?? '').trim();
  return RegExp(r'^[A-Za-z0-9_-]{1,104}_\d{11,15}$').hasMatch(id) ? id : null;
}

/// Сервер хабар коди (`HttpsError.message`) → l10n калити (`userErrorMessage(byServerMessage:)`).
const Map<String, String> kDealChatServerErrors = {
  'OWN_PRODUCT': 'deal_chat_own_product',
  'PRODUCT_UNAVAILABLE': 'deal_chat_product_unavailable',
  'PHONE_REQUIRED': 'deal_chat_login_required',
  'RATE_LIMITED': 'err_too_many',
  'CHAT_NOT_FOUND': 'err_not_found',
  'TEXT_INVALID': 'deal_chat_text_invalid',
};

/// Сервер чегараси билан бир хил (`functions/deal_chats.js` LIMITS.textMax).
const int kDealChatTextMax = 1000;
