import 'package:flutter/material.dart';

import 'locale_utils.dart';

/// Шаҳарлараро такси учун Ўзбекистон бўйича қишлоқ ва туманлар рўйхати.
/// Каноник саҳифа — кирилл (`allLocations`); UI тили лотин бўлса лотин кўрсатилади.
class IntercityPlaces {
  IntercityPlaces._();

  static const List<String> tashkentDistricts = [
    'Чилонзор',
    'Юнусобод',
    'Миробод',
    'Шайхонтоҳур',
    'Олмазор',
    'Сергели',
    'Учтепа',
    'Яшнобод',
    'Бектемир',
    'Яккасарой',
  ];

  static final List<String> _tashkentDistrictsLatn =
      tashkentDistricts.map(_toLatinDisplay).toList(growable: false);

  /// Firestore / маршрут мослаштириш учун каноник (кирилл) рўйхат.
  static const List<String> allLocations = [
    'Тошкент', 'Самарқанд', 'Бухоро', 'Наманган', 'Андижон',
    'Фарғона', 'Қарши', 'Термиз', 'Жиззах', 'Гулистон',
    'Навоий', 'Урганч', 'Нукус',
    'Тошкент • Олмалиқ', 'Тошкент • Ангрен', 'Тошкент • Чирчиқ',
    'Тошкент • Бекобод', 'Тошкент • Янгийўл', 'Тошкент • Келес',
    'Тошкент • Зангиота', 'Тошкент • Бўстонлиқ', 'Тошкент • Паркент',
    'Тошкент • Қибрай', 'Тошкент • Оҳангарон', 'Тошкент • Пскент',
    'Тошкент • Тўйтепа',
    'Тошкент ш. • Чилонзор', 'Тошкент ш. • Юнусобод', 'Тошкент ш. • Миробод',
    'Тошкент ш. • Шайхонтоҳур', 'Тошкент ш. • Олмазор', 'Тошкент ш. • Сергели',
    'Тошкент ш. • Учтепа', 'Тошкент ш. • Яшнобод', 'Тошкент ш. • Бектемир',
    'Тошкент ш. • Яккасарой',
    'Самарқанд • Каттақўрғон', 'Самарқанд • Иштихон', 'Самарқанд • Жомбой',
    'Самарқанд • Нарпай', 'Самарқанд • Пастдарғом', 'Самарқанд • Пайариқ',
    'Самарқанд • Қўшработ', 'Самарқанд • Тайлоқ', 'Самарқанд • Булунғур',
    'Самарқанд • Ургут', 'Самарқанд • Оқдарё',
    'Бухоро • Когон', 'Бухоро • Қоракўл', 'Бухоро • Ғиждувон',
    'Бухоро • Шофиркон', 'Бухоро • Вобкент', 'Бухоро • Ромитан',
    'Бухоро • Жондор', 'Бухоро • Олот', 'Бухоро • Пешку',
    'Наманган • Чуст', 'Наманган • Поп', 'Наманган • Тўрақўрғон',
    'Наманган • Уйчи', 'Наманган • Косонсой', 'Наманган • Мингбулоқ',
    'Наманган • Учқўрғон', 'Наманган • Янгиқўрғон', 'Наманган • Норин',
    'Андижон • Асака', 'Андижон • Хонобод', 'Андижон • Пахтаобод',
    'Андижон • Балиқчи', 'Андижон • Бўз', 'Андижон • Жалолқудуқ',
    'Андижон • Избосқан', 'Андижон • Мархамат', 'Андижон • Шахрихон',
    'Андижон • Улуғнор', 'Андижон • Қўрғонтепа',
    'Фарғона • Марғилон', 'Фарғона • Қўқон', 'Фарғона • Қувасой',
    'Фарғона • Риштон', 'Фарғона • Қува', 'Фарғона • Боғдод',
    'Фарғона • Данғара', 'Фарғона • Олтиариқ', 'Фарғона • Тошлоқ',
    'Фарғона • Учқўприк', 'Фарғона • Яйпан',
    'Қашқадарё • Шаҳрисабз', 'Қашқадарё • Китоб', 'Қашқадарё • Муборак',
    'Қашқадарё • Чироқчи', 'Қашқадарё • Яккабоғ', 'Қашқадарё • Косон',
    'Қашқадарё • Камаши', 'Қашқадарё • Деҳқонобод', 'Қашқадарё • Нишон',
    'Сурхондарё • Денов', 'Сурхондарё • Шўрчи', 'Сурхондарё • Бойсун',
    'Сурхондарё • Жарқўрғон', 'Сурхондарё • Сариосиё', 'Сурхондарё • Қумқўрғон',
    'Сурхондарё • Олтинсой', 'Сурхондарё • Музработ',
    'Жиззах • Зафаробод', 'Жиззах • Зомин', 'Жиззах • Ғаллаорол',
    'Жиззах • Дўстлик', 'Жиззах • Мирзачўл', 'Жиззах • Пахтакор',
    'Жиззах • Янгиобод', 'Жиззах • Арнасой', 'Жиззах • Бахмал',
    'Сирдарё • Янгийер', 'Сирдарё • Боёвут', 'Сирдарё • Сардоба',
    'Сирдарё • Хавос', 'Сирдарё • Мирзаобод', 'Сирдарё • Сайхунобод',
    'Навоий • Зарафшон', 'Навоий • Учқудуқ', 'Навоий • Нурота',
    'Навоий • Қизилтепа', 'Навоий • Хатирчи', 'Навоий • Томди',
    'Навоий • Конимех', 'Навоий • Навбаҳор',
    'Хоразм • Гурлан', 'Хоразм • Хива', 'Хоразм • Қўшкўпир',
    'Хоразм • Шовот', 'Хоразм • Янгиариқ', 'Хоразм • Янгибозор',
    'Хоразм • Боғот', 'Хоразм • Ҳазорасп', 'Хоразм • Хонқа',
    'Хоразм • Тупроққалъа', 'Хоразм • Питнак',
    'Қорақалпоғистон • Мўйноқ', 'Қорақалпоғистон • Чимбой',
    'Қорақалпоғистон • Хўжайли', 'Қорақалпоғистон • Қўнғирот',
    'Қорақалпоғистон • Тахтакўпир', 'Қорақалпоғистон • Беруний',
    'Қорақалпоғистон • Кегейли', 'Қорақалпоғистон • Қораўзак',
  ];

