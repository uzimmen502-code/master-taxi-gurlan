import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  Map<String, String> _localizedStrings = {};

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  Future<bool> load() async {
    String langCode;
    switch (locale.languageCode) {
      case 'uz':
        langCode = locale.scriptCode == 'Latn' ? 'uz_Latn' : 'uz_Cyrl';
        break;
      case 'ru':
        langCode = 'ru';
        break;
      default:
        langCode = 'uz_Cyrl';
    }

    try {
      final jsonString =
      await rootBundle.loadString('assets/lang/$langCode.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      _localizedStrings =
          jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      // Файл топилмаса, default матнлар ишлатилади
      _localizedStrings = _defaultStrings;
    }
    return true;
  }

  String translate(String key) {
    return _localizedStrings[key] ?? _defaultStrings[key] ?? key;
  }

  /// `context.tr('key')` uchun qisqa yo‘l.
  static String tr(BuildContext context, String key) {
    return of(context)?.translate(key) ?? key;
  }

  // ===== DEFAULT МАТНЛАР (файл бўлмаса ишлатилади) =====
  static const Map<String, String> _defaultStrings = {
    // Асосий
    'app_name': 'Master Taxi Gurlan',
    'ok': 'OK',
    'cancel': 'Бекор қилиш',
    'save': 'Сақлаш',
    'close': 'Ёпиш',
    'yes': 'Ҳа',
    'no': 'Йўқ',
    'loading': 'Юкланмоқда...',
    'error': 'Хатолик',
    'success': 'Муваффақият',

    // Навигация
    'taxi': 'Такси',
    'intercity_taxi': 'Ш.Такси',
    'bread': 'Нон буюртма',
    'food': 'Овқат',
    'profile': 'Профил',

    // Маҳаллий такси
    'from': 'Қаердан',
    'to': 'Қаерга',
    'enter_address': 'Манзилни киритинг',
    'optional': 'ихтиёрий',
    'gps_location': 'GPS жойлашув',
    'search_driver': 'Ҳайдовчи қидириш',
    'searching': 'Қидирилмоқда...',
    'driver_found': 'Ҳайдовчи топилди',
    'driver_not_found': 'Ҳайдовчи топилмади',
    'cancel_search': 'Бекор қилиш',
    'taxi_type': 'Такси тури',
    'alone_taxi': 'Алоҳида машина',
    'alone_taxi_desc': 'Бутун машина сизники',
    'route_taxi': 'Маршрут такси',
    'route_taxi_desc': 'Бошқалар билан бирга',
    'saved_places': 'Сақланган манзиллар',
    'add_place': 'Манзил қўшиш',
    'place_name': 'Манзил номи',
    'max_places': 'Максимум 6 та манзил сақлаш мумкин',
    'gps_denied': 'GPS рухсати берилмади',
    'gps_denied_forever': 'GPS рухсати рад этилган. Созламалардан рухсат беринг',
    'gps_detected': 'Жойлашув аниқланди',
    'gps_error': 'GPS аниқланмади. Қайта уриниб кўринг',

    // Такси карточкалари
    'driver': 'Ҳайдовчи',
    'car': 'Автомобил',
    'rating': 'Рейтинг',
    'plate': 'Дав. рақами',
    'distance': 'Масофа',
    'arrival_time': 'Келиш вақти',
    'phone': 'Телефон',
    'status': 'Ҳолат',
    'accepted': 'қабул қилди',
    'book': 'БРОН',
    'call': 'ҚЎНҒИРОҚ',
    'cancel_ride': 'БЕКОР ҚИЛИШ',
    'km': 'км',
    'min': 'дақ',
    'sum': 'сўм',
    'seats': 'Бўш ўрин',
    'parcel': 'Жўнатма',
    'radius': 'Радиус',
    'found': 'Топилган',

    // Шаҳарлараро такси
    'intercity': 'Шаҳарлараро',
    'passengers': 'Йўловчилар',
    'today': 'Бугун',
    'tomorrow': 'Эртага',
    'search_rides': 'РЕЙСЛАРНИ ҚИДИРИШ',
    'departure_time': 'Жўнаш вақти',
    'no_rides': 'Рейслар топилмади',
    'select_district': 'Тошкент туманини танланг',

    // Нон
    'bread_order': 'Нон буюртма',
    'cart': 'Сават',
    'cart_empty': 'Сават бўш',
    'add_to_cart': 'Қўшиш',
    'total': 'Жами',
    'order': 'Буюртма бериш',
    'baking': 'Ёпиб бериш',
    'ready': 'Тайёр',
    'added_to_cart': 'саватга қўшилди',

    // Овқат
    'food_order': 'Овқат буюртма',
    'menu': 'Меню',
    'categories': 'Категориялар',
    'all': 'Барчаси',
    'hot_dishes': 'Иссиқ таомлар',
    'soups': 'Шўрвалар',
    'salads': 'Салатлар',
    'drinks': 'Ичимликлар',
    'delivery_time': 'Етказиш вақти',
    'delivery_address': 'Етказиш манзили',
    'place_order': 'Буюртма бериш',
    'order_placed': 'Буюртма қабул қилинди',
    'min_order': 'Минимал буюртма',
    'free_delivery': 'Бепул етказиш',
    'piece': 'дона',

    // Профил
    'profile_photo': 'Профил расми',
    'take_photo': 'Расмни босинг',
    'gallery': 'Галереядан',
    'camera': 'Камерадан олиш',
    'delete_photo': 'Расмни ўчириш',
    'photo_source': 'Расмни қаердан олиш?',
    'name': 'Исм',
    'phone_number': 'Телефон рақами',
    'settings': 'Созламалар',
    'language': 'Тил',

    // Харита
    'select_location': 'Манзил танлаш',
    'confirm': 'Тасдиқлаш',
    'recent_places': 'Сўнгги манзиллар',
    'selected_address': 'Танланган манзил',
    'tap_to_select': 'Харитага босинг',
  };
}

// ===== DELEGATE =====
class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'ru' || locale.languageCode == 'uz';
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => true;
}