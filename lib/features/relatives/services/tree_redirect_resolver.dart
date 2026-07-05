import '../../../models/relative_person.dart';
import '../../../models/tree_person.dart';

typedef TreeRedirectMap = Map<String, String>;

/// `tree_redirects` zanjirini hal qilish (merge/link eski id).
String? resolveTreePersonId(String? id, TreeRedirectMap redirects) {
  if (id == null || id.isEmpty) return id;
  final seen = <String>{};
  var cur = id;
  while (redirects.containsKey(cur) && seen.add(cur)) {
    final next = redirects[cur]!;
    if (next.isEmpty || next == cur) break;
    cur = next;
  }
  return cur;
}

RelativePerson resolvePersonLinks(
  RelativePerson person,
  TreeRedirectMap redirects,
) {
  return RelativePerson(
    id: person.id,
    fullName: person.fullName,
    photoUrl: person.photoUrl,
    photoPath: person.photoPath,
    phone: person.phone,
    address: person.address,
    birthDate: person.birthDate,
    gender: person.gender,
    relationDegree: person.relationDegree,
    side: person.side,
    notes: person.notes,
    fatherId: resolveTreePersonId(person.fatherId, redirects),
    motherId: resolveTreePersonId(person.motherId, redirects),
    spouseId: resolveTreePersonId(person.spouseId, redirects),
    isSelf: person.isSelf,
    createdAt: person.createdAt,
  );
}

/// Nasab dropdown / daraxt chizish uchun: shaxsiy + komponent, redirect manbalari chiqariladi.
List<RelativePerson> buildLinkCandidates({
  required List<RelativePerson> personal,
  required List<TreePerson> component,
  required TreeRedirectMap redirects,
  String? excludeId,
}) {
  final redirectSources = redirects.keys.toSet();
  final byId = <String, RelativePerson>{};

  for (final n in component) {
    if (redirectSources.contains(n.id)) continue;
    byId[n.id] = n.toRelativePerson();
  }
  for (final p in personal) {
    if (redirectSources.contains(p.id)) continue;
    final comp = byId[p.id];
    if (comp != null) {
      byId[p.id] = RelativePerson(
        id: p.id,
        fullName: comp.fullName.isNotEmpty ? comp.fullName : p.fullName,
        photoUrl: comp.photoUrl.isNotEmpty ? comp.photoUrl : p.photoUrl,
        photoPath: p.photoPath,
        phone: p.phone,
        address: p.address,
        birthDate: comp.birthDate ?? p.birthDate,
        gender: comp.gender.isNotEmpty ? comp.gender : p.gender,
        relationDegree: p.relationDegree,
        side: p.side,
        notes: p.notes,
        fatherId: comp.fatherId ?? p.fatherId,
        motherId: comp.motherId ?? p.motherId,
        spouseId: comp.spouseId ?? p.spouseId,
        isSelf: p.isSelf,
        createdAt: p.createdAt,
      );
    } else {
      byId[p.id] = p;
    }
  }

  final list = byId.values
      .where((p) => p.id != excludeId && p.fullName.trim().isNotEmpty)
      .toList(growable: false);
  list.sort((a, b) => a.fullName.compareTo(b.fullName));
  return list;
}

String normPersonName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? birthDateKey(DateTime? d) {
  if (d == null) return null;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Dedup guruhlari: ism + (sana) + (jins).
List<List<TreePerson>> findDuplicateGroups(List<TreePerson> nodes) {
  final byKey = <String, List<TreePerson>>{};
  for (final n in nodes) {
    final name = normPersonName(n.fullName);
    if (name.isEmpty) continue;
    final bd = birthDateKey(n.birthDate);
    final g = n.gender.trim();
    final key = bd != null && bd.isNotEmpty
        ? '$name|$bd|${g.isEmpty ? '?' : g}'
        : g.isNotEmpty
            ? '$name||$g'
            : name;
    byKey.putIfAbsent(key, () => []).add(n);
  }
  return byKey.values
      .where((g) => g.length > 1)
      .toList(growable: false);
}

String duplicateGroupLabel(List<TreePerson> group) {
  final first = group.first;
  final parts = <String>[first.fullName];
  if (first.birthDate != null) {
    final d = first.birthDate!;
    parts.add(
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}');
  }
  if (first.gender.isNotEmpty) {
    parts.add(first.gender == 'male' ? 'Эркак' : 'Аёл');
  }
  return parts.join(' · ');
}
