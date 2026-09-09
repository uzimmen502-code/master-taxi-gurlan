import '../models/tv_clip.dart';

/// Бир илова сессиясида барқарор, кейинги очилишда янги тартиб.
final int _tvShuffleSessionSeed = DateTime.now().microsecondsSinceEpoch;

/// Home / feed / search пули — эга гриди эмас.
///
/// `Random()` ҳар fetchда қайта аралаштирмасин: саҳифалаш ўртасида
/// тартиб сақланади, илова қайта очилганда `sessionSeed` янгиланади.
List<TvClip> tvShuffleClips(List<TvClip> items) {
  if (items.length < 2) return List<TvClip>.from(items);
  final out = List<TvClip>.from(items);
  out.sort((a, b) {
    final cmp = Object.hash(a.id, _tvShuffleSessionSeed)
        .compareTo(Object.hash(b.id, _tvShuffleSessionSeed));
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });
  return out;
}

/// AVA TV тариф жадвали — «Кўриниш устуворлиги»: юқори тариф (pro_max →
/// premium → home → visibility) `tvShuffleClips`дан кейин feed бошига
/// силжийди. Кўп бўлса ҳам бошини тўлиқ тўлдирмаслик учун бир пайтда энг
/// кўпи [maxBoostedSlots] та боост клипи олдинги слотга чиқади — ортиқчаси
/// (ва barcha тариф 0/оddiy контент) ўз shuffle тартибида қолади, ЙЎҚОЛМАЙДИ
/// (feed охирига эмас, `rest` ичида ўз ўрнида қолади).
List<TvClip> tvApplyAdTierPriority(
  List<TvClip> items, {
  int maxBoostedSlots = 6,
}) {
  if (items.length < 2) return List<TvClip>.from(items);
  final boosted = <TvClip>[];
  final rest = <TvClip>[];
  for (final c in items) {
    if (c.adBoostWeight > 0) {
      boosted.add(c);
    } else {
      rest.add(c);
    }
  }
  if (boosted.isEmpty) return items;
  boosted.sort((a, b) => b.adBoostWeight.compareTo(a.adBoostWeight));
  final promoted = boosted.take(maxBoostedSlots);
  final overflow = boosted.skip(maxBoostedSlots);
  return [...promoted, ...rest, ...overflow];
}
