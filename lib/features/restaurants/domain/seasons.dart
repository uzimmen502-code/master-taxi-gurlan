// Мавсумий бўлимлар ва Рамазон жадвали (D-REST-22; docs/kafe_restoran_taklifi_uz.md §10.1, D-REST-39).
//
// Эга қарори: мавсумий бўлимлар (Рамазон, Наврўз, Қурбон ҳайит, Янги йил, тўй мавсуми) санадан 10 кун ОЛДИН очилади
// ва муддат тугагач ёпилади; Рамазон/Қурбон санаси ой тақвимидан тахминан ҳисобланади, админ тасдиқлайди ёки суради;
// саҳарлик/ифтор вақти — идоранинг расмий тақвими (Тошкент вақти + ҳудудлар бўйича дақиқа фарқи), жадвалда ҳудуд
// бўлмаса вақт ТАХМИН ҚИЛИНМАЙДИ. Қоидалар `settings/restaurant_seasons` ва `settings/restaurant_ramadan` дан
// (версияли, фақат CF ёзади); бу ерда — уларни ўқиш ва «ҳозир қайси мавсум очиқ» қоидасининг сервердаги
// (`functions/restaurant_seasons.js`) нусхаси (мослик `seasons_test.dart` да бир хил векторлар билан қулфланган).

/// Мавсум калитлари = таом теглари (`DishTag.seasons`) = `settings/restaurant_seasons` калитлари.
abstract final class SeasonKey {
  static const ramadan = 'ramadan';
  static const navruz = 'navruz';
  static const qurbon = 'qurbon';
  static const newyear = 'newyear';
  static const wedding = 'wedding';

  static const all = [ramadan, navruz, qurbon, newyear, wedding];
}

/// Битта мавсум даври: [from]…[to] (Тошкент куни, `YYYY-MM-DD`, иккала чегара ҳам киради).
class SeasonPeriod {
  const SeasonPeriod({required this.key, required this.from, required this.to, this.confirmed = false});

  final String key;
  final String from;
  final String to;

  /// Админ тасдиқлаган (`false` — тахминий сана).
  final bool confirmed;
}

/// Ҳозир очиқ мавсум: [opensOn] — қайси кундан кўринади (`from − opensDaysBefore`).
class ActiveSeason {
  const ActiveSeason({required this.key, required this.from, required this.to, required this.confirmed, required this.opensOn});

  final String key;
  final String from;
  final String to;
  final bool confirmed;
  final String opensOn;
}

/// Бугунги Тошкент куни (`YYYY-MM-DD`), қурилма вақт зонасидан мустақил (сервер `tashkentToday` билан бир хил: UTC+5).
String tashkentDay(DateTime now) => _iso(now.toUtc().add(const Duration(hours: 5)));

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `YYYY-MM-DD` ни (UTC ярим тун) ўқийди; мавжуд бўлмаган сана (`2027-02-30`) — `null`.
DateTime? parseIsoDay(Object? s) {
  if (s is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final p = s.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2] ? d : null;
}

/// `settings/restaurant_seasons`. Ҳужжат йўқ/бузилган — давр йўқ: мавсумий бўлим кўринмайди.
class RestaurantSeasonsConfig {
  const RestaurantSeasonsConfig({this.periods = const [], this.opensDaysBefore = defaultOpensDaysBefore, this.version = 0});

  /// Сервердаги `DEFAULT_OPENS_DAYS` нусхаси (эга: 10 кун).
  static const defaultOpensDaysBefore = 10;

  static const none = RestaurantSeasonsConfig();

  final List<SeasonPeriod> periods;
  final int opensDaysBefore;
  final int version;

