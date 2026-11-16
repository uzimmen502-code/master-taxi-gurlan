// Админ — «Бозор буюртмалари» (бизнес/ўз дўкони буюртмалари) босқичи. Сервер (feat/bozor-orders-srv,
// functions/business_orders.js): `adminGetBusinessOrdersConfig` (ўқиш; `server_config/business_orders` клиентга
// ёпиқ) ва `adminSetBusinessOrdersConfig` (ёзиш — версия + `admin_audit`). Етказиш тарифи — ресторан тарифи
// (`settings/restaurant_delivery`, `adminSetRestaurantDeliveryPrices`) — алоҳида тариф ЙЎҚ (7-банд).

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/formatters.dart';
import 'admin_restaurants_service.dart' show AdminRestaurantsException;

/// Сервер `STAGES` (business_orders.js) билан бир хил тартиб.
const kBusinessOrderStages = <String>['off', 'internal', 'pilot', 'public'];

/// `adminGetBusinessOrdersConfig` жавоби.
class BusinessOrdersConfig {
  const BusinessOrdersConfig({
    required this.stage,
    this.testerIds = const [],
    this.pilotDistrictIds = const [],
    this.acceptTimeoutMin = 0,
    this.version = 0,
    this.exists = false,
  });

  final String stage;
  final List<String> testerIds;
  final List<String> pilotDistrictIds;
  final int acceptTimeoutMin;
  final int version;

  /// Ҳужжат серверда бор (йўқ — сукут OFF).
  final bool exists;

  factory BusinessOrdersConfig.fromMap(Map<String, dynamic> m) {
    List<String> list(Object? v) => v is List ? v.map((e) => '$e').where((e) => e.isNotEmpty).toList() : const [];
    final stage = '${m['stage'] ?? ''}';
    return BusinessOrdersConfig(
      stage: kBusinessOrderStages.contains(stage) ? stage : 'off',
      testerIds: list(m['testerIds']),
      pilotDistrictIds: list(m['pilotDistrictIds']),
      acceptTimeoutMin: (m['acceptTimeoutMin'] as num?)?.toInt() ?? 0,
      version: (m['version'] as num?)?.toInt() ?? 0,
      exists: m['exists'] == true,
    );
  }
}

/// Матндан телефонлар (қатор/вергул/бўшлиқ; 998… ёки 9 рақам) — каноник, такрорсиз, тартибли.
List<String> parseTesterPhones(String raw) {
  final out = <String>{};
  for (final part in raw.split(RegExp(r'[\s,;]+'))) {
    final p = part.trim();
    if (p.isEmpty) continue;
    out.add(canonicalPhoneId(p));
  }
  return out.toList()..sort();
}

/// Нотўғри телефонлар (сервер `TESTER_RE` кўзгуси: 998 + 9 рақам).
List<String> invalidTesterPhones(List<String> phones) =>
    phones.where((p) => !RegExp(r'^998\d{9}$').hasMatch(p)).toList();

/// `adminSetBusinessOrdersConfig` payload'и (соф — тест учун): синовчилар фарқ сифатида (`add`/`remove`;
/// серверда ҳар бири ≤200), пилот туманлар — тўлиқ рўйхат, босқич — доим.
Map<String, dynamic> businessOrdersSavePayload({
  required BusinessOrdersConfig current,
  required String stage,
  required List<String> testerIds,
  required List<String> pilotDistrictIds,
  required String reason,
}) {
  final cur = current.testerIds.map(canonicalPhoneId).toSet();
  final next = testerIds.map(canonicalPhoneId).toSet();
  final add = (next.difference(cur).toList()..sort());
  final remove = (cur.difference(next).toList()..sort());
  return {
    'stage': stage,
    if (add.isNotEmpty) 'addTesterIds': add,
    if (remove.isNotEmpty) 'removeTesterIds': remove,
    'pilotDistrictIds': (pilotDistrictIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort()),
    'reason': reason.trim(),
  };
}

class AdminBusinessOrdersService {
  AdminBusinessOrdersService({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final res = await _functions.httpsCallable(name).call<dynamic>(data);
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      throw AdminRestaurantsException(e.code, (details?['code'] ?? '').toString(), e.message ?? e.code);
    }
  }

  Future<BusinessOrdersConfig> load() async => BusinessOrdersConfig.fromMap(await _call('adminGetBusinessOrdersConfig', const {}));

  /// Жавоб: `{ok, version, stage, testerCount, pilotDistrictIds, acceptTimeoutMin}`.
  Future<Map<String, dynamic>> save(Map<String, dynamic> payload) => _call('adminSetBusinessOrdersConfig', payload);
}
