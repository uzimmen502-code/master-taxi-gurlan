import 'package:cloud_functions/cloud_functions.dart';

/// Оила боғланиши — ўзаро тасдиқ + бонус (эга 2026-11-28; сервер holiday-srv `family_links.js`).
/// Мижоз family_* коллекцияларини ЎҚИМАЙДИ (rules ёпиқ) — фақат callable'лар:
/// `getMyFamilyLinks`, `inviteSpouse`, `respondSpouseInvite`, `unlinkSpouse`, `inviteRelative`,
/// `respondRelativeInvite`, `unlinkRelative`. Оилавий ҳолат ҳеч қаерда сақланмайди.

/// Таклифда танланадиган муносабатлар (сервер `INVITE_RELATIONS`, турмуш ўртоғидан ташқари).
const kFamilyRelativeRelations = ['father', 'mother', 'brother', 'sister', 'son', 'daughter'];

/// Муносабат калити (lang): `fam_rel_<relation>`.
String familyRelationKey(String relation) => 'fam_rel_${relation.isEmpty ? 'sibling' : relation}';

class FamilyInvite {
  const FamilyInvite({
    required this.inviteId,
    required this.kind,
    required this.relation,
    this.name = '',
    this.fromName = '',
    this.status = 'pending',
    this.personId = '',
  });

  final String inviteId;

  /// 'spouse' | 'relative'.
  final String kind;

  /// Кирувчида — у МЕНГА ким; чиқувчида — мен уни ким деб кўрсатдим.
  final String relation;
  final String name;
  final String fromName;
  final String status;
  final String personId;

  bool get isSpouse => kind == 'spouse';
  bool get pending => status == 'pending';

  static FamilyInvite? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    final id = s(raw['inviteId']);
    final kind = s(raw['kind']);
    if (id.isEmpty || (kind != 'spouse' && kind != 'relative')) return null;
    return FamilyInvite(
      inviteId: id,
      kind: kind,
      relation: s(raw['relation']),
      name: s(raw['name']),
      fromName: s(raw['fromName']),
      status: s(raw['status']).isEmpty ? 'pending' : s(raw['status']),
      personId: s(raw['personId']),
    );
  }
}

class FamilyLink {
  const FamilyLink({required this.pairKey, required this.kind, required this.relation, this.name = ''});

  final String pairKey;
  final String kind;

  /// У менга ким.
  final String relation;
  final String name;

  bool get isSpouse => kind == 'spouse';

  static FamilyLink? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String s(Object? v) => v is String ? v.trim() : '';
    if (s(raw['pairKey']).isEmpty) return null;
    return FamilyLink(pairKey: s(raw['pairKey']), kind: s(raw['kind']), relation: s(raw['relation']), name: s(raw['name']));
  }
}

/// Дастур (фаол бўлса — сумма ва муддат; чегаралар фақат қариндошларда).
class FamilyProgram {
  const FamilyProgram({this.active = false, this.amount = 0, this.validityDays = 0, this.maxParents = 0, this.maxSiblings = 0});

  final bool active;
  final int amount;
  final int validityDays;
  final int maxParents;
  final int maxSiblings;

  static FamilyProgram fromMap(Object? raw) {
    if (raw is! Map || raw['active'] != true) return const FamilyProgram();
    int i(Object? v) => v is num ? v.toInt() : 0;
    return FamilyProgram(
      active: true,
      amount: i(raw['amount']),
      validityDays: i(raw['validityDays']),
      maxParents: i(raw['parents']),
      maxSiblings: i(raw['siblings']),
    );
  }
}

class FamilyState {
  const FamilyState({
    this.incoming = const [],
    this.outgoing = const [],
    this.links = const [],
    this.spouseProgram = const FamilyProgram(),
    this.relativeProgram = const FamilyProgram(),
  });

  static const empty = FamilyState();

  final List<FamilyInvite> incoming;
  final List<FamilyInvite> outgoing;
  final List<FamilyLink> links;
  final FamilyProgram spouseProgram;
  final FamilyProgram relativeProgram;

  FamilyLink? get spouse => links.where((l) => l.isSpouse).firstOrNull;
  List<FamilyLink> get relatives => [for (final l in links) if (!l.isSpouse) l];

