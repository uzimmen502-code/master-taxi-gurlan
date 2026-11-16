// «Менинг бизнесим» фаолият тури → «Бозорлар» (6 бозор, taxonomy/markets v3 бўлимлари) мослиги (2026-11-16).
//
// Фақат ТАКЛИФ: объектга маҳсулот қўшилганда формадаги бозор/бўлим олдиндан танланади, сотувчи
// алмаштира олади (Аралаш — «бозорсиз»). Сервер бу мосликни ишлатмайди ва текширмайди (бозор майдонлари
// эълон ҳужжатида ихтиёрий; rules `tvShopItemShapeOk`). Мослик — PROPOSED (эга тасдиқлагунча, 47-банд).
//
// Қоида: аввал аниқроқ тур ([BusinessSubtypes] даги тайёр ном, исталган тил/ёзувда) — [_bySubtype];
// тайёр тур бор, лекин бу ерда йўқ (масалан «Ветеринария», «Автосервис» — хизмат) → бозор йўқ.
// Аниқроқ тур бўш ёки эганинг ўз матни → тур бўйича ([_byCategory]).

import 'business_category.dart';
import 'business_type_profile.dart';

/// Бозор id (`livestock` · `auto` · `meat` · `farm` · `electronics` · `appliances`) ва (бўлса) бўлим id.
typedef BusinessMarketMatch = ({String marketId, String? categoryId});

/// Тайёр аниқроқ тур (uz_Cyrl номи) → бозор/бўлим. Бўлим `null` — сотувчи ўзи танлайди.
const Map<BusinessCategory, Map<String, BusinessMarketMatch>> _bySubtype = {
  BusinessCategory.retail: {
    'Гўшт дўкони (қассоб)': (marketId: 'meat', categoryId: null),
    'Товуқ гўшти дўкони': (marketId: 'meat', categoryId: 'poultry'),
    'Балиқ дўкони': (marketId: 'meat', categoryId: 'fish'),
    'Мева-сабзавот дўкони': (marketId: 'farm', categoryId: null),
    'Қишлоқ хўжалиги маҳсулотлари': (marketId: 'farm', categoryId: null),
    'Маиший техника': (marketId: 'appliances', categoryId: null),
    'Кондиционер ва иситгичлар': (marketId: 'appliances', categoryId: 'air_conditioners'),
    'Электроника': (marketId: 'electronics', categoryId: null),
    'Телефон': (marketId: 'electronics', categoryId: 'phones'),
    // Ном «ноутбук»ни ўз ичига олади → laptops (эга 2026-11-16: ноутбук бўлса laptops, акс ҳолда computers).
    'Компьютер ва ноутбуклар': (marketId: 'electronics', categoryId: 'laptops'),
    'Телефон аксессуарлари': (marketId: 'electronics', categoryId: 'accessories'),
    'Автомобиль эҳтиёт қисмлари': (marketId: 'auto', categoryId: 'parts'),
  },
  BusinessCategory.manufacturing: {
    'Гўштни қайта ишлаш': (marketId: 'meat', categoryId: null),
  },
  BusinessCategory.agriculture: {
    'Ғаллачилик': (marketId: 'farm', categoryId: 'grain'),
    'Шоличилик': (marketId: 'farm', categoryId: 'grain'),
    'Сабзавотчилик': (marketId: 'farm', categoryId: 'vegetables'),
    'Иссиқхона': (marketId: 'farm', categoryId: 'vegetables'),
    'Полизчилик': (marketId: 'farm', categoryId: 'melons'),
    'Боғдорчилик': (marketId: 'farm', categoryId: 'fruits'),
    'Узумчилик': (marketId: 'farm', categoryId: 'fruits'),
    'Чорвачилик': (marketId: 'livestock', categoryId: null),
    'Қорамол': (marketId: 'livestock', categoryId: null),
    'Қўй-эчки': (marketId: 'livestock', categoryId: null),
    'Паррандачилик': (marketId: 'livestock', categoryId: null),
    'Балиқчилик': (marketId: 'meat', categoryId: 'fish'),
    'Балиқ етиштириш': (marketId: 'meat', categoryId: 'fish'),
  },
  BusinessCategory.auto: {
    'Автосалон': (marketId: 'auto', categoryId: 'cars'),
    'Мотоцикл савдоси': (marketId: 'auto', categoryId: 'moto'),
    'Махсус техника савдоси': (marketId: 'auto', categoryId: 'tech'),
    'Автомобиль эҳтиёт қисмлари': (marketId: 'auto', categoryId: 'parts'),
    'Аккумулятор': (marketId: 'auto', categoryId: 'parts'),
    'Шина савдоси': (marketId: 'auto', categoryId: 'parts'),
    'Автоойна': (marketId: 'auto', categoryId: 'parts'),
  },
  BusinessCategory.animals: {
    'Чорва сотиш': (marketId: 'livestock', categoryId: null),
    'Парранда сотиш': (marketId: 'livestock', categoryId: null),
    'Зотли ҳайвонлар кўпайтириш': (marketId: 'livestock', categoryId: null),
  },
  BusinessCategory.agency: {
    'Автомобиль сотиш агенти': (marketId: 'auto', categoryId: 'cars'),
  },
};

/// Аниқроқ тур бўш/эганинг ўз матни бўлганда — тур бўйича.
const Map<BusinessCategory, String> _byCategory = {
  BusinessCategory.animals: 'livestock',
  BusinessCategory.agriculture: 'farm',
  BusinessCategory.auto: 'auto',
};

/// [category] ва [subtype] (сақланган матн) учун бозор; мос бозор йўқ — `null` (Аралаш).
BusinessMarketMatch? marketForBusiness(BusinessCategory category, String? subtype) {
  final canon = BusinessTypeProfile.canonicalSubtype(category, subtype ?? '');
  if (canon.isNotEmpty) return _bySubtype[category]?[canon];
  final m = _byCategory[category];
  return m == null ? null : (marketId: m, categoryId: null);
}
