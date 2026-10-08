import 'dart:math';

/// `playbackStats` ёзувининг НАМУНА улуши.
///
/// НИМА УЧУН НАМУНА. `TvPlaybackAnalyticsRecorder` ҳар playback охирида
/// клип ҳужжатига битта Firestore ёзуви қиларди — яъни ёзув сони
/// кўришлар сонига тенг эди. У ўша битта («қизиган») ҳужжатга тушади,
/// шунинг учун машҳур клипда ёзувлар навбатга туриб, кечикиш беради.
///
/// Метрикаларнинг ҳаммаси ЎРТАЧА (rebuffer/кўриш, тугаллаш улуши,
/// биринчи кадр) — улар тасодифий намунада ўзгармайди. 10k DAU'да 10%
/// намуна ойига ~600 000 ўлчов беради, бу ўртачалар учун ортиғи билан
/// етарли.
///
/// АБСОЛЮТ сонлар эса намунадан бузилади. Шунинг учун улар бошқа
/// майдондан олинади: `viewCount` (аниқ, dedup қилинган кўриш сони).
/// Жуфти: `functions/tools/audit_avagram_usage.js` даги
/// `PLAYBACK_STATS_SAMPLE_RATE` — иккиси мос туриши ШАРТ, буни тест
/// текширади (`test/features/tv_market/tv_playback_sampling_test.dart`).
///
/// Ўлчов: `docs/video-architecture/cost_model.py`, E варианти.
const double kTvPlaybackStatsSampleRate = 0.10;

/// Шу playback учун статистика ёзиладими?
///
/// [roll] — [0,1) оралиғидаги тасодифий сон. Ташқаридан берилиши
/// тестни детерминистик қилади; ишлаб чиқаришда [tvRollPlaybackSample].
bool tvShouldWritePlaybackStats(
  double roll, {
  double rate = kTvPlaybackStatsSampleRate,
}) {
  if (rate >= 1.0) return true;
  if (rate <= 0.0) return false;
  return roll < rate;
}

final _rng = Random();

/// Ишлаб чиқариш учун: тасодифий сон олиб, қарорни қайтаради.
bool tvRollPlaybackSample({double rate = kTvPlaybackStatsSampleRate}) =>
    tvShouldWritePlaybackStats(_rng.nextDouble(), rate: rate);
