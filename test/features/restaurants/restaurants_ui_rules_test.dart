// UI/UX аудит (2026-10-24) қоидалари манба кодида қулфланади: ресторан занжирида
// 12 px дан кичик шрифт, иконка ўрнида эмодзи ва курьер карталарида қаттиқ кулранг/тўқ сариқ ранглар қайтиб келмасин.
// Истисно: меню рейлидаги категория номи — `fitCategoryFontSize` (эга қарори: сўз бўлинмаслиги учун 10.5 гача) —
// у `fontSize:` литерали эмас, шунинг учун бу текширувга тушмайди.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

/// Изоҳ қаторларисиз кодни қайтаради (қатор рақами билан).
List<MapEntry<int, String>> _codeLines(File f) {
  final out = <MapEntry<int, String>>[];
  final lines = f.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trimLeft();
    if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) continue;
    out.add(MapEntry(i + 1, lines[i]));
  }
  return out;
}

void main() {
  const root = 'lib/features/restaurants';

  test('12 px дан кичик fontSize литерали йўқ', () {
    final bad = <String>[];
    final re = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)');
    for (final f in _dartFiles(root)) {
      for (final l in _codeLines(f)) {
        for (final m in re.allMatches(l.value)) {
          if (double.parse(m.group(1)!) < 12) bad.add('${f.path}:${l.key}');
        }
      }
    }
    expect(bad, isEmpty, reason: '12 px дан кичик матн ўқилмайди: ${bad.join(', ')}');
  });

  test('иконка ўрнида эмодзи йўқ (Material иконка ишлатилади)', () {
    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true);
    final bad = <String>[];
    for (final f in _dartFiles(root)) {
      for (final l in _codeLines(f)) {
        if (emoji.hasMatch(l.value)) bad.add('${f.path}:${l.key}');
      }
    }
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('курьер карталарида қаттиқ кулранг/тўқ сариқ ранг йўқ (токенлар ишлатилади)', () {
    final re = RegExp(r'Colors\.(grey|orange|black87)\b');
    final bad = <String>[];
    for (final f in _dartFiles('$root/courier')) {
      for (final l in _codeLines(f)) {
        if (re.hasMatch(l.value)) bad.add('${f.path}:${l.key}');
      }
    }
    expect(bad, isEmpty, reason: bad.join(', '));
  });
}
