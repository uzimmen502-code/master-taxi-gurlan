// `taxonomy/markets` v1 шакли (functions/tools/data/market_taxonomy_v1.json, prod) — тестлар учун қисқартирилган
// нусха: барча бўлимлар, тур ва категория филтри бор майдонлар.
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';

Map<String, String> _n(String c, [String? l, String? r]) => {'uz_Cyrl': c, 'uz_Latn': l ?? c, 'ru': r ?? c};

final Map<String, dynamic> kTaxonomyDocV1 = {
  'version': 1,
  'markets': {
    'livestock': {
      'moduleId': 'livestock_market',
      'order': 10,
      'names': _n('Мол бозори', 'Mol bozori', 'Рынок скота'),
      'categories': [
        {'id': 'all', 'names': _n('Барчаси'), 'orderable': false},
      ],
      'fields': [
        {'key': 'breed', 'type': 'text', 'maxLen': 60, 'names': _n('Зоти', 'Zoti', 'Порода')},
        {'key': 'age_months', 'type': 'int', 'min': 0, 'max': 600, 'names': _n('Ёши (ой)', 'Yoshi (oy)', 'Возраст (мес.)')},
        {
          'key': 'sex',
          'type': 'select',
          'names': _n('Жинси', 'Jinsi', 'Пол'),
          'options': [
            {'id': 'male', 'names': _n('Эркак', 'Erkak', 'Самец')},
            {'id': 'female', 'names': _n('Урғочи', "Urg'ochi", 'Самка')},
          ],
        },
        {'key': 'count', 'type': 'int', 'min': 1, 'max': 100000, 'names': _n('Сони')},
        {'key': 'weight_kg', 'type': 'int', 'min': 1, 'max': 5000, 'names': _n('Тахминий вазни (кг)')},
        {'key': 'pregnant', 'type': 'bool', 'names': _n('Бўғоз', "Bo'g'oz", 'Стельная')},
      ],
      'priceUnits': ['', 'piece'],
    },
    'auto': {
      'moduleId': 'auto_market',
      'order': 20,
      'names': _n('Мошина бозори', 'Mashina bozori', 'Авторынок'),
      'categories': [
        {'id': 'cars', 'names': _n('Мошиналар')},
        {'id': 'moto', 'names': _n('Мото')},
        {'id': 'tech', 'names': _n('Техника')},
        {'id': 'parts', 'names': _n('Эҳтиёт қисмлар'), 'orderable': true},
      ],
      'fields': [
        {'key': 'brand', 'type': 'text', 'maxLen': 40, 'names': _n('Марка'), 'categories': ['cars', 'moto', 'tech']},
        {'key': 'year', 'type': 'int', 'min': 1950, 'max': 2100, 'names': _n('Йили'), 'categories': ['cars', 'moto', 'tech']},
        {'key': 'fits_car', 'type': 'text', 'maxLen': 80, 'names': _n('Қайси машинага'), 'categories': ['parts']},
        {
          'key': 'condition',
          'type': 'select',
          'names': _n('Ҳолати'),
          'options': [
            {'id': 'new', 'names': _n('Янги')},
            {'id': 'used', 'names': _n('Ишлатилган')},
          ],
          'categories': ['parts'],
        },
      ],
      'priceUnits': [''],
    },
    'meat': {
      'moduleId': 'meat_market',
      'order': 30,
      'names': _n('Гўшт бозори', "Go'sht bozori", 'Мясной рынок'),
      'categories': [
        {'id': 'beef', 'names': _n('Мол', 'Mol', 'Говядина')},
        {'id': 'mutton', 'names': _n('Қўй')},
        {'id': 'poultry', 'names': _n('Парранда')},
        {'id': 'fish', 'names': _n('Балиқ')},
        {'id': 'other', 'names': _n('Бошқа')},
      ],
      'fields': [
        {'key': 'slaughter_date', 'type': 'date', 'names': _n('Сўйилган санаси')},
      ],
      'priceUnits': ['kg'],
    },
    'farm': {
      'moduleId': 'farm_market',
      'order': 40,
      'names': _n('Деҳқон бозори', 'Dehqon bozori', 'Фермерский рынок'),
      'categories': [
        {'id': 'vegetables', 'names': _n('Сабзавот')},
        {'id': 'fruits', 'names': _n('Мева')},
        {'id': 'melons', 'names': _n('Полиз')},
        {'id': 'grain', 'names': _n('Дон')},
        {'id': 'other', 'names': _n('Бошқа')},
      ],
      'fields': [
        {'key': 'harvest_date', 'type': 'date', 'names': _n('Ҳосил вақти')},
      ],
      'priceUnits': ['kg', 'ton', 'piece'],
    },
  },
};