  /// Ҳозир очиқ мавсумлар ([SeasonKey.all] тартибида): бугунги Тошкент куни `[from − opensDaysBefore, to]` да.
  List<ActiveSeason> activeAt(DateTime now) {
    final today = parseIsoDay(tashkentDay(now))!;
    final out = <ActiveSeason>[];
    for (final key in SeasonKey.all) {
      ActiveSeason? best;
      DateTime? bestFrom;
      for (final p in periods.where((p) => p.key == key)) {
        final from = parseIsoDay(p.from);
        final to = parseIsoDay(p.to);
        if (from == null || to == null) continue;
        final opens = from.subtract(Duration(days: opensDaysBefore));
        if (today.isBefore(opens) || today.isAfter(to)) continue;
        if (bestFrom == null || from.isBefore(bestFrom)) {
          bestFrom = from;
          best = ActiveSeason(key: key, from: p.from, to: p.to, confirmed: p.confirmed, opensOn: _iso(opens));
        }
      }
      if (best != null) out.add(best);
    }
    return out;
  }

  factory RestaurantSeasonsConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return none;
    final periods = <SeasonPeriod>[];
    final raw = d['periods'];
    if (raw is List) {
      for (final p in raw) {
        if (p is! Map) continue;
        final key = p['key'];
        if (key is! String || !SeasonKey.all.contains(key)) continue;
        if (parseIsoDay(p['from']) == null || parseIsoDay(p['to']) == null) continue;
        periods.add(SeasonPeriod(key: key, from: p['from'] as String, to: p['to'] as String, confirmed: p['confirmed'] == true));
      }
    }
    final o = d['opensDaysBefore'];
    return RestaurantSeasonsConfig(
      periods: periods,
      opensDaysBefore: o is num && o == o.truncate() && o >= 0 && o <= 30 ? o.toInt() : defaultOpensDaysBefore,
      version: d['version'] is num ? (d['version'] as num).toInt() : 0,
    );
  }
}

/// Бугунги саҳарлик ва ифтор вақти (`HH:mm`).
class RamadanTimes {
  const RamadanTimes({required this.sahar, required this.iftar});

  final String sahar;
  final String iftar;
}

/// `settings/restaurant_ramadan`: Тошкент вақти бўйича кунлик жадвал ва ҳудуд (`geo_regions` id) бўйича дақиқа фарқи.
class RamadanConfig {
  const RamadanConfig({this.days = const {}, this.offsets = const {}, this.version = 0});

  static const none = RamadanConfig();

  final Map<String, ({String sahar, String iftar})> days;
  final Map<String, int> offsets;
  final int version;

  static final _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  static String? _shift(String hhmm, int minutes) {
    if (!_hhmm.hasMatch(hhmm)) return null;
    final p = hhmm.split(':').map(int.parse).toList();
    final total = (((p[0] * 60 + p[1] + minutes) % 1440) + 1440) % 1440;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Берилган кун ва ҳудуд учун вақт; кун ёки ҳудуд жадвалда йўқ бўлса `null` (вақт тахмин қилинмайди).
  RamadanTimes? timesFor(String isoDay, String? regionId) {
    final day = days[isoDay];
    if (day == null || regionId == null || regionId.isEmpty) return null;
    final off = offsets[regionId];
    if (off == null) return null;
    final sahar = _shift(day.sahar, off);
    final iftar = _shift(day.iftar, off);
    return sahar == null || iftar == null ? null : RamadanTimes(sahar: sahar, iftar: iftar);
  }

  factory RamadanConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return none;
    final days = <String, ({String sahar, String iftar})>{};
    final rawDays = d['days'];
    if (rawDays is Map) {
      for (final e in rawDays.entries) {
        final v = e.value;
        if (e.key is! String || parseIsoDay(e.key) == null || v is! Map) continue;
        final sahar = v['sahar'];
        final iftar = v['iftar'];
        if (sahar is String && iftar is String && _hhmm.hasMatch(sahar) && _hhmm.hasMatch(iftar)) {
          days[e.key as String] = (sahar: sahar, iftar: iftar);
        }
      }
    }
    final offsets = <String, int>{};
    final rawOff = d['offsets'];
    if (rawOff is Map) {
      for (final e in rawOff.entries) {
        final v = e.value;
        if (e.key is String && v is num && v == v.truncate() && v >= -120 && v <= 120) offsets[e.key as String] = v.toInt();
      }
    }
    return RamadanConfig(days: days, offsets: offsets, version: d['version'] is num ? (d['version'] as num).toInt() : 0);
  }
}
