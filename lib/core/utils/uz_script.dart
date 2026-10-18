/// Ўзбек ёзуви: кирилл ↔ лотин, КЎРСАТИШ учун (ҳарф катталиги сақланади).
///
/// `AdSearchText.toLatin/toCyrillic` қидирув токенлари учун: ҳамма нарсани
/// кичик ҳарфга айлантиради ва `е/э`ни ажратмайди — матнни мижозга
/// кўрсатишга яролмайди. Бу ерда кўрсатиш учун аниқроқ қоидалар.
///
/// Хавфсизлик қоидаси: ЛОТИН → кирилл фақат соф ўзбек лотини сўзларига
/// (`c`, `w` йўқ) қўлланади — «Coca-Cola», «KFC» каби бренд номлари
/// бузилмасин. Кирилл → лотин ҳамма сўзга қўлланади (рус сўзи ҳам ўқилади).
abstract final class UzScript {
  static const _toLat = <String, String>{
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ё': 'yo', 'ж': 'j',
    'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
    'х': 'x', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': "'",
    'ь': '', 'ы': 'i', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'ў': "o'", 'қ': 'q',
    'ғ': "g'", 'ҳ': 'h', 'ң': 'ng',
  };

  static const _toCyr = <String, String>{
    'a': 'а', 'b': 'б', 'd': 'д', 'f': 'ф', 'g': 'г', 'h': 'ҳ', 'i': 'и',
    'j': 'ж', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п',
    'q': 'қ', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у', 'v': 'в', 'x': 'х',
    'y': 'й', 'z': 'з',
  };

  static const _cyrVowels = 'аеёиоуэюяўы';
  static const _marks = 'ʻʼʽˈ`´‘’′';

  static final _word = RegExp("[A-Za-zЀ-ӿ'$_marks]+");
  static final _pureLatin = RegExp("^[abdefghijklmnopqrstuvxyz'$_marks]+\$", caseSensitive: false);

  static bool hasCyrillic(String s) => s.runes.any((r) => r >= 0x0400 && r <= 0x04FF);

  static bool _isUpper(String ch) => ch != ch.toLowerCase();

  /// [out]ни манба ҳарфнинг катталигига мослайди: кичик → ўзгармайди;
  /// катта → биринчи ҳарф катта, қўшни ҳарф ҳам катта бўлса — ҳаммаси катта.
  static String _cased(String out, {required bool upper, required bool neighbourUpper}) {
    if (!upper || out.isEmpty) return out;
    if (out.length == 1 || neighbourUpper) return out.toUpperCase();
    return out[0].toUpperCase() + out.substring(1);
  }

  /// Кирилл (ва аралаш) матнни лотинга. Лотин сўзлар ўзгармайди.
  static String toLatin(String s) => s.replaceAllMapped(_word, (m) {
        final w = m[0]!;
        if (!hasCyrillic(w)) return w;
        final chars = w.split('');
        final buf = StringBuffer();
        for (var i = 0; i < chars.length; i++) {
          final ch = chars[i];
          final low = ch.toLowerCase();
          final upper = _isUpper(ch);
          final neighbourUpper = (i > 0 && _isUpper(chars[i - 1])) || (i + 1 < chars.length && _isUpper(chars[i + 1]));
          String? out;
          if (low == 'е') {
            final prev = i == 0 ? null : chars[i - 1].toLowerCase();
            out = (prev == null || _cyrVowels.contains(prev) || prev == 'ъ' || prev == 'ь') ? 'ye' : 'e';
          } else {
            out = _toLat[low];
          }
          buf.write(out == null ? ch : _cased(out, upper: upper, neighbourUpper: neighbourUpper));
        }
        return buf.toString();
      });

  /// Соф ўзбек лотини сўзларини кириллга. Бошқа сўзлар (бренд, кирилл,
  /// аралаш) ўзгармайди.
  static String toCyrillic(String s) => s.replaceAllMapped(_word, (m) {
        final w = m[0]!;
        // `c` фақат `ch` таркибида рухсат (бошқа `c` — бренд/хорижий сўз).
        if (!_pureLatin.hasMatch(w.replaceAll(RegExp('ch', caseSensitive: false), ''))) return w;
        final src = w.replaceAll(RegExp('[$_marks]'), "'");
        final low = src.toLowerCase();
        final buf = StringBuffer();
        var i = 0;
        while (i < src.length) {
          final two = i + 1 < low.length ? low.substring(i, i + 2) : '';
          final upper = _isUpper(src[i]);
          final nextUpper = i + 1 < src.length && _isUpper(src[i + 1]);
          final prevUpper = i > 0 && _isUpper(src[i - 1]);
          String out;
          var take = 1;
          if (two == "o'") {
            out = 'ў';
            take = 2;
          } else if (two == "g'") {
            out = 'ғ';
            take = 2;
          } else if (two == 'sh') {
            out = 'ш';
            take = 2;
          } else if (two == 'ch') {
            out = 'ч';
            take = 2;
          } else if (two == 'yo') {
            out = 'ё';
            take = 2;
          } else if (two == 'yu') {
            out = 'ю';
            take = 2;
          } else if (two == 'ya') {
            out = 'я';
            take = 2;
          } else if (two == 'ye' && i == 0) {
            out = 'е';
            take = 2;
          } else if (two == 'ng') {
            out = 'нг';
            take = 2;
          } else if (low[i] == "'") {
            out = i == 0 ? '' : 'ъ';
          } else if (low[i] == 'e') {
            out = i == 0 ? 'э' : 'е';
          } else {
            out = _toCyr[low[i]] ?? src[i];
          }
          final second = take == 2 && i + 2 < src.length && _isUpper(src[i + 2]);
          buf.write(_cased(out,
              upper: upper, neighbourUpper: (take == 2 ? _isUpper(src[i + 1]) : nextUpper) || prevUpper || second));
          i += take;
        }
        return buf.toString();
      });
}