MarketTaxonomy get kTaxonomyV1 => MarketTaxonomy.fromMap(kTaxonomyDocV1);

/// v3 (эга 2026-11-16, functions/tools/data/market_taxonomy_v3.json): v1 + Электроника (50, 9 бўлим) ва
/// Маиший техника (60, 8 бўлим). v2 даги gadgets/large/small/climate бўлимлари v3 да йўқ.
final Map<String, dynamic> kTaxonomyDocV3 = {
  'version': 3,
  'markets': {
    ...(kTaxonomyDocV1['markets'] as Map<String, dynamic>),
    'electronics': {
      'moduleId': 'electronics_market',
      'order': 50,
      'names': _n('Электроника бозори', 'Elektronika bozori', 'Рынок электроники'),
      'categories': [
        {'id': 'phones', 'names': _n('Смартфонлар', 'Smartfonlar', 'Смартфоны')},
        {'id': 'laptops', 'names': _n('Ноутбуклар', 'Noutbuklar', 'Ноутбуки')},
        {'id': 'computers', 'names': _n('Компьютерлар', 'Kompyuterlar', 'Компьютеры')},
        {'id': 'tv', 'names': _n('Телевизорлар', 'Televizorlar', 'Телевизоры')},
        {'id': 'tablets', 'names': _n('Планшетлар', 'Planshetlar', 'Планшеты')},
        {'id': 'smartwatches', 'names': _n('Смарт соатлар', 'Smart soatlar', 'Смарт-часы')},
        {'id': 'audio_video', 'names': _n('Аудио ва видео ускуналар', 'Audio va video uskunalar', 'Аудио- и видеотехника')},
        {'id': 'accessories', 'names': _n('Аксессуарлар', 'Aksessuarlar', 'Аксессуары')},
        {'id': 'other', 'names': _n('Бошқа', 'Boshqa', 'Другое')},
      ],
      'priceUnits': ['', 'piece'],
    },
    'appliances': {
      'moduleId': 'appliances_market',
      'order': 60,
      'names': _n('Маиший техника бозори', 'Maishiy texnika bozori', 'Рынок бытовой техники'),
      'categories': [
        {'id': 'fridges', 'names': _n('Музлаткичлар', 'Muzlatkichlar', 'Холодильники')},
        {'id': 'washers', 'names': _n('Кир ювиш машиналари', 'Kir yuvish mashinalari', 'Стиральные машины')},
        {'id': 'stoves', 'names': _n('Газ ва электр плиталар', 'Gaz va elektr plitalar', 'Газовые и электроплиты')},
        {'id': 'air_conditioners', 'names': _n('Кондиционерлар', 'Konditsionerlar', 'Кондиционеры')},
        {'id': 'vacuums', 'names': _n('Чангюткичлар', 'Changyutkichlar', 'Пылесосы')},
        {'id': 'kitchen', 'names': _n('Ошхона техникалари', 'Oshxona texnikalari', 'Кухонная техника')},
        {'id': 'heaters', 'names': _n('Иситгич ва бойлерлар', 'Isitgich va boylerlar', 'Обогреватели и бойлеры')},
        {'id': 'other', 'names': _n('Бошқа', 'Boshqa', 'Другое')},
      ],
      'priceUnits': ['', 'piece'],
    },
  },
};

MarketTaxonomy get kTaxonomyV3 => MarketTaxonomy.fromMap(kTaxonomyDocV3);

/// v5 (эга 2026-11-19, functions/tools/data/market_taxonomy_v5.json): v3 + Мол бозори 5 бўлим (cattle, sheep_goat,
/// horse, poultry, other; `all` йўқ — эски эълонлар `all` да қолади), Мошина бўлим номлари («Авто», «Махсус
/// техникалар») + model/fuel, Электроника/Маиший техникага каробка ўлчамлари (box_w_cm/box_l_cm/box_h_cm 1..1000).
Map<String, dynamic> _boxField(String key, String c, String l, String r) =>
    {'key': key, 'type': 'int', 'min': 1, 'max': 1000, 'names': _n(c, l, r)};

