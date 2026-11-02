// S0 (2026-11-03): фаолият тури профили — «Менинг бизнесим» занжири шартномаси.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_subtypes.dart';
import 'package:ava_gurlan/features/business_map/domain/business_type_profile.dart';
import 'package:ava_gurlan/features/business_map/domain/product_kind.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;

Business _biz(BusinessCategory c, {String subtype = '', String id = 'b1', bool online = false}) => Business(
      id: id,
      ownerId: '998901234567',
      name: 'Test',
      category: c,
      phone: '998901234567',
      lat: 41.5,
      lng: 60.6,
      subtype: subtype,
      online: online,
    );

/// Профилнинг ҳамма матн калитлари (экранлар шуларни ишлатади).
Set<String> _keysOf(BusinessTypeProfile p) => {
      p.catalogTitleKey,
      p.emptyStateKey,
      p.nextStepTitleKey,
      p.nextStepSubtitleKey,
      p.nextStepCtaKey,
      if (p.licenceNoteKey != null) p.licenceNoteKey!,
      if (p.moduleBridge != null) p.moduleBridge!.ctaKey,
      for (final u in p.priceUnits) u.labelKey,
      for (final u in p.priceUnits)
        if (u.suffixKey != null) u.suffixKey!,
    };

/// Профилда бўлмаган, лекин S1/S3/S5 учун шу слайсда қўшилган калитлар.
const _reservedKeys = [
  'biz_next_title',
  'biz_next_hero_map',
  'biz_next_hero_online',
  'biz_next_progress',
  'biz_next_step_placed',
  'biz_next_step_online',
  'biz_next_offer_count',
  'biz_next_step_preview',
  'biz_next_step_share',
  'biz_next_step_share_sub',
  'biz_next_step_chats',
  'biz_next_quick_title',
  'biz_next_quick_sub',
  'biz_next_manage',
  'biz_next_later',
  'biz_open_services',
  'biz_open_page',
  'biz_customer_view',
  'biz_link_qr',
  'home_section_see_all',
];

