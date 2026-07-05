import '../../../models/relative_person.dart';

/// Nasab daraxtini GEDCOM 5.5 matniga aylantiradi (export / zaxira).
class GedcomExporter {
  GedcomExporter._();

  static String build({
    required List<RelativePerson> people,
    String appName = 'AVA Gurlan',
  }) {
    final byId = {for (final p in people) p.id: p};
    final famIds = <String, String>{};
    final famChildren = <String, List<String>>{};
    final famSpouses = <String, ({String? husb, String? wife})>{};

    String indiXref(String personId) => '@I${_safeId(personId)}@';

    String famXrefForParents(String? fatherId, String? motherId) {
      final parts = [fatherId ?? '', motherId ?? '']..sort();
      final key = 'P:${parts[0]}|${parts[1]}';
      return famIds.putIfAbsent(key, () => '@F${_safeId(key)}@');
    }

    String famXrefForCouple(String a, String b) {
      final parts = [a, b]..sort();
      final key = 'C:${parts[0]}|${parts[1]}';
      return famIds.putIfAbsent(key, () => '@F${_safeId(key)}@');
    }

    for (final p in people) {
      if (p.fatherId != null || p.motherId != null) {
        final fx = famXrefForParents(p.fatherId, p.motherId);
        famChildren.putIfAbsent(fx, () => []).add(p.id);
        famSpouses[fx] = (husb: p.fatherId, wife: p.motherId);
      }
      final sp = p.spouseId;
      if (sp != null && sp.isNotEmpty && byId.containsKey(sp)) {
        final fx = famXrefForCouple(p.id, sp);
        final other = byId[sp]!;
        String? husb;
        String? wife;
        if (p.gender == 'male') husb = p.id;
        if (p.gender == 'female') wife = p.id;
        if (other.gender == 'male') husb = other.id;
        if (other.gender == 'female') wife = other.id;
        husb ??= p.id;
        wife ??= sp;
        famSpouses[fx] = (husb: husb, wife: wife);
      }
    }

    final buf = StringBuffer()
      ..writeln('0 HEAD')
      ..writeln('1 SOUR $appName')
      ..writeln('2 VERS 1.0')
      ..writeln('1 GEDC')
      ..writeln('2 VERS 5.5')
      ..writeln('2 FORM LINEAGE-LINKED')
      ..writeln('1 CHAR UTF-8')
      ..writeln('1 DATE ${_gedDate(DateTime.now())}');

    for (final p in people) {
      if (p.fullName.trim().isEmpty) continue;
      buf.writeln('0 ${indiXref(p.id)} INDI');
      buf.writeln('1 NAME ${_gedName(p.fullName)}');
      final sex = _gedSex(p.gender);
      if (sex.isNotEmpty) buf.writeln('1 SEX $sex');
      if (p.birthDate != null) {
        buf.writeln('1 BIRT');
        buf.writeln('2 DATE ${_gedDate(p.birthDate!)}');
      }
      if (p.notes.trim().isNotEmpty) {
        buf.writeln('1 NOTE ${_escape(p.notes.trim())}');
      }
      if (p.relationDegree.trim().isNotEmpty) {
        buf.writeln('1 OCCU ${_escape(p.relationDegree.trim())}');
      }
      if (p.fatherId != null || p.motherId != null) {
        buf.writeln('1 FAMC ${famXrefForParents(p.fatherId, p.motherId)}');
      }
      final sp = p.spouseId;
      if (sp != null && sp.isNotEmpty && byId.containsKey(sp)) {
        buf.writeln('1 FAMS ${famXrefForCouple(p.id, sp)}');
      }
    }

    for (final entry in famSpouses.entries) {
      buf.writeln('0 ${entry.key} FAM');
      final h = entry.value.husb;
      final w = entry.value.wife;
      if (h != null && byId.containsKey(h)) {
        buf.writeln('1 HUSB ${indiXref(h)}');
      }
      if (w != null && byId.containsKey(w)) {
        buf.writeln('1 WIFE ${indiXref(w)}');
      }
      for (final cid in (famChildren[entry.key] ?? const <String>[]).toSet()) {
        if (byId.containsKey(cid)) {
          buf.writeln('1 CHIL ${indiXref(cid)}');
        }
      }
    }

    buf.writeln('0 TRLR');
    return buf.toString();
  }

  static String _safeId(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  static String _gedName(String fullName) {
    final t = fullName.trim();
    if (t.isEmpty) return '/ /';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length == 1) return '$t //';
    final surname = parts.last;
    final given = parts.sublist(0, parts.length - 1).join(' ');
    return '$given /$surname/';
  }

  static String _gedSex(String gender) {
    if (gender == 'male') return 'M';
    if (gender == 'female') return 'F';
    return 'U';
  }

  static String _gedDate(DateTime d) => '${d.day} ${_month(d.month)} ${d.year}';

  static String _month(int m) => const [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ][m - 1];

  static String _escape(String s) =>
      s.replaceAll('\n', ' ').replaceAll('\r', ' ');
}
