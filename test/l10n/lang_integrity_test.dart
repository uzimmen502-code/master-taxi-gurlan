import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 3 тилли матн яхлитлиги (лойиҳа қоидаси: ҳар матн uz_Cyrl + uz_Latn + ru).
///
/// Бу тест БАРЧА калитларни текширади — янги калит қўшилганда ҳам ўзи
/// ушлайди: калитлар тўплами бир хил, `{param}` лар бир хил, лотин матнда
/// кирилл ҳарф ва рус матнда ўзбек ҳарфи (ў қ ғ ҳ) йўқ.
Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/lang/$lang.json').readAsStringSync())
        as Map<String, dynamic>;

final _param = RegExp(r'\{[a-zA-Z_]+\}');
final _cyrillic = RegExp('[Ѐ-ӿ]');
final _uzLetters = RegExp('[ўқғҳЎҚҒҲ]');

/// Эски (2026-10-24 га қадар) қайд қилинган истиснолар: валюта «сўм» кирилл
/// ёзилиши иловада қабул қилинган қоида (`currency_sum`), қолгани шунга
/// тегишли нарх шаблонлари. Бу рўйхатга ЯНГИ калит қўшилмайди.
const _legacyCyrillicInLatin = {
  'bread_flour_milk_cost',
  'bread_wallet_balance',
  'bread_wallet_cash_due',
  'bread_wallet_order_total',
  'bread_wallet_will_apply',
  'currency_sum',
  'marshrut_price_per_seat',
  'marshrut_seat_price_short',
  'non_promo_subtitle',
  'oil_price_from',
  'oil_price_from_multiline',
  'onb_car_bonus',
  'price_sum_short',
  'sum',
};
const _legacyUzbekInRu = {
  ..._legacyCyrillicInLatin,
  'wallet_will_zero',
  'bizprod_empty',
};
const _legacyEmpty = {
  'oil_section_reco_hint',
  'oil_section_types_end',
  'oil_section_types_hint',
  'oil_section_types_prefix',
};

void main() {
  final cyr = _load('uz_Cyrl');
  final lat = _load('uz_Latn');
  final ru = _load('ru');

  test('калитлар тўплами учала тилда бир хил', () {
    expect(lat.keys.toSet(), cyr.keys.toSet());
    expect(ru.keys.toSet(), cyr.keys.toSet());
  });

  test('{param} лар учала тилда бир хил', () {
    String p(Map<String, dynamic> m, String k) =>
        (_param.allMatches(m[k] as String).map((x) => x[0]!).toList()..sort())
            .join(',');
    for (final k in cyr.keys) {
      expect(p(lat, k), p(cyr, k), reason: '$k (uz_Latn)');
      expect(p(ru, k), p(cyr, k), reason: '$k (ru)');
    }
  });

  test('бўш матн йўқ (эски истиснолардан ташқари)', () {
    for (final k in cyr.keys) {
      if (_legacyEmpty.contains(k)) continue;
      for (final m in {'uz_Cyrl': cyr, 'uz_Latn': lat, 'ru': ru}.entries) {
        expect((m.value[k] as String).trim().isNotEmpty, isTrue,
            reason: '$k / ${m.key}');
      }
    }
  });

  test('лотин матнда кирилл ҳарф йўқ (эски истиснолардан ташқари)', () {
    for (final k in cyr.keys) {
      if (_legacyCyrillicInLatin.contains(k)) continue;
      expect(_cyrillic.hasMatch(lat[k] as String), isFalse,
          reason: '$k (uz_Latn): ${lat[k]}');
    }
  });

  test('рус матнда ўзбекча ҳарфлар (ў қ ғ ҳ) йўқ (эски истиснолардан ташқари)', () {
    for (final k in cyr.keys) {
      if (_legacyUzbekInRu.contains(k)) continue;
      expect(_uzLetters.hasMatch(ru[k] as String), isFalse,
          reason: '$k (ru): ${ru[k]}');
    }
  });

  test('кодда ишлатилган ҳар бир context.tr(\'калит\') матн файлида бор', () {
    // Ҳақиқий литерал калитлар (динамик `tr(var)` текширилмайди).
    final rx = RegExp(
        "\\.(?:tr|trMsg|translate)\\(\\s*'([a-z][a-z0-9_]*)'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('/admin_web/')) continue;
      // Изоҳ қаторлари (`/// context.tr('key')`) ҳисобга олинмайди.
      final text = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final m in rx.allMatches(text)) {
        final key = m.group(1)!;
        if (!cyr.containsKey(key)) missing.add('$key  ($path)');
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('controller/сервис қайтарадиган калитлар ("prefix_..." литераллар) файлда бор',
      () {
    // Контроллерлар `context.tr` эмас, калитни ЎЗИ қайтаради
    // (`error: 'drv_gps_required_online'`, `userMessage: 'tcs_open_failed'`),
    // шунинг учун юқоридаги тест уларни кўрмайди. Бу ерда ишончли префикслар:
    // 2026-10-24 аудитида киритилганлар (Firestore майдонлари билан тўқнашмайди).
    final rx = RegExp(
        "'((?:err|ob_ctl|ob_dev|ob_err|drv|loc_err|rpv|tcs|mdl_thread|rcpt|pos_err|"
        "crr_task_status|crr_route|sched_err|local_change)_[a-z0-9_]+)(?:\\||')");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('/admin_web/')) continue;
      final text = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final m in rx.allMatches(text)) {
        final key = m.group(1)!;
        if (!cyr.containsKey(key)) missing.add('$key  ($path)');
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