void main() {
  final langs = {'uz_Cyrl': _load('uz_Cyrl'), 'uz_Latn': _load('uz_Latn'), 'ru': _load('ru')};

  group('қамров', () {
    test('30 турнинг ҳар бирида профил бор, шаблонлар 2–4 та', () {
      expect(BusinessCategory.values.length, 30);
      for (final c in BusinessCategory.values) {
        final p = BusinessTypeProfile.of(c);
        expect(p.category, c);
        expect(p.subtype, '');
        expect(p.templates.length, inInclusiveRange(2, 4), reason: c.wire);
        expect(p.priceUnits, contains(p.defaultPriceUnit), reason: c.wire);
        expect(p.priceUnits, contains(PriceUnit.fixed), reason: c.wire);
      }
    });

    test('ҳар бир аниқроқ тур учун ҳам профил ишлайди (ҳеч бири синмайди)', () {
      for (final c in BusinessCategory.values) {
        for (final (uz, ru) in BusinessSubtypes.data[c]!) {
          final a = BusinessTypeProfile.of(c, subtype: uz);
          final b = BusinessTypeProfile.of(c, subtype: ru);
          expect(a.subtype, uz, reason: '${c.wire} $uz');
          expect(b.subtype, uz, reason: '${c.wire} $ru → uz_Cyrl');
          expect(a.defaultKind, b.defaultKind);
          expect(a.templates.length, inInclusiveRange(2, 4), reason: '${c.wire} $uz');
          expect(a.priceUnits, contains(a.defaultPriceUnit), reason: '${c.wire} $uz');
        }
      }
    });
  });

  group('таклиф тури', () {
    test('auto хизмат аниқроқ турлари → service', () {
      for (final s in [
        'Автосервис',
        'Шиномонтаж',
        'Автоювиш',
        'Мой алмаштириш',
        'Компьютер диагностикаси',
        'Кузов таъмири',
        'Эвакуатор',
        'Электромобиль қувватлаш станцияси',
      ]) {
        final p = BusinessTypeProfile.of(BusinessCategory.auto, subtype: s);
        expect(p.defaultKind, OfferKind.service, reason: s);
        expect(p.group, BusinessOfferGroup.services, reason: s);
        expect(p.catalogTitleKey, 'biz_catalog_services', reason: s);
        expect(defaultProductKind(BusinessCategory.auto, subtype: s), 'service', reason: s);
      }
    });

    test('auto савдо аниқроқ турлари → product (negative)', () {
      for (final s in ['Автомобиль эҳтиёт қисмлари', 'Аккумулятор', 'Шина савдоси']) {
        final p = BusinessTypeProfile.of(BusinessCategory.auto, subtype: s);
        expect(p.defaultKind, OfferKind.product, reason: s);
        expect(p.group, BusinessOfferGroup.products, reason: s);
        expect(p.catalogTitleKey, 'bizprod_title_products', reason: s);
        expect(p.courierDelivery, isTrue, reason: s);
      }
    });

    test('чегара: бошқа ёзув/регистр тан олинади; номаълум/бўш аниқроқ тур — тур бошланғичи', () {
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: 'shinomontaj').defaultKind, OfferKind.service);
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: '  АВТОЗАПЧАСТИ ').defaultKind, OfferKind.product);
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: 'Менинг устахонам').subtype, '');
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: 'Менинг устахонам').defaultKind, OfferKind.service);
      expect(BusinessTypeProfile.of(BusinessCategory.auto).defaultKind, OfferKind.service);
      // Бошқа турнинг номи шу турда алмаштириш бермайди.
      expect(BusinessTypeProfile.of(BusinessCategory.retail, subtype: 'Шиномонтаж').defaultKind, OfferKind.product);
      expect(defaultProductKind(BusinessCategory.auto), 'service');
    });

    test('«Бошқа» — аралаш, бошланғичи маҳсулот, танлов очиқ', () {
      final p = BusinessTypeProfile.of(BusinessCategory.other);
      expect(p.group, BusinessOfferGroup.mixed);
      expect(p.defaultKind, OfferKind.product);
      expect(p.kindSelectable, isTrue);
      expect(p.catalogTitleKey, 'bizprod_title');
      expect(p.priceUnits, PriceUnit.values);
      expect({for (final t in p.templates) t.kind}, {OfferKind.product, OfferKind.service});
    });

    test('дўкон — фақат маҳсулот, танлов йўқ; асосий дўкон ҳам', () {
      final p = BusinessTypeProfile.of(BusinessCategory.retail);
      expect(p.group, BusinessOfferGroup.products);
      expect(p.kindSelectable, isFalse);
      final own = BusinessTypeProfile.forBusiness(Business.ownShop(ownerId: '998901234567', name: 'Дўкон'));
      expect(own.category, BusinessCategory.retail);
      expect(own.kindSelectable, isFalse);
    });

    test('овқатланиш — меню (ресторан бўлими), generic каталог эмас', () {
      final p = BusinessTypeProfile.of(BusinessCategory.food, subtype: 'Кафе');
      expect(p.group, BusinessOfferGroup.menu);
      expect(p.catalogTitleKey, 'restaurants_m_tab_menu');
      expect(p.nextStepCtaKey, 'bizmap_open_menu');
      expect(p.kindSelectable, isFalse);
      expect(p.courierDelivery, isFalse);
    });

    test('сартарош — хизмат, шаблонлар «Соч олиш…», 3 тилда', () {
      final p = BusinessTypeProfile.forBusiness(_biz(BusinessCategory.personal, subtype: 'Сартарошхона'));
      expect(p.defaultKind, OfferKind.service);
      expect(p.templateTitles('uz_Cyrl'), contains('Соч олиш'));
      expect(p.templateTitles('uz_Latn'), contains('Soch olish'));
      expect(p.templateTitles('ru'), contains('Стрижка'));
      expect(p.emptyStateKey, 'biz_empty_services');
    });

    test('аниқроқ тур шаблонлари: тозалаш — м², таъмир — таъмир шаблонлари', () {
      final clean = BusinessTypeProfile.of(BusinessCategory.personal, subtype: 'Уй тозалаш');
      expect(clean.defaultPriceUnit, PriceUnit.m2);
      expect(clean.templateTitles('uz_Cyrl'), contains('Уй тозалаш'));
      final repair = BusinessTypeProfile.of(BusinessCategory.personal, subtype: 'Телефон таъмири');
      expect(repair.templateTitles('uz_Cyrl'), isNot(contains('Соч олиш')));
    });
  });

  group('лицензия', () {
    test('лицензияли 5 тур эслатма билан; қолганлари йўқ', () {
      const licensed = {
        BusinessCategory.health,
        BusinessCategory.finance,
        BusinessCategory.professional,
        BusinessCategory.security,
        BusinessCategory.family,
      };
      for (final c in BusinessCategory.values) {
        final p = BusinessTypeProfile.of(c);
        expect(p.needsLicenceNote, licensed.contains(c), reason: c.wire);
        if (licensed.contains(c)) expect(p.licenceNoteKey, 'business_cat_note_${c.wire}');
      }
      // Эслатма аниқроқ турдан қатъи назар (масалан дорихона — маҳсулот, лекин эслатма бор).
      expect(BusinessTypeProfile.of(BusinessCategory.health, subtype: 'Дорихона').needsLicenceNote, isTrue);
    });
  });

  group('курьер', () {
    test('фақат маҳсулот + жисмоний жой; хизмат ва онлайн — йўқ', () {
      final shop = BusinessTypeProfile.of(BusinessCategory.retail);
      expect(shop.courierDeliveryApplies(kind: OfferKind.product, online: false), isTrue);
      expect(shop.courierDeliveryApplies(kind: OfferKind.product, online: true), isFalse);
      expect(shop.courierDeliveryApplies(kind: OfferKind.service, online: false), isFalse);
      final barber = BusinessTypeProfile.of(BusinessCategory.personal);
      expect(barber.courierDelivery, isFalse);
      expect(barber.courierDeliveryApplies(kind: OfferKind.product, online: false), isFalse);
    });

    test('тиббий товар, тирик ҳайвон, ташқи савдо партияси — курьер йўқ', () {
      expect(BusinessTypeProfile.of(BusinessCategory.health, subtype: 'Дорихона').courierDelivery, isFalse);
      expect(BusinessTypeProfile.of(BusinessCategory.animals, subtype: 'Чорва сотиш').courierDelivery, isFalse);
      expect(BusinessTypeProfile.of(BusinessCategory.animals, subtype: 'Зоотоварлар').courierDelivery, isTrue);
      expect(BusinessTypeProfile.of(BusinessCategory.foreignTrade).courierDelivery, isFalse);
    });
  });

  group('модул кўприклари', () {
    test('кўчмас мулк → эълон; баҳолаш — кўприксиз', () {
      expect(BusinessTypeProfile.of(BusinessCategory.realEstate).moduleBridge, BusinessModuleBridge.realtyListing);
      expect(BusinessTypeProfile.of(BusinessCategory.realEstate, subtype: 'Уй ижараси').moduleBridge,
          BusinessModuleBridge.realtyListing);
      expect(BusinessTypeProfile.of(BusinessCategory.realEstate, subtype: 'Кўчмас мулк баҳолаш').moduleBridge, isNull);
    });

    test('юк ташиш аниқроқ турлари → yuk_local; такси — йўқ', () {
      expect(BusinessTypeProfile.of(BusinessCategory.logistics, subtype: 'Юк машинаси').moduleBridge,
          BusinessModuleBridge.cargoLocal);
      expect(BusinessTypeProfile.of(BusinessCategory.logistics, subtype: 'Шаҳар таксиси').moduleBridge, isNull);
      expect(BusinessTypeProfile.of(BusinessCategory.logistics).moduleBridge, isNull);
    });

    test('қувватлаш станцияси → EV', () {
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: 'Электромобиль қувватлаш станцияси').moduleBridge,
          BusinessModuleBridge.evStation);
      expect(BusinessTypeProfile.of(BusinessCategory.energy, subtype: 'Электр қувватлаш станциялари').moduleBridge,
          BusinessModuleBridge.evStation);
      expect(BusinessTypeProfile.of(BusinessCategory.auto, subtype: 'Мой алмаштириш').moduleBridge, isNull);
    });

    test('кўприк экранлари репода бор (2026-11-03 текширилган)', () {
      for (final f in [
        'lib/features/realty/screens/add_realty_listing_screen.dart',
        'lib/features/yuk_local/screens/yuk_local_screen.dart',
        'lib/features/ev_charging/screens/ev_charging_map_screen.dart',
        'lib/features/ev_charging/screens/add_ev_station_screen.dart',
      ]) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }
    });
  });

  group('l10n', () {
    test('ҳар профил (тур + ҳар аниқроқ тур) калити 3 тилда бор ва бўш эмас', () {
      final keys = <String>{..._reservedKeys};
      for (final c in BusinessCategory.values) {
        keys.addAll(_keysOf(BusinessTypeProfile.of(c)));
        for (final (uz, _) in BusinessSubtypes.data[c]!) {
          keys.addAll(_keysOf(BusinessTypeProfile.of(c, subtype: uz)));
        }
      }
      for (final k in keys) {
        for (final e in langs.entries) {
          expect((e.value[k] as String?)?.trim(), isNotEmpty, reason: '${e.key}: $k');
        }
      }
    });

    test('шаблон номлари: uz_Latn да кирилл йўқ, ru да ўзбек ҳарфи йўқ', () {
      final cyr = RegExp('[Ѐ-ӿ]');
      final uz = RegExp('[ўқғҳЎҚҒҲ]');
      for (final c in BusinessCategory.values) {
        final profiles = [
          BusinessTypeProfile.of(c),
          for (final (s, _) in BusinessSubtypes.data[c]!) BusinessTypeProfile.of(c, subtype: s),
        ];
        for (final p in profiles) {
          for (final t in p.templateTitles('uz_Latn')) {
            expect(cyr.hasMatch(t), isFalse, reason: '${c.wire}: $t');
          }
          for (final t in p.templateTitles('ru')) {
            expect(uz.hasMatch(t), isFalse, reason: '${c.wire}: $t');
          }
        }
      }
    });
  });
}