  /// Кутаётган (ҳали жавоб берилмаган) чиқувчи турмуш ўртоғи таклифи — боғланмаган бўлса.
  FamilyInvite? get pendingSpouse => spouse != null ? null : outgoing.where((i) => i.isSpouse && i.pending).firstOrNull;

  /// Чиқувчи қариндош таклифлари (тасдиқланганлари — [relatives]да).
  List<FamilyInvite> get relativeInvites => [for (final i in outgoing) if (!i.isSpouse && i.status != 'accepted') i];

  bool get anyProgramActive => spouseProgram.active || relativeProgram.active;

  factory FamilyState.fromMap(Object? raw) {
    if (raw is! Map) return empty;
    List<T> list<T>(Object? v, T? Function(Object?) f) => [if (v is List) ...v.map(f).whereType<T>()];
    final p = raw['programs'] is Map ? raw['programs'] as Map : const {};
    return FamilyState(
      incoming: list(raw['incoming'], FamilyInvite.fromMap),
      outgoing: list(raw['outgoing'], FamilyInvite.fromMap),
      links: list(raw['links'], FamilyLink.fromMap),
      spouseProgram: FamilyProgram.fromMap(p['spouse']),
      relativeProgram: FamilyProgram.fromMap(p['relative']),
    );
  }
}

/// Форма хатолари (lang калитлари): исм 1..60, телефон 9/12 рақам, турмуш ўртоғида туғилган сана шарт.
List<String> familyInviteProblems({required String name, required String phone, String birthDate = '', bool spouse = false}) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  final okPhone = d.length == 9 || (d.length == 12 && d.startsWith('998'));
  return [
    if (name.trim().isEmpty || name.trim().length > 60) 'fam_err_name',
    if (!okPhone) 'fam_err_phone',
    if (spouse && birthDate.isEmpty) 'fam_err_birth',
  ];
}

/// Сервер хато коди → lang калити (номаълум — умумий).
String familyErrorKey(Object e) {
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    final code = d is Map ? '${d['code'] ?? ''}' : '';
    const known = {'SPOUSE_EXISTS', 'ALREADY_LINKED', 'RATE_LIMITED', 'CAP_REACHED', 'SPOUSE_TAKEN', 'SELF_INVITE', 'PHONE_INVALID', 'INVITE_CLOSED'};
    if (known.contains(code)) return 'fam_err_$code';
  }
  return 'fam_err_generic';
}

abstract class FamilyLinksApi {
  Future<FamilyState> load();
  Future<void> inviteSpouse({required String name, required String birthDate, required String phone, String personId = ''});
  Future<void> inviteRelative({required String name, required String phone, required String relation, String birthDate = '', String personId = ''});
  Future<String> respond(FamilyInvite invite, {required bool accept});
  Future<void> unlink(FamilyLink link);
}

class FirebaseFamilyLinksApi implements FamilyLinksApi {
  FirebaseFamilyLinksApi({FirebaseFunctions? functions}) : _fns = functions ?? FirebaseFunctions.instance;
  final FirebaseFunctions _fns;

  Future<Object?> _call(String name, Map<String, Object?> data) async => (await _fns.httpsCallable(name).call<Object?>(data)).data;

  @override
  Future<FamilyState> load() async => FamilyState.fromMap(await _call('getMyFamilyLinks', const {}));

  @override
  Future<void> inviteSpouse({required String name, required String birthDate, required String phone, String personId = ''}) =>
      _call('inviteSpouse', {'name': name.trim(), 'birthDate': birthDate, 'phone': phone, if (personId.isNotEmpty) 'personId': personId});

  @override
  Future<void> inviteRelative({required String name, required String phone, required String relation, String birthDate = '', String personId = ''}) =>
      _call('inviteRelative', {
        'name': name.trim(),
        'phone': phone,
        'relation': relation,
        if (birthDate.isNotEmpty) 'birthDate': birthDate,
        if (personId.isNotEmpty) 'personId': personId,
      });

  @override
  Future<String> respond(FamilyInvite invite, {required bool accept}) async {
    final r = await _call(invite.isSpouse ? 'respondSpouseInvite' : 'respondRelativeInvite', {'inviteId': invite.inviteId, 'accept': accept});
    return r is Map ? '${r['result'] ?? ''}' : '';
  }

  @override
  Future<void> unlink(FamilyLink link) =>
      _call(link.isSpouse ? 'unlinkSpouse' : 'unlinkRelative', {'pairKey': link.pairKey});
}
