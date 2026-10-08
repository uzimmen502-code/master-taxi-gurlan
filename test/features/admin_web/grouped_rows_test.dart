import 'package:ava_gurlan/features/admin_web/utils/grouped_rows.dart';
import 'package:flutter_test/flutter_test.dart';

/// Админ сайдбари: ўзаро боғлиқ бўлимлар гуруҳ сарлавҳаси остида (эга,
/// 2026-10-08).
void main() {
  String render(List<GroupedRow> rows) =>
      rows.map((r) => r.isHeader ? '[${r.group}]' : '${r.index}').join(' ');

  test('сарлавҳа гуруҳ алмашган жойда бир марта; бўш гуруҳ — сарлавҳасиз', () {
    final rows = groupedRows(['', 'Такси', 'Такси', 'Бозорлар']);
    expect(render(rows), '0 [Такси] 1 2 [Бозорлар] 3');
  });

  test('индекслар кўринадиган рўйхатга мос (танлов бузилмайди)', () {
    final rows = groupedRows(['A', 'A', 'B']);
    expect(rows.where((r) => !r.isHeader).map((r) => r.index), [0, 1, 2]);
  });

  test('роль бўйича фильтрланган рўйхат — кўринмайдиган гуруҳ сарлавҳаси йўқ',
      () {
    // finance: «Молия» гуруҳидан бошқа ҳеч нарса кўринмайди.
    expect(render(groupedRows(['Молия', 'Молия'])), '[Молия] 0 1');
    expect(groupedRows(const []), isEmpty);
  });

  test('бир хил гуруҳ орасида бошқа гуруҳ бўлса — иккинчи марта сарлавҳа', () {
    expect(render(groupedRows(['A', 'B', 'A'])), '[A] 0 [B] 1 [A] 2');
  });
}
