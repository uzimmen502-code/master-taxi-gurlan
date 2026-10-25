import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../business_map/data/business_repository.dart';

/// Сотувчининг ўз Telegram канали (эга қарори 2026-10-25, 1-фаза). Сервер: `functions/seller_tg_channel.js`
/// (sellerTgChannelStatus / Prepare / Connect / Disconnect). Ҳамма текширув серверда — илова фақат кўрсатади.
class SellerTgChannel {
  const SellerTgChannel({
    required this.status,
    this.username = '',
    this.title = '',
    this.code = '',
    this.expiresAt,
  });

  static const none = SellerTgChannel(status: 'none');

  /// `none` | `pending` (код берилган) | `connected` | `needs_reconnect` (бот ҳуқуқини йўқотган).
  final String status;
  final String username;
  final String title;

  /// Эгалик коди (`AVA-XXXXXX`) — фақат `pending`да.
  final String code;
  final DateTime? expiresAt;

  bool get isConnected => status == 'connected';
  bool get needsReconnect => status == 'needs_reconnect';
  bool get isPending => status == 'pending' && code.isNotEmpty;
  String get handle => username.isEmpty ? '' : '@$username';

  factory SellerTgChannel.fromMap(Object? raw) {
    if (raw is! Map) return none;
    final ms = raw['expiresAtMs'];
    return SellerTgChannel(
      status: '${raw['status'] ?? 'none'}',
      username: '${raw['username'] ?? ''}'.trim(),
      title: '${raw['title'] ?? ''}'.trim(),
      code: '${raw['code'] ?? ''}'.trim(),
      expiresAt: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
    );
  }
}

class SellerTgChannelState {
  const SellerTgChannelState({required this.available, required this.botUsername, required this.channel});

  /// AVA боти созланган (`getMe` жавоб берди).
  final bool available;
  final String botUsername;
  final SellerTgChannel channel;
}

/// Тестда алмаштирилади ([CallableSellerTgChannelApi] — ҳақиқий callable'лар).
abstract class SellerTgChannelApi {
  Future<SellerTgChannelState> status();
  Future<SellerTgChannel> prepare(String username);
  Future<SellerTgChannel> connect();
  Future<void> disconnect();
}

class CallableSellerTgChannelApi implements SellerTgChannelApi {
  CallableSellerTgChannelApi({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<Map> _call(String name, [Map<String, Object?> data = const {}]) async {
    final res = await _fns.httpsCallable(name).call<Object?>(data);
    return (res.data as Map?) ?? const {};
  }

  @override
  Future<SellerTgChannelState> status() async {
    final d = await _call('sellerTgChannelStatus');
    return SellerTgChannelState(
      available: d['available'] == true,
      botUsername: '${d['botUsername'] ?? ''}'.trim(),
      channel: SellerTgChannel.fromMap(d['channel']),
    );
  }

  @override
  Future<SellerTgChannel> prepare(String username) async =>
      SellerTgChannel.fromMap((await _call('sellerTgChannelPrepare', {'username': username.trim()}))['channel']);

  @override
  Future<SellerTgChannel> connect() async => SellerTgChannel.fromMap((await _call('sellerTgChannelConnect'))['channel']);

  @override
  Future<void> disconnect() async => _call('sellerTgChannelDisconnect');
}

/// Сервер диагностика кодлари → фойдаланувчига тушунарли матн калити (25-банд).
const sellerTgKnownErrors = {
  'INVALID_USERNAME',
  'PRIVATE_CHANNEL_UNSUPPORTED',
  'CHANNEL_NOT_FOUND',
  'NOT_A_CHANNEL',
  'CHANNEL_NOT_ALLOWED',
  'BOT_NOT_ADMIN',
  'BOT_NO_POST_RIGHT',
  'CHANNEL_TAKEN',
  'SELLER_HAS_CHANNEL',
  'SHOP_BLOCKED',
  'NO_PENDING_CODE',
  'CODE_EXPIRED',
  'CODE_NOT_FOUND',
  'SELLER_TG_RATE_LIMIT',
  'TG_TRY_LATER',
};

String sellerTgErrorKey(Object e) {
  final code = BusinessRepository.errorCode(e);
  if (code == 'TG_BOT_UNAVAILABLE') return 'seller_tg_unavailable';
  if (sellerTgKnownErrors.contains(code)) return 'seller_tg_err_$code';
  return 'seller_tg_err_generic';
}

/// Жойлаш экрани учун: эганинг УЛАНГАН канали номи (`@nom`), бўлмаса бўш. Rules: эга фақат ўз ҳужжатини `get`.
/// Хато (офлайн ва ҳ.к.) — бўш: «Менинг каналим» шунчаки кўринмайди, жойлаш тўхтамайди.
Future<String> loadConnectedSellerChannel(String phone, {FirebaseFirestore? firestore}) async {
  if (phone.length != 12) return '';
  try {
    final snap = await (firestore ?? FirebaseFirestore.instance).collection('seller_tg_channels').doc(phone).get();
    final d = snap.data();
    if (d == null || d['status'] != 'connected') return '';
    final u = '${d['username'] ?? ''}'.trim();
    return u.isEmpty ? '' : '@$u';
  } catch (e) {
    debugPrint('[SellerTgChannel] load: $e');
    return '';
  }
}
