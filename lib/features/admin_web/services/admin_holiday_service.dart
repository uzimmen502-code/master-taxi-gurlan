import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../supermarket/domain/sm_holiday.dart';
import 'admin_incentives_service.dart' show kFamilyBonusProgramIds;

/// «Байрам саватчаси» админ манбаи (сервер 5eb77906, `functions/holiday.js`). Ўқиш — Firestore (rules: админ
/// ҳаммасини ўқийди, `stage: off` ҳам); ёзиш — ФАҚАТ callable орқали (admin_audit, 41-банд):
/// `adminUpsertHolidayOccasion({occasion, reason?})`, `adminUpsertHolidayBasket({basket, reason?})`,
/// `adminUpsertRelativesBonusProgram({program, reason?})`.
abstract class AdminHolidayApi {
  Future<List<HolidayOccasion>> loadOccasions();
  Future<List<HolidayBasket>> loadBaskets();
  /// Оила бонуслари (эга 2026-11-28): dminGetFamilyBonusPrograms → {spouse_link, relative_link} (йўқ — null).
  Future<Map<String, FamilyBonusProgram?>> loadFamilyPrograms();
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''});
  Future<void> saveBasket(HolidayBasket b, {String reason = ''});
  Future<void> saveFamilyProgram(String programId, FamilyBonusProgram p, {String reason = ''});
}

class FirebaseAdminHolidayApi implements AdminHolidayApi {
  FirebaseAdminHolidayApi({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _fns = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _fns;

  @override
  Future<List<HolidayOccasion>> loadOccasions() async {
    final snap = await _db.collection('holiday_occasions').limit(100).get();
    final out = [for (final d in snap.docs) HolidayOccasion.fromMap(d.data(), id: d.id)].whereType<HolidayOccasion>().toList();
    out.sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.id.compareTo(b.id));
    return out;
  }

  @override
  Future<List<HolidayBasket>> loadBaskets() async {
    final snap = await _db.collection('holiday_baskets').limit(300).get();
    return [for (final d in snap.docs) HolidayBasket.fromMap(d.data(), id: d.id)].whereType<HolidayBasket>().toList();
  }

  @override
  Future<Map<String, FamilyBonusProgram?>> loadFamilyPrograms() async {
    final r = (await _fns.httpsCallable('adminGetFamilyBonusPrograms').call<Object?>(const {})).data;
    final m = r is Map && r['programs'] is Map ? r['programs'] as Map : const {};
    return {
      for (final id in kFamilyBonusProgramIds)
        id: m[id] is Map ? FamilyBonusProgram.fromMap(Map<String, dynamic>.from(m[id] as Map)) : null,
    };
  }

  Future<void> _call(String name, Map<String, dynamic> data) => _fns.httpsCallable(name).call<Object?>(data);

  @override
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''}) =>
      _call('adminUpsertHolidayOccasion', {'occasion': o.toAdminMap(), if (reason.trim().isNotEmpty) 'reason': reason.trim()});

  @override
  Future<void> saveBasket(HolidayBasket b, {String reason = ''}) =>
      _call('adminUpsertHolidayBasket', {'basket': b.toAdminMap(), if (reason.trim().isNotEmpty) 'reason': reason.trim()});

  @override
  Future<void> saveFamilyProgram(String programId, FamilyBonusProgram p, {String reason = ''}) => _call(
      'adminUpsertFamilyBonusProgram', {'programId': programId, 'program': p.toMap(programId), if (reason.trim().isNotEmpty) 'reason': reason.trim()});
}

/// `incentive_programs/relatives_birthdays` — сервер `BONUS_KEYS` (бутун сўм).
class RelativesBonusProgram {
  const RelativesBonusProgram({
    this.title = const {},
    this.stage = 'off',
    this.internalPhones = const [],
    this.pilotDistrictIds = const [],
    this.amount = 0,
    this.minRelatives = 3,
    this.minOrderAmount = 0,
    this.maxOrderSharePct = 30,
    this.validityDays = 90,
    this.budgetTotal = 0,
    this.grantedAmount = 0,
    this.grantedCount = 0,
  });

  final Map<String, String> title;
  final String stage;
  final List<String> internalPhones;
  final List<String> pilotDistrictIds;
  final int amount;
  final int minRelatives;
  final int minOrderAmount;
  final int maxOrderSharePct;
  final int validityDays;
  final int budgetTotal;

