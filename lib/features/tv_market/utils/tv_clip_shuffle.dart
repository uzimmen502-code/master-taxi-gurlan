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