final List<Map<String, dynamic>> _techFieldsV5 = [
  {'key': 'brand', 'type': 'text', 'maxLen': 40, 'names': _n('Марка', 'Marka', 'Марка')},
  {'key': 'model', 'type': 'text', 'maxLen': 60, 'names': _n('Модель', 'Model', 'Модель')},
  {
    'key': 'condition',
    'type': 'select',
    'names': _n('Ҳолати', 'Holati', 'Состояние'),
    'options': [
      {'id': 'new', 'names': _n('Янги', 'Yangi', 'Новый')},
      {'id': 'used', 'names': _n('Ишлатилган', 'Ishlatilgan', 'Б/у')},
    ],
  },
  _boxField('box_w_cm', 'Эни', 'Eni', 'Ширина'),
  _boxField('box_l_cm', 'Узунлиги', 'Uzunligi', 'Длина'),
  _boxField('box_h_cm', 'Баландлиги', 'Balandligi', 'Высота'),
];

final Map<String, dynamic> kTaxonomyDocV5 = () {
  final markets = <String, dynamic>{...(kTaxonomyDocV3['markets'] as Map<String, dynamic>)};
  final livestock = Map<String, dynamic>.of(markets['livestock'] as Map<String, dynamic>);
  livestock['categories'] = [
    {'id': 'cattle', 'names': _n('Қорамол', 'Qoramol', 'КРС'), 'showInNearbyAds': true},
    {'id': 'sheep_goat', 'names': _n('Қўй-эчки', "Qo'y-echki", 'Овцы и козы'), 'showInNearbyAds': true},
    {'id': 'horse', 'names': _n('От', 'Ot', 'Лошади'), 'showInNearbyAds': true},
    {'id': 'poultry', 'names': _n('Парранда', 'Parranda', 'Птица'), 'showInNearbyAds': true},
    {'id': 'other', 'names': _n('Бошқа', 'Boshqa', 'Другое'), 'showInNearbyAds': true},
  ];
  final auto = Map<String, dynamic>.of(markets['auto'] as Map<String, dynamic>);
  auto['categories'] = [
    {'id': 'cars', 'names': _n('Авто', 'Avto', 'Авто')},
    {'id': 'moto', 'names': _n('Мото', 'Moto', 'Мото')},
    {'id': 'tech', 'names': _n('Махсус техникалар', 'Maxsus texnikalar', 'Спецтехника')},
    {'id': 'parts', 'names': _n('Эҳтиёт қисмлар', 'Ehtiyot qismlar', 'Запчасти'), 'orderable': true},
  ];
  const vehicle = ['cars', 'moto', 'tech'];
  auto['fields'] = [
    {'key': 'brand', 'type': 'text', 'maxLen': 40, 'names': _n('Марка', 'Marka', 'Марка'), 'categories': vehicle},
    {'key': 'model', 'type': 'text', 'maxLen': 40, 'names': _n('Модель', 'Model', 'Модель'), 'categories': vehicle},
    {'key': 'year', 'type': 'int', 'min': 1950, 'max': 2100, 'names': _n('Йили', 'Yili', 'Год'), 'categories': vehicle},
    {
      'key': 'fuel',
      'type': 'select',
      'names': _n('Ёқилғи', "Yoqilg'i", 'Топливо'),
      'categories': vehicle,
      'options': [
        for (final id in ['petrol', 'methane', 'propane', 'diesel', 'electric', 'hybrid']) {'id': id, 'names': _n(id)},
      ],
    },
    {'key': 'fits_car', 'type': 'text', 'maxLen': 80, 'names': _n('Қайси машинага'), 'categories': ['parts']},
  ];
  final electronics = Map<String, dynamic>.of(markets['electronics'] as Map<String, dynamic>)..['fields'] = _techFieldsV5;
  final appliances = Map<String, dynamic>.of(markets['appliances'] as Map<String, dynamic>)..['fields'] = _techFieldsV5;
  return <String, dynamic>{
    'version': 5,
    'markets': {
      ...markets,
      'livestock': livestock,
      'auto': auto,
      'electronics': electronics,
      'appliances': appliances,
    },
  };
}();

MarketTaxonomy get kTaxonomyV5 => MarketTaxonomy.fromMap(kTaxonomyDocV5);
