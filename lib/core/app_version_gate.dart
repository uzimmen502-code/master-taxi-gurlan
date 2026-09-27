import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/app_version_repository.dart';

/// Минимал версия дарвозаси — сервер эски иловага «янгилан» дея олиши.
///
/// **НЕГА КЕРАК (2026-09-27 ҳодисаси).** `firestore.rules` да шаҳарлараро
/// брон қоидаси ўзгартирилганда Play'даги эски илова эски усулда ёзишда
/// давом этди ва 4 соат 56 дақиқа брон умуман ишламади. Ягона чора
/// қоидани орқага қайтариш бўлди, чунки серверда эски иловага
/// «сен эскирдинг» дейиш механизми ЙЎҚ эди.
///
/// Бу синф ўша механизм. Firestore'даги битта ҳужжат — `config/app_version`
/// (мавжуд `config` коллекциясида, шунинг учун ЯНГИ ҚОИДА КЕРАК ЭМАС):
///
/// ```json
/// {
///   "minSupportedBuild": 70,
///   "latestBuild": 73,
///   "message": {"uz_Cyrl": "...", "uz_Latn": "...", "ru": "..."}
/// }
/// ```
///
/// **ЧЕКЛАНИШ:** дарвоза фақат уни ЎЗ ИЧИГА ОЛГАН версиялардан бошлаб
/// ишлайди. Бугунги 1.0.24 / 1.0.26 / 1.0.29 фойдаланувчиларида бу код
/// йўқ, яъни уларни мажбурлаб бўлмайди. Шунинг учун у реклама
/// бошлашдан ОЛДИН киритилади: рекламадан келадиган ҳар бир янги
/// фойдаланувчи дарвозали версияни ўрнатади.
///
/// ## Хавфсизлик тамойили: ХАТОДА ОЧИҚ ҚОЛАДИ
///
/// Ҳар қандай ноаниқликда дарвоза **очиқ** қолади ([mustUpdate] false):
///
/// - ўз build рақами ўқилмаса (`_currentBuild == 0`)
/// - `config/app_version` ҳужжати бўлмаса ёки ўқилмаса
/// - `minSupportedBuild` сон бўлмаса ёки 0 бўлса
///
/// Сабаби очиқ: Firestore узилиши ёки битта нотўғри қиймат БУТУН
/// иловани ишдан чиқармаслиги керак. Дарвоза — бошқарув воситаси,
/// портлайдиган нарса эмас.
class AppVersionGate {
  AppVersionGate._();

  static const _keyMin = 'ver_gate_min_build';
  static const _keyLatest = 'ver_gate_latest_build';
  static const _keyMessage = 'ver_gate_message';

  /// Ҳолат ўзгарганда UI қайта чизилиши учун.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static final AppVersionRepository _repo = AppVersionRepository();

  /// Шу APK нинг build рақами (`pubspec` даги `+70`). 0 = аниқланмади.
  static int _currentBuild = 0;

  /// Шундан кичик версиялар мажбурий янгиланади. 0 = дарвоза ўчиқ.
  static int _minSupportedBuild = 0;

  /// Энг сўнгги версия — юмшоқ эслатма учун. 0 = эслатма йўқ.
  static int _latestBuild = 0;

  /// Серверда ёзилган ихтиёрий матн (локал таржима ўрнига ишлатилади).
  static String _serverMessage = '';

  /// Play'даги саҳифа учун — `PackageInfo` дан олинади.
  static String _packageName = '';

  static int get currentBuild => _currentBuild;
  static int get minSupportedBuild => _minSupportedBuild;
  static int get latestBuild => _latestBuild;
  static String get serverMessage => _serverMessage;
  static String get packageName => _packageName;

  /// Мажбурий янгилаш — илова ишламайди.
  ///
  /// Иккала рақам ҳам МАЪЛУМ ва мусбат бўлгандагина true бўлади.
  static bool get mustUpdate =>
      _currentBuild > 0 &&
      _minSupportedBuild > 0 &&
      _currentBuild < _minSupportedBuild;

  /// Юмшоқ эслатма — янги версия бор, лекин ишлайверади.
  static bool get updateAvailable =>
      _currentBuild > 0 &&
      _latestBuild > 0 &&
      _currentBuild < _latestBuild &&
      !mustUpdate;

  /// Cold start: ўз версиясини аниқлаш + ОХИРГИ КЕШни тиклаш.
  ///
  /// Тармоққа чиқмайди — шунинг учун ишга тушишни секинлаштирмайди.
  /// Кеш ишлатилишининг сабаби: акс ҳолда фойдаланувчи интернетни
  /// ўчириб дарвозани айланиб ўта оларди.
  static Future<void> loadCacheOnly() async {
    await _readCurrentBuild();
    await _loadFromCache();
    _bump();
  }

  /// Splash'дан кейин: `config/app_version` ни тармоқдан янгилаш.
  ///
  /// Хато бўлса кешдаги қиймат сақланади (дарвоза ўз-ўзидан очилиб
  /// кетмайди), лекин янги чеклов ҳам қўйилмайди.
  static Future<void> refresh() async {
    if (_currentBuild <= 0) {
      // Ўз версиямизни билмасак, солиштиришнинг маъноси йўқ.
      await _readCurrentBuild();
      if (_currentBuild <= 0) return;
    }
    final before = _fingerprint();
    try {
      final cfg = await _repo.fetch();
      if (cfg == null) return;
      _minSupportedBuild = cfg.minSupportedBuild;
      _latestBuild = cfg.latestBuild;
      _serverMessage = cfg.message;
      await _saveToCache();
    } catch (e, st) {
      debugPrint('AppVersionGate.refresh: $e\n$st');
      return;
    }
    if (_fingerprint() != before) _bump();
  }

  static Future<void> _readCurrentBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _packageName = info.packageName;
      _currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;
    } catch (e, st) {
      // Веб ва тестларда бўлмаслиги мумкин — дарвоза ўчиқ қолади.
      debugPrint('AppVersionGate._readCurrentBuild: $e\n$st');
      _currentBuild = 0;
    }
  }

  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _minSupportedBuild = prefs.getInt(_keyMin) ?? 0;
      _latestBuild = prefs.getInt(_keyLatest) ?? 0;
      _serverMessage = prefs.getString(_keyMessage) ?? '';
    } catch (_) {}
  }

  static Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyMin, _minSupportedBuild);
      await prefs.setInt(_keyLatest, _latestBuild);
      await prefs.setString(_keyMessage, _serverMessage);
    } catch (_) {}
  }

  static String _fingerprint() =>
      '$_currentBuild|$_minSupportedBuild|$_latestBuild|$_serverMessage';

  static void _bump() => revision.value++;

  @visibleForTesting
  static void setForTest({
    int currentBuild = 0,
    int minSupportedBuild = 0,
    int latestBuild = 0,
    String serverMessage = '',
    String packageName = 'uz.ava.gurlan',
  }) {
    _currentBuild = currentBuild;
    _minSupportedBuild = minSupportedBuild;
    _latestBuild = latestBuild;
    _serverMessage = serverMessage;
    _packageName = packageName;
  }

  @visibleForTesting
  static void resetForTest() => setForTest(packageName: '');
}
