/// Сайдбар қатори: гуруҳ сарлавҳаси ёки бўлим (кўринадиган рўйхатдаги
/// индекси).
class GroupedRow {
  const GroupedRow.header(this.group) : index = -1;
  const GroupedRow.item(this.index) : group = '';

  final String group;
  final int index;

  bool get isHeader => index < 0;
}

/// [groups] — ҳар бир бўлимнинг гуруҳи (`''` — сарлавҳасиз). Сарлавҳа гуруҳ
/// ўзгарган жойда бир марта қўйилади. Рўйхат роль бўйича фильтрлангандан
/// КЕЙИН қурилади — роли кўрмайдиган (бўш) гуруҳнинг сарлавҳаси чиқмайди.
List<GroupedRow> groupedRows(List<String> groups) {
  final rows = <GroupedRow>[];
  String? prev;
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    if (g.isNotEmpty && g != prev) rows.add(GroupedRow.header(g));
    rows.add(GroupedRow.item(i));
    prev = g;
  }
  return rows;
}
