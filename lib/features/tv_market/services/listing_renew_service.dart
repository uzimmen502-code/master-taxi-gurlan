import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// «Бозорлар» 2b: муддати тугаган эълонни янгилаш — сервер `renewMarketListing({collection, id})`
/// (`functions/market_moderation.js`; эга текширувини ва `expired → pending` ўтишини сервер бажаради, 18-банд).
/// Қайта чақирилса — сервер `pending`да `changed: false` қайтаради (идемпотент, 21-банд).
class ListingRenewService {
  ListingRenewService({FirebaseFunctions? functions, this.invoke}) : _functions = functions;

  final FirebaseFunctions? _functions;

  /// Тест учун: callable ўрнига.
  final Future<Object?> Function(String name, Map<String, dynamic> payload)? invoke;

  static const callableName = 'renewMarketListing';

  Future<void> renew({required String collection, required String id}) async {
    final payload = {'collection': collection, 'id': id};
    final started = DateTime.now();
    try {
      final custom = invoke;
      if (custom != null) {
        await custom(callableName, payload);
      } else {
        await (_functions ?? FirebaseFunctions.instance).httpsCallable(callableName).call<Object?>(payload);
      }
      _log(collection, id, 'ok', null, started);
    } catch (e) {
      _log(collection, id, 'error', renewDiagnosticCode(e), started);
      rethrow;
    }
  }

  static void _log(String collection, String id, String result, String? code, DateTime started) {
    // Структурали лог (24-банд); шахсий маълумот йўқ (телефон ёзилмайди).
    debugPrint(jsonEncode({
      'module': 'listing_renew',
      'action': callableName,
      'collection': collection,
      'listingId': id,
      'result': result,
      if (code != null) 'errorCode': code,
      'duration': DateTime.now().difference(started).inMilliseconds,
    }));
  }
}

/// Диагностик код (фақат лог, 25-банд): сервер `details.code` (`LISTING_NOT_EXPIRED`, `NOT_OWNER`, …),
/// бўлмаса Firebase коди; бошқа хато — `CLIENT_ERROR`.
String renewDiagnosticCode(Object e) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    final c = d is Map ? d['code'] : null;
    if (c is String && c.isNotEmpty) return c;
    return e.code;
  }
  if (e is TimeoutException) return 'TIMEOUT';
  return 'CLIENT_ERROR';
}

/// Фойдаланувчига кўрсатиладиган матн калити (25-банд: stack trace / сервер матни эмас).
String renewErrorKey(Object e) {
  final code = renewDiagnosticCode(e);
  switch (code) {
    case 'LISTING_NOT_EXPIRED':
      return 'listing_mod_renew_not_expired';
    case 'unavailable':
    case 'deadline-exceeded':
    case 'TIMEOUT':
      return 'err_network';
    default:
      return 'listing_mod_renew_failed';
  }
}