  /// Фақат кўрсатиш (сервер ҳисоблагичлари).
  final int grantedAmount;
  final int grantedCount;

  factory RelativesBonusProgram.fromMap(Map<String, dynamic> d) {
    int i(Object? v, int dflt) => v is num ? v.toInt() : dflt;
    List<String> l(Object? v) => [if (v is List) for (final x in v) '$x'];
    final t = d['title'] is Map ? d['title'] as Map : const {};
    final c = d['counters'] is Map ? d['counters'] as Map : const {};
    return RelativesBonusProgram(
      title: {for (final e in t.entries) '${e.key}': '${e.value}'},
      stage: kHolidayStages.contains(d['stage']) ? d['stage'] as String : 'off',
      internalPhones: l(d['internalPhones']),
      pilotDistrictIds: l(d['pilotDistrictIds']),
      amount: i(d['amount'], 0),
      minRelatives: i(d['minRelatives'], 3),
      minOrderAmount: i(d['minOrderAmount'], 0),
      maxOrderSharePct: i(d['maxOrderSharePct'], 30),
      validityDays: i(d['validityDays'], 90),
      budgetTotal: i(d['budgetTotal'], 0),
      grantedAmount: i(c['grantedAmount'], 0),
      grantedCount: i(c['grantedCount'], 0),
    );
  }

  Map<String, Object> toMap() => {
        'title': title,
        'stage': stage,
        'internalPhones': internalPhones,
        'pilotDistrictIds': pilotDistrictIds,
        'amount': amount,
        'minRelatives': minRelatives,
        'minOrderAmount': minOrderAmount,
        'maxOrderSharePct': maxOrderSharePct,
        'validityDays': validityDays,
        'budgetTotal': budgetTotal,
      };
}

/// Байрам формаси хатолари (админ панели — кирилл, конвенция; сервер `validateOccasion` нусхаси — тугма учун,
/// ҳақиқий текширув серверда). Бўш — сақласа бўлади.
List<String> holidayOccasionProblems(HolidayOccasion o) {
  final seen = <String>{};
  return [
    if (!kHolidayIdRe.hasMatch(o.id)) 'ID: кичик лотин ҳарф билан бошлансин, 2–40 белги (a-z, 0-9, _).',
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
      if ((o.names[l] ?? '').trim().isEmpty || (o.names[l] ?? '').trim().length > 60) 'Номи ($l) 1–60 белги бўлсин.',
    if (!kHolidayStages.contains(o.stage)) 'Босқич нотўғри.',
    if (o.remindDaysBefore < 1 || o.remindDaysBefore > 30) 'Эслатма 1–30 кун олдин бўлсин.',
    if (o.image.isNotEmpty && (!o.image.startsWith('https://') || o.image.length > 500)) 'Расм манзили https:// билан бошлансин.',
    if (!o.isBirthday && o.ruleType == 'fixed' && !holidayMdValid(o.md)) 'Сана ОО-КК шаклида бўлсин (масалан 03-21; 02-29 эмас).',
    if (!o.isBirthday && o.ruleType == 'list' && o.dates.length > 30) 'Саналар 30 тагача.',
    if (!o.isBirthday && o.ruleType == 'list')
      for (final d in o.dates)
        if (!holidayFullDateValid(d))
          'Сана нотўғри: «$d» (ЙЙЙЙ-ОО-КК).'
        else if (!seen.add(d))
          'Сана такрорланди: «$d».',
    if (!o.isBirthday && o.ruleType != 'fixed' && o.ruleType != 'list') 'Сана турини танланг.',
  ];
}

