// AVA patch #3 (vendored video_player_android 2.9.5).
//
// ExoPlayer birinchi HLS variant'ni `DefaultBandwidthMeter`ning boshlang'ich
// (mamlakat/tarmoq turi bo'yicha jadval) baholashiga qarab tanlaydi — Wi-Fi'da
// 480p/720p. `AvaMediaCache.prefetch()` esa eng past (360p) variant'ni
// yozadi — o'lchov (TECNO LH7n): player prefetch'ni chetlab, o'z variant'ini
// tarmoqdan tortdi (init 1.5–2.5 s kesh bo'lsa ham).
//
// Boshlang'ich baho pastroq → birinchi segment doim eng past variant (kesh
// hit, tez birinchi frame), keyin real o'lchovga qarab yuqoriga o'tadi
// (qisqa-format lentalarning "start low, ramp up" andozasi).
//
// ─────────────────────────────────────────────────────────────────────
// 2026-09-26 TUZATISH — "ramp up" ҳеч қачон СОДИР БЎЛМАГАН.
//
// Аввал бу ерда ҲАР плеер учун ЯНГИ `DefaultBandwidthMeter` қурилар эди
// (`new Builder(context).build()`). `DefaultBandwidthMeter` ўлчовни ўз
// ичида сақлайди, яъни ҳар свайпда — ҳар янги ExoPlayer'да — ўлчов
// нолдан, 100 kbps'дан бошланарди. Клип ўртача 8 сония кўрилади, шу
// вақт ичида эса ўлчов яна бошидан тўпланади. Натижада поғона ҳеч
// қачон кўтарилмасди.
//
// Қурилмада ўлчанди (TECNO LH7n, `adb shell dumpsys media.metrics`,
// 2026-09-26): кетма-кет 5 та клип — ҳаммаси 202×360 декодланган,
// декодер умри 52с, 57с, 15с, 10с, 2с; `resolution-change-count=1`
// (яъни фақат бошланғич ўлчам, ҳеч қандай ABR алмашуви йўқ).
//
// Энди метр — ЖАРАЁН БЎЙИЧА ЯГОНА (process-wide singleton): биринчи
// клипда ўлчанган тармоқ тезлиги кейингиларига ўтади, шунинг учун
// иккинчи клипдан бошлаб плеер дарҳол мос поғонани танлайди. Media3
// ҳужжати ҳам айнан шуни тавсия қилади ("use a single instance for all
// players") — бир нечта плеер ўлчови бирлашади.
//
// `DefaultBandwidthMeter.getSingletonInstance()` ишлатилмайди: у ўз
// ичида default (мамлакат жадвали) бошланғич баҳо билан қурилади ва
// уни ўзгартириб бўлмайди — бизга эса қуйидаги ПАСТ бошланғич баҳо
// керак (биринчи сегмент кешдан келсин).
package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.upstream.BandwidthMeter;
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;

@UnstableApi
public final class AvaBandwidthMeter {
  private AvaBandwidthMeter() {}

  /// Ataylab har qanday variant'dan past: AdaptiveTrackSelection "hech biri
  /// sig'masa — eng past bitrate" qoidasi bilan birinchi tanlov DOIM master'dagi
  /// eng past variant. `AvaMediaCache.selectVariant()` ҳам АЙНАН шу метрнинг
  /// баҳосидан фойдаланади, шунинг учун prefetch ва плеер доим бир хил
  /// вариантни олади (кеш ҳар доим тўғри келади).
  /// Birinchi segmentdan keyin real o'lchov bilan yuqoriga o'tadi.
  ///
  /// ЭСЛАТМА: бу энди ФАҚАТ жараён ишга тушгандан кейинги БИРИНЧИ клипга
  /// таъсир қилади — кейингилари ўлчанган ҳақиқий тезликни мерос олади.
  public static final long INITIAL_BITRATE_ESTIMATE = 100_000L;

  private static volatile DefaultBandwidthMeter instance;

  @NonNull
  public static BandwidthMeter create(@NonNull Context context) {
    DefaultBandwidthMeter local = instance;
    if (local == null) {
      synchronized (AvaBandwidthMeter.class) {
        local = instance;
        if (local == null) {
          // Application context — метр жараён давомида яшайди, Activity'ни
          // ушлаб қолмаслиги керак.
          local =
              new DefaultBandwidthMeter.Builder(context.getApplicationContext())
                  .setInitialBitrateEstimate(INITIAL_BITRATE_ESTIMATE)
                  .build();
          instance = local;
        }
      }
    }
    return local;
  }
}
