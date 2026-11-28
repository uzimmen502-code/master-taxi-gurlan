/// Компьютерда QR орқали кириш (эга 2026-11-28) — соф ёрдамчилар (тестланади).
///
/// Сервер манбаси: `functions/qr_web_login.js` (`feat/qr-web-login-srv`). QR матни ва хато
/// кодлари сервер билан бир хил бўлиши шарт — ўзгарса иккала томон биргаликда.
library;

/// QR матни: `AVAQR1:<32 hex sid>` (сервер `qrPayloadFor`).
const String kQrLoginPrefix = 'AVAQR1:';

final RegExp _sidRe = RegExp(r'^[a-f0-9]{32}$');

/// QR матнидан `sid`; AVA кириш QR'и бўлмаса — бўш сатр.
String parseQrLoginPayload(String? raw) {
  final s = (raw ?? '').trim();
  if (!s.startsWith(kQrLoginPrefix)) return '';
  final sid = s.substring(kQrLoginPrefix.length).toLowerCase();
  return _sidRe.hasMatch(sid) ? sid : '';
}

/// Сервер `details.code` → l10n калити (фойдаланувчига хом код чиқмайди, §25).
String qrLoginErrorKey(String? code) {
  switch (code) {
    case 'QR_LOGIN_DISABLED':
      return 'qrl_disabled';
    case 'QR_SESSION_INVALID':
      return 'qrl_err_invalid';
    case 'QR_SESSION_OTHER_USER':
      return 'qrl_err_other_user';
    case 'QR_SESSION_NOT_PENDING':
      return 'qrl_err_used';
    case 'QR_WEB_SESSION_LIMIT':
      return 'qrl_err_limit';
    case 'QR_RATE_LIMITED':
      return 'qrl_err_rate';
    case 'QR_WEB_SESSION_INVALID':
      return 'qrl_err_session_ended';
    case 'DEVICE_NOT_BOUND':
      return 'qrl_not_main_phone';
    default:
      return 'qrl_err_generic';
  }
}

/// Web QR экрани ҳолати (`qr_login_watch.status`).
enum QrWatchState { pending, scanned, approved, consumed, rejected, expired, unknown }

QrWatchState qrWatchStateOf(String? status) {
  switch (status) {
    case 'pending':
      return QrWatchState.pending;
    case 'scanned':
      return QrWatchState.scanned;
    case 'approved':
      return QrWatchState.approved;
    case 'consumed':
      return QrWatchState.consumed;
    case 'rejected':
      return QrWatchState.rejected;
    case 'expired':
    case 'cancelled':
      return QrWatchState.expired;
    default:
      return QrWatchState.unknown;
  }
}

/// Web QR'ни автомат янгилаш сони (ҳар бири ~2 дақиқа). Кейин — «Янги QR код» тугмаси
/// (очиқ қолган вкладка чексиз ёзув/чақирув қилмасин, §37).
const int kQrAutoRefreshMax = 5;