/// Саватча формаси хатолари (сервер `validateBasket` нусхаси).
List<String> holidayBasketProblems(HolidayBasket b) {
  final groups = <String>{};
  final out = <String>{
    if (!kHolidayIdRe.hasMatch(b.id)) 'ID: кичик лотин ҳарф билан бошлансин, 2–40 белги (a-z, 0-9, _).',
    if (!kHolidayIdRe.hasMatch(b.occasionId)) 'Байрамни танланг.',
    if (!kHolidayTiers.contains(b.tier)) 'Даража нотўғри.',
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
      if ((b.names[l] ?? '').trim().isEmpty || (b.names[l] ?? '').trim().length > 60) 'Номи ($l) 1–60 белги бўлсин.',
    if (b.baseGuests < 1 || b.baseGuests > kHolidayGuestsMax) 'Асосий меҳмонлар 1–$kHolidayGuestsMax.',
    if (b.items.isEmpty) 'Камида битта маҳсулот қўшинг.',
    if (b.items.length > 60) 'Маҳсулотлар 60 тагача.',
    for (final i in b.items) ...[
      if (i.groupId.isEmpty || i.qtyMilli <= 0) 'Ҳар маҳсулотда гуруҳ ва миқдор бўлсин.' else if (!groups.add(i.groupId)) 'Гуруҳ такрорланди: ${i.groupId}.',
      if (i.priority != 0 && (i.priority < 1 || i.priority > 9)) 'Устуворлик 1–9.',
    ],
  };
  return out.toList();
}

/// Бонус дастури формаси хатолари (сервер `validateBonusProgram` нусхаси).
List<String> relativesBonusProblems(RelativesBonusProgram p) => [
      for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
        if ((p.title[l] ?? '').trim().isEmpty || (p.title[l] ?? '').trim().length > 80) 'Номи ($l) 1–80 белги бўлсин.',
      if (!kHolidayStages.contains(p.stage)) 'Босқич нотўғри.',
      if (p.internalPhones.length > 50 || !p.internalPhones.every((x) => RegExp(r'^998\d{9}$').hasMatch(x)))
        'Ички синов рақамлари: 998XXXXXXXXX, 50 тагача.',
      if (p.pilotDistrictIds.length > 50 || !p.pilotDistrictIds.every((x) => RegExp(r'^[a-z0-9_-]{2,40}$').hasMatch(x)))
        'Пилот туман ID лари нотўғри.',
      if (p.amount < 1 || p.amount > 10000000) 'Бонус — 1 дан 10 000 000 сўмгача.',
      if (p.minRelatives < 1 || p.minRelatives > 20) 'Қариндошлар сони 1–20.',
      if (p.minOrderAmount < 0 || p.minOrderAmount > 100000000) 'Энг кам буюртма нотўғри.',
      if (p.maxOrderSharePct < 1 || p.maxOrderSharePct > 100) 'Буюртмадаги улуш 1–100%.',
      if (p.validityDays < 1 || p.validityDays > 365) 'Муддат 1–365 кун.',
      if (p.budgetTotal < (p.amount < 1 ? 1 : p.amount) || p.budgetTotal > 100000000000) 'Умумий бюджет камида битта бонус миқдорича.',
    ];

/// Сана майдони: ҳар қатор (ёки вергул) битта сана.
List<String> holidaySplitDates(String raw) =>
    [for (final s in raw.split(RegExp(r'[\n,;]'))) if (s.trim().isNotEmpty) s.trim()];

const kHolidayStageLabels = <String, String>{
  'off': 'Ўчиқ',
  'internal': 'Ички синов',
  'pilot': 'Пилот',
  'public': 'Ҳамма учун',
};

const kHolidayTierLabels = <String, String>{'simple': 'Оддий', 'medium': 'Ўрта', 'large': 'Катта'};

/// Оила бонус дастури (сервер `family_links.js` PROGRAM_KEYS; бутун сўм). Чегаралар — фақат `relative_link`.
class FamilyBonusProgram {
  const FamilyBonusProgram({
    this.title = const {},
    this.stage = 'off',
    this.internalPhones = const [],
    this.pilotDistrictIds = const [],
    this.amount = 0,
    this.minOrderAmount = 0,
    this.maxOrderSharePct = 100,
    this.validityDays = 30,
    this.budgetTotal = 0,
    this.maxParents = 2,
    this.maxSiblings = 15,
    this.grantedAmount = 0,
    this.grantedCount = 0,
  });

  /// Сукут (PROPOSED/эга): турмуш ўртоғи 10 000, қариндош 5 000; ота-она ≤2, ака-ука/опа-сингил ≤15; OFF.
  static FamilyBonusProgram defaults(String programId) => programId == 'spouse_link'
      ? const FamilyBonusProgram(title: {'uz_Cyrl': 'Турмуш ўртоғи бонуси', 'uz_Latn': 'Turmuş örtoği bonusi', 'ru': 'Бонус за супруга'}, amount: 10000, budgetTotal: 10000000)
      : const FamilyBonusProgram(title: {'uz_Cyrl': 'Қариндошлар бонуси', 'uz_Latn': 'Qarindoşlar bonusi', 'ru': 'Бонус за родственников'}, amount: 5000, budgetTotal: 10000000);