  static final List<String> _allLatn =
      allLocations.map(_toLatinDisplay).toList(growable: false);

  static List<String> tashkentDistrictsFor(Locale locale) =>
      LocaleUtils.isLatin(locale) ? _tashkentDistrictsLatn : tashkentDistricts;

  /// Қидирув — танланган til/алифбода + транслитерация (GurlanPlaces qoidasi).
  static List<String> search(String query, {Locale? locale}) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];

    final preferLatin = locale != null
        ? LocaleUtils.isLatin(locale)
        : !_isCyrillic(q);
    final primary = preferLatin ? _allLatn : allLocations;
    final secondary = preferLatin ? allLocations : _allLatn;
    final queryAlt = _isCyrillic(q) ? _toLatinRaw(q) : _toCyrillic(q);

    final results = <String>[];
    for (final item in primary) {
      if (item.toLowerCase().contains(q)) results.add(item);
    }
    if (results.length < 3) {
      for (final item in secondary) {
        if (item.toLowerCase().contains(queryAlt) && !results.contains(item)) {
          results.add(item);
        }
      }
    }
    return results.take(12).toList(growable: false);
  }

  /// Танловдан кейин каноник кирилл қиймат (Firestore мослаштириш).
  static String normalizeLocation(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();
    for (var i = 0; i < allLocations.length; i++) {
      final cy = allLocations[i].toLowerCase();
      final la = _allLatn[i].toLowerCase();
      if (lower == cy || lower == la) return allLocations[i];
    }
    for (var i = 0; i < allLocations.length; i++) {
      final cy = allLocations[i].toLowerCase();
      final la = _allLatn[i].toLowerCase();
      if (cy.contains(lower) ||
          la.contains(lower) ||
          lower.contains(cy) ||
          lower.contains(la)) {
        return allLocations[i];
      }
    }
    return trimmed;
  }

  /// Controller’да сақланган каноник манзилни UI tiliga кўрсатиш.
  static String displayForLocale(String canonical, Locale locale) {
    if (canonical.isEmpty) return '';
    final idx = allLocations.indexOf(canonical);
    if (idx < 0) return canonical;
    return LocaleUtils.isLatin(locale) ? _allLatn[idx] : allLocations[idx];
  }

  /// Фақат «Тошкент» (tumansiz) — keyingi qadamda tuman tanlash.
  static bool isBareTashkentCity(String canonical) {
    return normalizeLocation(canonical) == 'Тошкент';
  }

  /// Tuman tanlovidan каноник: `Тошкент ш. • Чилонзор`.
  static String districtCanonicalFromPicker(String districtLabel, Locale locale) {
    final districts = tashkentDistrictsFor(locale);
    final idx = districts.indexOf(districtLabel);
    final cyr = idx >= 0 ? tashkentDistricts[idx] : districtLabel;
    return 'Тошкент ш. • $cyr';
  }

  /// Tarix + qidiruv — UI tilida, kanonik дубликатсиз.
  static List<String> mergedSuggestions({
    required String query,
    required Locale locale,
    required List<String> recentCanonical,
    int limit = 12,
  }) {
    final q = query.trim().toLowerCase();
    final seen = <String>{};
    final out = <String>[];

    void addRaw(String raw) {
      final canonical = normalizeLocation(raw);
      if (canonical.isEmpty || !seen.add(canonical)) return;
      out.add(displayForLocale(canonical, locale));
    }

    for (final c in recentCanonical) {
      final disp = displayForLocale(c, locale);
      if (q.isEmpty || disp.toLowerCase().contains(q)) {
        addRaw(c);
      }
    }

    if (q.isNotEmpty) {
      for (final s in search(query, locale: locale)) {
        addRaw(s);
        if (out.length >= limit) break;
      }
    }

    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  static bool isTashkentCity(String canonical) {
    final city = extractCity(canonical).toLowerCase();
    return city == 'тошкент' || city == 'toshkent';
  }

  /// `"Самарқанд • Иштихон"` → `"Самарқанд"`; `"Тошкент ш."` → `"Тошкент"`.
  static String extractCity(String loc) {
    if (loc.contains('•')) return loc.split('•').first.trim();
    if (loc.endsWith(' ш.')) return loc.substring(0, loc.length - 3);
    return loc;
  }

  /// `"Хоразм • Гурлан"` → `"Гурлан"`; oxirgi Toshkent tumani → `"Тошкент"`.
  static String shortStopName(String canonical, {bool lastInRoute = false}) {
    final t = canonical.trim();
    if (t.isEmpty) return '';
    if (t.contains('•')) {
      final left = t.split('•').first.trim();
      final right = t.split('•').last.trim();
      if (lastInRoute && _isTashkentArea(left)) return 'Тошкент';
      return right;
    }
    if (t.endsWith(' ш.')) return extractCity(t);
    return t;
  }

  static bool _isTashkentArea(String s) {
    final compact = s.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
    return compact.startsWith('toshkent') || compact.startsWith('тошкент');
  }

  static List<String> parseRouteStops(String routeLabel) {
    return routeLabel
        .split('→')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static String _displayShortStop(
    String canonical, {
    bool lastInRoute = false,
    Locale? locale,
  }) {
    final short = shortStopName(canonical, lastInRoute: lastInRoute);
    if (locale == null || !LocaleUtils.isLatin(locale)) return short;
    if (short == 'Тошкент') return 'Toshkent';
    for (var i = 0; i < allLocations.length; i++) {
      if (allLocations[i] == canonical) {
        final lat = _allLatn[i];
        if (lastInRoute && _isTashkentArea(allLocations[i])) return 'Toshkent';
        if (lat.contains('•')) return lat.split('•').last.trim();
        return lat;
      }
    }
    return _toLatinDisplay(short);
  }

  static String shortRouteLabelFromStops(
    List<String> stops, {
    Locale? locale,
  }) {
    if (stops.isEmpty) return '';
    final parts = <String>[];
    for (var i = 0; i < stops.length; i++) {
      parts.add(
        _displayShortStop(
          stops[i],
          lastInRoute: i == stops.length - 1,
          locale: locale,
        ),
      );
    }
    return parts.join(' → ');
  }

  static String shortRouteLabel(String fullRoute, {Locale? locale}) {
    final trimmed = fullRoute.trim();
    if (trimmed.isEmpty) return '';
    return shortRouteLabelFromStops(parseRouteStops(trimmed), locale: locale);
  }

  static String rideRouteDisplay({
    required String routeLabel,
    required List<String> stops,
    String driverFrom = '',
    String driverTo = '',
    Locale? locale,
  }) {
    final raw = routeLabel.trim();
    if (raw.isNotEmpty) return shortRouteLabel(raw, locale: locale);
    if (stops.isNotEmpty) {
      return shortRouteLabelFromStops(stops, locale: locale);
    }
    if (driverFrom.isNotEmpty && driverTo.isNotEmpty) {
      return shortRouteLabelFromStops([driverFrom, driverTo], locale: locale);
    }
    if (driverFrom.isNotEmpty) {
      return _displayShortStop(driverFrom, lastInRoute: true, locale: locale);
    }
    return '';
  }

  static String tripRouteDisplay(
    Map<String, dynamic>? trip, {
    Locale? locale,
  }) {
    if (trip == null) return '';
    final rawStops = trip['stops'];
    final stops = rawStops is List
        ? rawStops.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return rideRouteDisplay(
      routeLabel: (trip['routeLabel'] ?? '') as String,
      stops: stops,
      driverFrom: (trip['from'] ?? '') as String,
      driverTo: (trip['to'] ?? '') as String,
      locale: locale,
    );
  }

  static String rawRouteFromTrip(Map<String, dynamic>? trip) {
    if (trip == null) return '';
    final label = (trip['routeLabel'] as String?)?.trim() ?? '';
    if (label.isNotEmpty) return label;
    final rawStops = trip['stops'];
    if (rawStops is List && rawStops.isNotEmpty) {
      return rawStops.map((e) => e.toString()).join(' → ');
    }
    final from = (trip['from'] ?? '') as String;
    final to = (trip['to'] ?? '') as String;
    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    return from.isNotEmpty ? from : to;
  }

  static bool _isCyrillic(String s) =>
      s.runes.any((r) => r >= 0x0400 && r <= 0x04FF);

  static String _toLatinDisplay(String s) {
    final buf = StringBuffer();
    for (final c in s.split('')) {
      if (c == c.toUpperCase() && c != c.toLowerCase()) {
        final mapped = _toLatinRaw(c.toLowerCase());
        if (mapped.isEmpty) {
          buf.write(c);
        } else {
          buf.write(mapped[0].toUpperCase());
          if (mapped.length > 1) buf.write(mapped.substring(1));
        }
      } else {
        buf.write(_toLatinRaw(c));
      }
    }
    return buf.toString();
  }

  static String _toLatinRaw(String s) {
    const map = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
      'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
      'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
      'ф': 'f', 'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '\'',
      'ы': 'i', 'ь': '\'', 'э': 'e', 'ю': 'yu', 'я': 'ya',
      'ҳ': 'h', 'қ': 'q', 'ғ': 'g\'', 'ў': 'o\'', 'ң': 'ng',
    };
    return s.toLowerCase().split('').map((c) => map[c] ?? c).join('');
  }

  static String _toCyrillic(String s) {
    var result = s.toLowerCase();
    const map = {
      'sh': 'ш', 'ch': 'ч', 'yo': 'ё', 'yu': 'ю', 'ya': 'я', 'ts': 'ц',
      'ng': 'ң', 'o\'': 'ў', 'g\'': 'ғ', 'q': 'қ', 'h': 'ҳ',
      'a': 'а', 'b': 'б', 'v': 'в', 'g': 'г', 'd': 'д', 'e': 'е',
      'j': 'ж', 'z': 'з', 'i': 'и', 'y': 'й', 'k': 'к', 'l': 'л', 'm': 'м',
      'n': 'н', 'o': 'о', 'p': 'п', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у',
      'f': 'ф', 'x': 'х',
    };
    for (final entry in map.entries.where((e) => e.key.length > 1)) {
      result = result.replaceAll(entry.key, entry.value);
    }
    for (final entry in map.entries.where((e) => e.key.length == 1)) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
