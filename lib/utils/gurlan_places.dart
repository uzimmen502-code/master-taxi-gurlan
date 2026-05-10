// lib/utils/gurlan_places.dart
// Гурлан тумани МФЙлари — Кирил ва Лотин алифбоси қўллаб-қувватланади

class GurlanPlaces {

  // ── Кирил ──
  static const List<String> _cyrl = [
    'Ёрмиш МФЙ', 'Обод МФЙ', 'Ишонч МФЙ', 'Дўстлик МФЙ',
    'Навбаҳор МФЙ', 'Чинобод МФЙ', 'Боғишамол МФЙ', 'Марифат МФЙ',
    'Мевазор МФЙ', 'Дўсимбий МФЙ', 'Фидокор МФЙ', 'Навбир-ёп МФЙ',
    'Нукус МФЙ', 'Нурафшон МФЙ', 'Қатариқ МФЙ', 'Чаккалар МФЙ',
    'Зиёкор МФЙ', 'Сахтиён МФЙ', 'Янги боғ МФЙ', 'Эсабий МФЙ',
    'Қангли МФЙ', 'Ватанпарвар МФЙ', 'Марбугат МФЙ', 'Бирлашган МФЙ',
    'Гулшан МФЙ', 'Бўзқалъа МФЙ', 'Олчин МФЙ', 'Ўйилма МФЙ',
    'Деҳқонобод МФЙ', 'Тахтакўпир МФЙ', 'Мойли МФЙ', 'Шанғи МФЙ',
    'Олға МФЙ', 'Янги аср МФЙ', 'Болдоқли МФЙ', 'Шодлик МФЙ',
    'Эшимжирон МФЙ', 'Жалойир МФЙ', 'Пахтачи МФЙ', 'Нурли йўл МФЙ',
    'Совунчи МФЙ', 'Пахтакор МФЙ', 'Деҳқон МФЙ', 'Беш уй МФЙ',
    'Боғистон МФЙ', 'Оққум МФЙ', 'Нуробод МФЙ', 'Дўстлик боғи МФЙ',
    // Шаҳарлар ва бозорлар
    'Гурлан бозори', 'Марказий бозор', 'Саноат бозори',
    'Гурлан туман ҳокимияти', 'Гурлан марказий шифохонаси',
    'Гурлан автовокзали', 'Урганч', 'Хива', 'Хонқа', 'Питнак',
    'Янгибозор', 'Тошкент', 'Самарқанд', 'Бухоро', 'Нукус',
  ];

  // ── Лотин ──
  static const List<String> _latn = [
    'Yormish MFY', 'Obod MFY', 'Ishonch MFY', 'Do\'stlik MFY',
    'Navbahor MFY', 'Chinobod MFY', 'Bog\'ishamol MFY', 'Marifat MFY',
    'Mevazor MFY', 'Do\'simbiy MFY', 'Fidokor MFY', 'Navbir-yop MFY',
    'Nukus MFY', 'Nurafshon MFY', 'Qatariq MFY', 'Chakkallar MFY',
    'Ziyokor MFY', 'Saxtiyun MFY', 'Yangi bog\' MFY', 'Esabiy MFY',
    'Qangli MFY', 'Vatanparvar MFY', 'Marbugat MFY', 'Birlashgan MFY',
    'Gulshan MFY', 'Bo\'zqal\'a MFY', 'Olchin MFY', 'O\'yilma MFY',
    'Dehqonobod MFY', 'Taxtako\'pir MFY', 'Moyli MFY', 'Shang\'i MFY',
    'Olg\'a MFY', 'Yangi asr MFY', 'Boldoqli MFY', 'Shodlik MFY',
    'Eshimjiron MFY', 'Jaloyir MFY', 'Paxtachi MFY', 'Nurli yo\'l MFY',
    'Sovunchi MFY', 'Paxtakor MFY', 'Dehqon MFY', 'Besh uy MFY',
    'Bog\'iston MFY', 'Oqqum MFY', 'Nurobod MFY', 'Do\'stlik bog\'i MFY',
    // Shaharlar va bozorlar
    'Gurlan bozori', 'Markaziy bozor', 'Sanoat bozori',
    'Gurlan tuman hokimiyati', 'Gurlan markaziy shifoxonasi',
    'Gurlan avtovokzali', 'Urganch', 'Xiva', 'Xonqa', 'Pitnak',
    'Yangibozor', 'Toshkent', 'Samarqand', 'Buxoro', 'Nukus',
  ];

  // ── Кирилдан Лотинга транслитерация ──
  static String _toLatin(String s) {
    const map = {
      'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo',
      'ж':'j','з':'z','и':'i','й':'y','к':'k','л':'l','м':'m',
      'н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u',
      'ф':'f','х':'x','ц':'ts','ч':'ch','ш':'sh','щ':'sh','ъ':'\'',
      'ы':'i','ь':'\'','э':'e','ю':'yu','я':'ya',
      'ҳ':'h','қ':'q','ғ':'g\'','ў':'o\'','ң':'ng',
    };
    return s.toLowerCase().split('').map((c) => map[c] ?? c).join('');
  }

  // ── Лотиндан Кириллга транслитерация ──
  static String _toCyrillic(String s) {
    var result = s.toLowerCase();
    const map = {
      'sh':'ш','ch':'ч','yo':'ё','yu':'ю','ya':'я','ts':'ц',
      'ng':'ң','o\'':'ў','g\'':'ғ','q':'қ','h':'ҳ',
      'a':'а','b':'б','v':'в','g':'г','d':'д','e':'е',
      'j':'ж','z':'з','i':'и','y':'й','k':'к','l':'л','m':'м',
      'n':'н','o':'о','p':'п','r':'р','s':'с','t':'т','u':'у',
      'f':'ф','x':'х',
    };
    // Avval ikki harfli
    for (final entry in map.entries.where((e) => e.key.length > 1)) {
      result = result.replaceAll(entry.key, entry.value);
    }
    // Keyin bir harfli
    for (final entry in map.entries.where((e) => e.key.length == 1)) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  // ── Кирилмикан? ──
  static bool _isCyrillic(String s) =>
      s.runes.any((r) => r >= 0x0400 && r <= 0x04FF);

  // ── Қидириш ──
  static List<String> search(String q) {
    if (q.trim().length < 2) return [];
    final query  = q.toLowerCase().trim();
    final isCyrl = _isCyrillic(query);

    // Мос рўйхат
    final primary   = isCyrl ? _cyrl : _latn;
    final secondary = isCyrl ? _latn : _cyrl;

    // Транслитерация
    final queryAlt  = isCyrl ? _toLatin(query) : _toCyrillic(query);

    final results = <String>[];

    // Аввал асосий рўйхатдан
    for (final item in primary) {
      if (item.toLowerCase().contains(query)) results.add(item);
    }

    // Кейин иккиламчи рўйхатдан (агар жуда кам натижа)
    if (results.length < 3) {
      for (final item in secondary) {
        if (item.toLowerCase().contains(queryAlt) && !results.contains(item)) {
          results.add(item);
        }
      }
    }

    return results.take(8).toList();
  }

  // ── Тўлиқ рўйхат ──
  static List<String> get allCyrl => _cyrl;
  static List<String> get allLatn => _latn;
}