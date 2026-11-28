import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
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

/// «Яқинлар туғилган куни» бонус дастури (сервер 5eb77906 `incentive_programs/relatives_birthdays`, `kind`).
const kRelativesBonusProgramId = 'relatives_birthdays';

/// Умумий рағбат экранида таҳрирлаб бўлмайдиган дастур (ЯГОНА ёзиш йўли — `adminUpsertRelativesBonusProgram`).
/// Оила бонуслари (эга 2026-11-28): spouse_link / relative_link — ЯГОНА ёзиш йўли adminUpsertFamilyBonusProgram.
const kFamilyBonusProgramIds = ['spouse_link', 'relative_link'];

/// Машина суғуртаси бонуси (car_insurance.js `adminInsuranceSaveCampaign`; stage доим 'off').
const kCarInsuranceBonusProgramId = 'car_insurance_bonus';

/// Махсус дастурлар — сервер `SPECIAL_PROGRAM_IDS` кўзгуси (incentives.js, эга 2026-11-28).
const kSpecialIncentiveProgramIds = [kRelativesBonusProgramId, ...kFamilyBonusProgramIds, kCarInsuranceBonusProgramId];

/// Ўз модулида бошқариладиган дастур: рўйхатдаги ID ёки ҳужжатда ҳар қандай `kind` (сервер ҳам PROGRAM_SPECIAL).
bool incentiveProgramLocked(String id, Map<String, dynamic> data) =>
    kSpecialIncentiveProgramIds.contains(id) || '${data['kind'] ?? ''}'.trim().isNotEmpty;

/// Қулф матни: қайси админ бўлимида таҳрирланади (admin_shell ёрлиқлари).
String incentiveLockedWhere(String id, Map<String, dynamic> data) {
  final kind = '${data['kind'] ?? ''}'.trim();
  if (id == kCarInsuranceBonusProgramId || kind == kCarInsuranceBonusProgramId) return '«Автомобил суғуртаси» бўлимида';
  if (kSpecialIncentiveProgramIds.contains(id) || kSpecialIncentiveProgramIds.contains(kind)) return '«Байрам саватчаси» бўлимида';
  return 'ўз бўлимида';
}

// ── Форма ёрдамчилари (соф — тест учун; эга 2026-11-28 «Дастурни таҳрирлаш» соддалаштириш) ──

const _kTashkentOffset = Duration(hours: 5);

/// «Фақат янги фойдаланувчилар» ўчиқ: шу санадан олдинги чегара — ҳамма (эски ва янги) мос келади.
/// Сервер ўзгармайди (`newUsersSince` ≤ рўйхатдан ўтган вақт).
final int kIncentiveAllUsersSinceMs = DateTime.utc(2020, 1, 1).millisecondsSinceEpoch;

bool incentiveSinceMeansAll(int ms) => ms <= kIncentiveAllUsersSinceMs;

