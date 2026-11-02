import 'package:cloud_functions/cloud_functions.dart';

/// Рағбат дастурлари — админ callable'лари (`functions/incentives.js`, эга қарори 2026-11-02).
/// Ёзиш фақат сервер орқали (rules'да ёпиқ); ҳар амал `admin_audit`га тушади.
class AdminIncentivesService {
  AdminIncentivesService({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  /// Яратиш ёки таҳрирлаш. [programId] бўш — янги (ID = `key`). → programId.
  Future<String> upsertProgram(Map<String, dynamic> program, {String? programId}) async {
    final res = await _fns.httpsCallable('adminUpsertIncentiveProgram').call<Object?>({
      ...program,
      if (programId != null && programId.isNotEmpty) 'programId': programId,
    });
    final d = res.data;
    return d is Map ? '${d['programId'] ?? ''}' : '';
  }

  Future<void> setStage(String programId, String stage) async {
    await _fns.httpsCallable('adminSetIncentiveStage').call<Object?>({'programId': programId, 'stage': stage});
  }

  /// → бекор қилинган қолдиқ (сўм); 0 — аллақачон фаол эмас.
  Future<int> revokeGrant(String grantId, String reason) async {
    final res = await _fns.httpsCallable('adminRevokeIncentiveGrant').call<Object?>({'grantId': grantId, 'reason': reason});
    final d = res.data;
    return d is Map && d['amount'] is num ? (d['amount'] as num).toInt() : 0;
  }
}

/// Сервер хато кодлари → админ учун тушунарли матн (админ панели кирилл, конвенция бўйича).
String incentiveAdminError(Object e) {
  final code = e is FirebaseFunctionsException
      ? ((e.details is Map ? (e.details as Map)['code'] : null) ?? e.message ?? e.code).toString()
      : e.toString();
  const map = <String, String>{
    'VALIDATION_key': 'Калит: 2–40 та кичик лотин ҳарф, рақам ёки «_».',
    'VALIDATION_title_uz_Cyrl': 'Номи (кирилл) 1–80 белги бўлсин.',
    'VALIDATION_title_uz_Latn': 'Номи (лотин) 1–80 белги бўлсин.',
    'VALIDATION_title_ru': 'Номи (рус) 1–80 белги бўлсин.',
    'VALIDATION_stage': 'Босқич нотўғри.',
    'VALIDATION_internalPhones': 'Ички синов рақамлари нотўғри (998… шаклида, 50 тагача).',
    'VALIDATION_pilotDistrictIds': 'Туман ID лари нотўғри (50 тагача).',
    'VALIDATION_gender': 'Жинс нотўғри.',
    'VALIDATION_age': 'Ёш оралиғи нотўғри (0–120, «дан» ≤ «гача»).',
    'VALIDATION_newUsersSince': '«Янги фойдаланувчилар — шу санадан» майдони шарт.',
    'VALIDATION_amount': 'Миқдор — бутун сўм, 1 дан 10 000 000 гача.',
    'VALIDATION_buckets': 'Туркумлар нотўғри (калит такрорланмасин, миқдор бутун сўм).',
    'VALIDATION_buckets_sum': 'Туркумлар йиғиндиси умумий миқдорга тенг бўлиши шарт.',
    'VALIDATION_maxOrderSharePct': 'Буюртмадаги улуш 1–100% бўлсин.',
    'VALIDATION_validityDays': 'Муддат 1–3650 кун бўлсин.',
    'VALIDATION_budgetTotal': 'Умумий бюджет камида битта рағбат миқдорича бўлсин.',
    'VALIDATION_budgetTotal_below_granted': 'Умумий бюджетни аллақачон берилган суммадан камайтириб бўлмайди.',
    'VALIDATION_budgetDaily': 'Кунлик бюджет нотўғри (0 — чекловсиз).',
    'VALIDATION_endAt': 'Тугаш санаси бошланишдан кейин бўлсин.',
    'VALIDATION_reason': 'Сабабни ёзинг (камида 3 белги).',
    'PROGRAM_INVALID': 'Дастур топилмади.',
    'GRANT_NOT_FOUND': 'Рағбат топилмади.',
  };
  // Аввал АНИҚ мослик: `VALIDATION_budgetTotal_below_granted` ҳам `VALIDATION_budgetTotal` ни ўз ичига олади.
  final exact = map[code.trim()];
  if (exact != null) return exact;
  final byLength = map.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in byLength) {
    if (code.contains(k)) return map[k]!;
  }
  if (code.contains('permission-denied') || code.contains('Admin only')) return 'Рухсат йўқ (фақат админ).';
  return 'Амал бажарилмади. Қайта уриниб кўринг.';
}
