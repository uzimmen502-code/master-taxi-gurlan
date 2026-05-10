// МФЙ рўйхати — Кирилл ва Лотин

const List<Map<String, String>> mfyData = [
  {'kir': 'Ёрмиш', 'lat': 'Yormish'},
  {'kir': 'Обод', 'lat': 'Obod'},
  {'kir': 'Ишонч', 'lat': 'Ishonch'},
  {'kir': 'Дўстлик', 'lat': 'Do\'stlik'},
  {'kir': 'Навбаҳор', 'lat': 'Navbahor'},
  {'kir': 'Чинобод', 'lat': 'Chinobod'},
  {'kir': 'Боғишамол', 'lat': 'Bog\'ishamol'},
  {'kir': 'Марифат', 'lat': 'Marifat'},
  {'kir': 'Мевазор', 'lat': 'Mevazor'},
  {'kir': 'Дўсимбий', 'lat': 'Do\'simbiy'},
  {'kir': 'Фидокор', 'lat': 'Fidokor'},
  {'kir': 'Навбир-ёп', 'lat': 'Navbir-yop'},
  {'kir': 'Нукус', 'lat': 'Nukus'},
  {'kir': 'Нурафшон', 'lat': 'Nurafshon'},
  {'kir': 'Қатариқ', 'lat': 'Qatariq'},
  {'kir': 'Чаккалар', 'lat': 'Chakkallar'},
  {'kir': 'Зиёкор', 'lat': 'Ziyokor'},
  {'kir': 'Сахтиён', 'lat': 'Saxtiyón'},
  {'kir': 'Янги боғ', 'lat': 'Yangi bog\''},
  {'kir': 'Эсабий', 'lat': 'Esabiy'},
  {'kir': 'Қангли', 'lat': 'Qangli'},
  {'kir': 'Ватанпарвар', 'lat': 'Vatanparvar'},
  {'kir': 'Марбугат', 'lat': 'Marbug\'at'},
  {'kir': 'Бирлашган', 'lat': 'Birlashgan'},
  {'kir': 'Гулшан', 'lat': 'Gulshan'},
  {'kir': 'Бўзқалъа', 'lat': 'Bo\'zqal\'a'},
  {'kir': 'Олчин', 'lat': 'Olchin'},
  {'kir': 'Ўйилма', 'lat': 'O\'yilma'},
  {'kir': 'Деҳқонобод', 'lat': 'Dehqonobod'},
  {'kir': 'Тахтакўпир', 'lat': 'Taxtako\'pir'},
  {'kir': 'Мойли', 'lat': 'Moyli'},
  {'kir': 'Шанғи', 'lat': 'Shang\'i'},
  {'kir': 'Олға', 'lat': 'Olg\'a'},
  {'kir': 'Янги аср', 'lat': 'Yangi asr'},
  {'kir': 'Болдоқли', 'lat': 'Boldoqli'},
  {'kir': 'Шодлик', 'lat': 'Shodlik'},
  {'kir': 'Эшимжирон', 'lat': 'Eshimjiron'},
  {'kir': 'Жалойир', 'lat': 'Jaloyir'},
  {'kir': 'Пахтачи', 'lat': 'Paxtachi'},
  {'kir': 'Нурли йўл', 'lat': 'Nurli yo\'l'},
  {'kir': 'Совунчи', 'lat': 'Sovunchi'},
  {'kir': 'Пахтакор', 'lat': 'Paxtakor'},
  {'kir': 'Деҳқон', 'lat': 'Dehqon'},
  {'kir': 'Беш уй', 'lat': 'Besh uy'},
  {'kir': 'Боғистон', 'lat': 'Bog\'iston'},
  {'kir': 'Оққум', 'lat': 'Oqqum'},
  {'kir': 'Нуробод', 'lat': 'Nurobod'},
  {'kir': 'Дўстлик боғи', 'lat': 'Do\'stlik bog\'i'},
];

// Қидирув функцияси — иккала алифбода ишлайди
List<String> searchMfy(String query, bool isLatin) {
  if (query.isEmpty) return [];
  final q = query.toLowerCase();
  return mfyData
      .where((m) =>
  m['kir']!.toLowerCase().contains(q) ||
      m['lat']!.toLowerCase().contains(q))
      .map((m) => isLatin ? '${m['lat']} MFY' : '${m['kir']} МФЙ')
      .take(7)
      .toList();
}

// Лотин ёки Кириллни аниқлаш
bool isLatinScript(String text) {
  if (text.isEmpty) return false;
  final latinChars = RegExp(r'[a-zA-Z]');
  final cyrillicChars = RegExp(r'[а-яёА-ЯЁ]');
  final latinCount = latinChars.allMatches(text).length;
  final cyrillicCount = cyrillicChars.allMatches(text).length;
  return latinCount > cyrillicCount;
}