/// Тошкент куни бошланиши (00:00 UTC+5) — бошланиш ва «янгилар шу санадан».
int tashkentDayStartMs(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(_kTashkentOffset).millisecondsSinceEpoch;

/// Тошкент куни ТУГАШИ = кейинги кун 00:00 (сервер: `now >= endAt` → ENDED). Танланган кун ТЎЛИҚ киради.
int tashkentDayEndExclusiveMs(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day + 1).subtract(_kTashkentOffset).millisecondsSinceEpoch;

/// Вақт → Тошкент календар куни (маҳаллий DateTime 00:00 — фақат кун/ой/йил ишлатилади).
DateTime tashkentDateOf(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(_kTashkentOffset);
  return DateTime(t.year, t.month, t.day);
}

/// Сақланган `endAt` → охирги ТЎЛИҚ кирадиган кун (`endAt − 1 ms` нинг Тошкент куни). Эски (браузер ярим
/// тунида сақланган) ҳужжатда ҳам ҳақиқий маънони кўрсатади; санага тегилмаса қайта сақлашда вақт ўзгармайди.
DateTime incentiveEndInclusiveDay(int endAtMs) => tashkentDateOf(endAtMs - 1);

/// Лотин номдан калит: кичик ҳарф, ö→o ğ→g ş→sh ç→ch, бошқа белги → «_», 2–40 (сервер `KEY_RE`).
String incentiveKeyFromLatin(String latin) {
  var s = latin.toLowerCase();
  const map = {'ö': 'o', 'ğ': 'g', 'ş': 'sh', 'ç': 'ch'};
  map.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp("[ʻʼʽˈ`´‘’′']"), '');
  s = s.replaceAll(RegExp('[^a-z0-9]+'), '_').replaceAll(RegExp('_+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.length > 40) s = s.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
  return s.length >= 2 ? s : '';
}

final _kIncentiveKeyRe = RegExp(r'^[a-z0-9_]{2,40}$');

/// Калит хатоси (null — тўғри): формат, махсус ёки банд.
String? incentiveKeyError(String key, Set<String> existingIds) {
  if (!_kIncentiveKeyRe.hasMatch(key)) return 'Калит: 2–40 та кичик лотин ҳарф, рақам ёки «_».';
  if (kSpecialIncentiveProgramIds.contains(key)) return 'Бу калит махсус дастурга тегишли.';
  if (existingIds.contains(key)) return 'Бу калит банд — бошқа ном ёки калит танланг.';
  return null;
}

/// Кунлик бюджет хатоси (null — тўғри): 0 — чекловсиз; акс ҳолда миқдор ≤ кунлик ≤ умумий (сервер ҳам).
String? incentiveBudgetDailyError({required int amount, required int total, required int daily}) {
  if (daily == 0) return null;
  if (daily < 0) return 'Кунлик бюджет манфий бўлмасин.';
  if (daily < amount) return 'Кунлик бюджет камида битта кишининг миқдорича бўлсин (0 — чекловсиз).';
  if (daily > total) return 'Кунлик бюджет умумий бюджетдан ошмасин.';
  return null;
}

/// Карточкадаги «Кимга» қатори: жинс · ёш (чекловсиз бўлса — кўрсатилмайди) · машина · янгилар.
String incentiveAudienceText(Map<String, dynamic> aud) {
  int n(Object? v) => v is num ? v.toInt() : 0;
  final gender = '${aud['gender'] ?? 'any'}';
  final min = n(aud['ageMin']);
  final max = aud['ageMax'] == null ? 120 : n(aud['ageMax']);
  final hasMax = max > 0 && max < 120;
  final age = min > 0 && hasMax
      ? '$min–$max ёш'
      : min > 0
          ? '$min ёшдан'
          : hasMax
              ? '$max ёшгача'
              : '';
  final since = aud['newUsersSince'];
  var sinceText = '';
  if (since is Timestamp) {
    final ms = since.millisecondsSinceEpoch;
    if (incentiveSinceMeansAll(ms)) {
      sinceText = 'эски ва янги фойдаланувчилар';
    } else {
      final d = tashkentDateOf(ms);
      sinceText = 'янгилар: ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} дан';
    }
  }
  return [
    gender == 'female' ? 'аёллар' : gender == 'male' ? 'эркаклар' : 'ҳамма',
    if (age.isNotEmpty) age,
    if (aud['requireCar'] == true) 'машина профили шарт',
    if (sinceText.isNotEmpty) sinceText,
  ].join(' · ');
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
    'VALIDATION_budgetDaily': 'Кунлик бюджет: 0 (чекловсиз) ёки битта киши миқдоридан умумий бюджетгача.',
    'PROGRAM_SPECIAL': 'Бу махсус дастур — ўз бўлимида таҳрирланади.',
    'PROGRAM_KEY_TAKEN': 'Бу калит банд — бошқа калит танланг.',
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