  final Map<String, String> title;
  final String stage;
  final List<String> internalPhones;
  final List<String> pilotDistrictIds;
  final int amount;
  final int minOrderAmount;
  final int maxOrderSharePct;
  final int validityDays;
  final int budgetTotal;
  final int maxParents;
  final int maxSiblings;
  final int grantedAmount;
  final int grantedCount;

  factory FamilyBonusProgram.fromMap(Map<String, dynamic> d) {
    int i(Object? v, int dflt) => v is num ? v.toInt() : dflt;
    List<String> l(Object? v) => [if (v is List) for (final x in v) '$x'];
    final t = d['title'] is Map ? d['title'] as Map : const {};
    final c = d['counters'] is Map ? d['counters'] as Map : const {};
    return FamilyBonusProgram(
      title: {for (final e in t.entries) '${e.key}': '${e.value}'},
      stage: kHolidayStages.contains(d['stage']) ? d['stage'] as String : 'off',
      internalPhones: l(d['internalPhones']),
      pilotDistrictIds: l(d['pilotDistrictIds']),
      amount: i(d['amount'], 0),
      minOrderAmount: i(d['minOrderAmount'], 0),
      maxOrderSharePct: i(d['maxOrderSharePct'], 100),
      validityDays: i(d['validityDays'], 30),
      budgetTotal: i(d['budgetTotal'], 0),
      maxParents: i(d['maxParents'], 2),
      maxSiblings: i(d['maxSiblings'], 15),
      grantedAmount: i(c['grantedAmount'], 0),
      grantedCount: i(c['grantedCount'], 0),
    );
  }

  Map<String, Object> toMap(String programId) => {
        'title': title,
        'stage': stage,
        'internalPhones': internalPhones,
        'pilotDistrictIds': pilotDistrictIds,
        'amount': amount,
        'minOrderAmount': minOrderAmount,
        'maxOrderSharePct': maxOrderSharePct,
        'validityDays': validityDays,
        'budgetTotal': budgetTotal,
        if (programId == 'relative_link') 'maxParents': maxParents,
        if (programId == 'relative_link') 'maxSiblings': maxSiblings,
      };
}

/// Оила бонус формаси хатолари (сервер `validateFamilyProgram` нусхаси).
List<String> familyBonusProblems(String programId, FamilyBonusProgram p) => [
      for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru'])
        if ((p.title[l] ?? '').trim().isEmpty || (p.title[l] ?? '').trim().length > 80) 'Номи ($l) 1–80 белги бўлсин.',
      if (!kHolidayStages.contains(p.stage)) 'Босқич нотўғри.',
      if (p.internalPhones.length > 50 || !p.internalPhones.every((x) => RegExp(r'^998\d{9}$').hasMatch(x)))
        'Ички синов рақамлари: 998XXXXXXXXX, 50 тагача.',
      if (p.pilotDistrictIds.length > 50 || !p.pilotDistrictIds.every((x) => RegExp(r'^[a-z0-9_-]{2,40}$').hasMatch(x)))
        'Пилот туман ID лари нотўғри.',
      if (p.amount < 1 || p.amount > 10000000) 'Бонус — 1 дан 10 000 000 сўмгача.',
      if (p.minOrderAmount < 0 || p.minOrderAmount > 100000000) 'Энг кам буюртма нотўғри.',
      if (p.maxOrderSharePct < 1 || p.maxOrderSharePct > 100) 'Буюртмадаги улуш 1–100%.',
      if (p.validityDays < 1 || p.validityDays > 365) 'Муддат 1–365 кун.',
      if (p.budgetTotal < (p.amount < 1 ? 1 : p.amount) || p.budgetTotal > 100000000000) 'Умумий бюджет камида битта бонус миқдорича.',
      if (programId == 'relative_link' && (p.maxParents < 0 || p.maxParents > 10)) 'Ота-она чегараси 0–10.',
      if (programId == 'relative_link' && (p.maxSiblings < 0 || p.maxSiblings > 50)) 'Ака-ука/опа-сингил чегараси 0–50.',
    ];