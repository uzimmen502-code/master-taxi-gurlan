import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/utils/uz_script.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_admin_screen.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_subtypes.dart';
import 'package:flutter_test/flutter_test.dart';

/// 30 фаолият тури ва уларнинг аниқроқ турлари (эга, 2026-11-01).
void main() {
  const langs = ['uz_Cyrl', 'uz_Latn', 'ru'];
  Map<String, dynamic> lang(String l) =>
      jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

  group('Жадвал', () {
    test('30 турнинг ҳар бирида аниқроқ турлар бор; тур ичида такрор йўқ; эга рўйхати тартиби', () {
      expect(BusinessCategory.values.length, 30);
      expect(BusinessSubtypes.data.keys.toSet(), BusinessCategory.values.toSet());
      for (final c in BusinessCategory.values) {
        final list = BusinessSubtypes.data[c]!;
        expect(list, isNotEmpty, reason: c.wire);
        final norms = [for (final e in list) BusinessSubtypes.norm(e.$1)];
        expect(norms.toSet().length, norms.length, reason: '${c.wire}: такрор');
      }
      // Чегара: рўйхат боши ва охири эга матнидагидек.
      expect(BusinessSubtypes.of(BusinessCategory.retail, 'uz_Cyrl').first, 'Озиқ-овқат дўкони');
      expect(BusinessSubtypes.of(BusinessCategory.retail, 'uz_Cyrl').last, 'Ижтимоий тармоқ орқали савдо');
      expect(BusinessSubtypes.of(BusinessCategory.other, 'uz_Cyrl').last, 'Янги пайдо бўладиган бизнес моделлари');
    });

    test('ҳар бир ном 3 тилда бўш эмас ва ≤60 белги (сервер subtypeMax), бош ҳарф билан', () {
      for (final c in BusinessCategory.values) {
        for (final l in langs) {
          for (final n in BusinessSubtypes.of(c, l)) {
            expect(n.trim(), isNotEmpty, reason: '${c.wire}/$l');
            expect(n.length, lessThanOrEqualTo(60), reason: '${c.wire}/$l: $n');
            expect(n[0], n[0].toUpperCase(), reason: '${c.wire}/$l: $n');
          }
        }
        // Рус таржимаси кириллда (лотин эмас) ёзилган — `IT`, `CRM`, `SMM`, `PR`, `HR`, `DJ` бундан мустасно.
        for (final e in BusinessSubtypes.data[c]!) {
          expect(UzScript.hasCyrillic(e.$2) || RegExp(r'^[A-Z]{2,3}$').hasMatch(e.$2), isTrue, reason: e.$2);
        }
      }
    });

    test('лотин номи кириллдан ўгирилади (alohida yozilmaydi)', () {
      expect(BusinessSubtypes.of(BusinessCategory.retail, 'uz_Latn').first, "Oziq-ovqat do'koni");
      expect(BusinessSubtypes.of(BusinessCategory.auto, 'uz_Latn'), contains("G'ildirak balansirovkasi"));
      expect(BusinessSubtypes.of(BusinessCategory.retail, 'ru').first, 'Продуктовый магазин');
    });
  });

  group('Матн калитлари (3 тил) ва админ', () {
    test('30 тур: тўлиқ ном 3 тилда; қисқа ном ЙЎҚ (эга, 2026-11-03); эски 4 калит йўқ', () {
      for (final l in langs) {
        final m = lang(l);
        for (final c in BusinessCategory.values) {
          final full = m[c.labelKey] as String?;
          expect(full, isNotNull, reason: '$l ${c.labelKey}');
          expect(m.containsKey('business_cat_short_${c.wire}'), isFalse, reason: '$l ${c.wire}: қисқа ном қайтмасин');
        }
        for (final old in BusinessCategory.legacyWires.keys) {
          expect(m.containsKey('business_cat_$old'), isFalse, reason: '$l: эски калит қолган');
        }
        for (final c in BusinessCategory.values) {
          final k = BusinessSubtypes.noteKey(c);
          if (k != null) expect(m[k], isA<String>(), reason: '$l $k');
        }
        expect(m['bizmap_f_category_hint'], isA<String>());
      }
      // Эга номлари (рақамланган рўйхат) — кирилл матн айнан шу.
      final cyr = lang('uz_Cyrl');
      expect(cyr['business_cat_retail'], 'Савдо ва дўконлар');
      expect(cyr['business_cat_auto'], 'Автомобиль ва транспортга хизмат кўрсатиш');
      expect(cyr['business_cat_other'], 'Бошқа ва янги бизнес турлари');
    });

    test('изоҳ фақат тиббиёт ва молияда', () {
      expect([for (final c in BusinessCategory.values) if (BusinessSubtypes.noteKey(c) != null) c],
          [BusinessCategory.health, BusinessCategory.finance]);
    });

    test('админдаги номлар uz_Cyrl матни билан бир хил (битта манба)', () {
      final cyr = lang('uz_Cyrl');
      for (final c in BusinessCategory.values) {
        expect(adminBusinessCategoryLabel(c), cyr[c.labelKey], reason: c.wire);
      }
    });
  });

  group('Қидирув', () {
    String label(BusinessCategory c) => c.labelKey; // тестда матн = калит

    test('аниқроқ тури: тур танланган — фақат шу тур; бўш сўров — бутун рўйхат', () {
      final all = BusinessSubtypes.subtypeOptions('', 'uz_Cyrl', category: BusinessCategory.auto);
      expect(all.length, BusinessSubtypes.data[BusinessCategory.auto]!.length);
      expect(all.every((o) => o.category == BusinessCategory.auto), isTrue);
      final q = BusinessSubtypes.subtypeOptions('шин', 'uz_Cyrl', category: BusinessCategory.auto);
      expect([for (final o in q) o.subtype], ['Шиномонтаж', 'Шина таъмири', 'Шина савдоси']);
      expect(BusinessSubtypes.subtypeOptions('шин', 'uz_Cyrl', category: BusinessCategory.food), isEmpty);
    });

    test('тур танланмаган: бўш сўров — ҳеч нарса; сўз — 30 турнинг ҳаммасидан (кирилл, лотин, рус)', () {
      expect(BusinessSubtypes.subtypeOptions('', 'uz_Cyrl'), isEmpty);
      final cyr = BusinessSubtypes.subtypeOptions('дорих', 'uz_Cyrl');
      expect({for (final o in cyr) o.category},
          {BusinessCategory.retail, BusinessCategory.health, BusinessCategory.animals}); // + «Ветеринар дорихонаси»
      expect([for (final o in cyr) o.subtype].take(2), ['Дорихона', 'Дорихона'], reason: 'бошидан мослари олдин');
      final lat = BusinessSubtypes.subtypeOptions('dorix', 'uz_Latn');
      expect([for (final o in lat) o.subtype], ['Dorixona', 'Dorixona', 'Veterinar dorixonasi']);
      final ru = BusinessSubtypes.subtypeOptions('аптек', 'ru');
      expect([for (final o in ru) o.subtype], containsAll(['Аптека', 'Ветеринарная аптека']));
    });

    test('бошидан мос келганлар олдин', () {
      final o = BusinessSubtypes.subtypeOptions('таъмир', 'uz_Cyrl', category: BusinessCategory.construction);
      expect(o.first.subtype, 'Таъмирлаш');
    });

    test('фаолият тури: бўш — 30 та тартиб билан; ном бўйича; аниқроқ тур бўйича (тур + тур номи)', () {
      final all = BusinessSubtypes.categoryOptions('', 'uz_Cyrl', label);
      expect([for (final o in all) o.category], BusinessCategory.values);
      expect(all.every((o) => o.subtype == null), isTrue);

      final byName = BusinessSubtypes.categoryOptions('business_cat_real', 'uz_Cyrl', label);
      expect(byName.single.category, BusinessCategory.realEstate);

      final bySub = BusinessSubtypes.categoryOptions('шиномонтаж', 'uz_Cyrl', label);
      expect(bySub.single, (category: BusinessCategory.auto, subtype: 'Шиномонтаж'));
      expect(BusinessSubtypes.categoryOptions('йўқ-бундай-тур', 'uz_Cyrl', label), isEmpty);
    });
  });

  group('Кўрсатиш ва тур алмашиши', () {
    test('display: тайёр ном кўрувчи тилида; эркин матн ўзгармайди', () {
      expect(BusinessSubtypes.display('Шиномонтаж', 'ru'), 'Шиномонтаж');
      expect(BusinessSubtypes.display('Дорихона', 'ru', category: BusinessCategory.health), 'Аптека');
      expect(BusinessSubtypes.display('Аптека', 'uz_Cyrl'), 'Дорихона');
      expect(BusinessSubtypes.display("Oziq-ovqat do'koni", 'uz_Cyrl'), 'Озиқ-овқат дўкони');
      expect(BusinessSubtypes.display('Супермаркет', 'uz_Latn'), 'Supermarket');
      expect(BusinessSubtypes.display('Бобомнинг устахонаси', 'ru'), 'Бобомнинг устахонаси');
      expect(BusinessSubtypes.display('', 'ru'), '');
    });

    test('fits: бўш ва ўз матни — ҳа; шу турнинг тайёр номи — ҳа; бошқа турнинг тайёр номи — йўқ', () {
      expect(BusinessSubtypes.fits('', BusinessCategory.auto), isTrue);
      expect(BusinessSubtypes.fits('Менинг матним', BusinessCategory.auto), isTrue);
      expect(BusinessSubtypes.fits('Шиномонтаж', BusinessCategory.auto), isTrue);
      expect(BusinessSubtypes.fits('Супермаркет', BusinessCategory.auto), isFalse);
      expect(BusinessSubtypes.fits('Аптека', BusinessCategory.health), isTrue, reason: 'русча ҳам танилади');
    });
  });
}
