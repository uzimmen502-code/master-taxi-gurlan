// AVA patch #4 (vendored video_player_android 2.9.5).
//
// ExoPlayer'нинг стандарт `AdaptiveTrackSelection`и УЗУН видео учун
// созланган: поғонани кўтариш учун камида 10 СОНИЯ олдинга буферланган
// бўлишини талаб қилади (`minDurationForQualityIncreaseMs` = 10_000).
//
// AVAGram — қисқа-формат лента: ўртача кўриш 8 сония, буфер эса
// [AvaLoadControl] билан 20 сония билан чегараланган. Яъни фойдаланувчи
// клипни ташлаб кетгунча плеер поғонани кўтаришга УМУМАН УЛГУРМАЙДИ —
// бутун сессия энг паст поғонада ўтади.
//
// Қурилмада ўлчанди (TECNO LH7n, `dumpsys media.metrics`, 2026-09-26):
// кетма-кет 5 клип, ҳаммаси энг паст поғонада, `resolution-change-count=1`
// (бошланғич ўлчамдан бошқа ҳеч қандай алмашув йўқ). [AvaBandwidthMeter]
// ҳар плеерда нолдан бошлангани билан бирга — бу иккинчи сабаб эди.
//
// Қуйидаги қийматлар айнан қисқа-формат учун:
//
//  • MIN_DURATION_FOR_QUALITY_INCREASE_MS = 1_500 (10_000 ўрнига)
//    Битта HLS сегмент 3 сония (`TV_CLIP_HLS_SEGMENT_SECONDS`), шунинг
//    учун биринчи сегмент келиши биланоқ шарт бажарилади ва плеер
//    ҳақиқий ўлчовга қараб юқорига ўтади.
//
//  • MIN_DURATION_TO_RETAIN_AFTER_DISCARD_MS = 3_000 (25_000 ўрнига)
//    Поғона кўтарилганда АЛЛАҚАЧОН буферланган паст сифатли қисм
//    ташланади ва юқори сифатда қайта юкланади. 25 сония (стандарт)
//    бизнинг 20 сониялик буферимиздан катта — яъни ташлаш ҳеч қачон
//    содир бўлмасди ва кўтарилиш экранда фақат ~20 сониядан кейин
//    кўринарди (клип аллақачон тугаган бўларди). 3_000 = битта сегмент
//    сақланади, қолгани янгиланади — кўтарилиш ~3 сонияда КЎЗГА
//    кўринади, исроф эса битта сегментдан ошмайди.
//
//  • BANDWIDTH_FRACTION = 0.75 (стандарт 0.7)
//    Сервер энди master playlist'да BANDWIDTH сифатида PEAK тезликни
//    эълон қилади (аввал ўртача эди), яъни рақамнинг ўзида заҳира бор —
//    шунинг учун бу ерда ортиқча эҳтиёткорлик шарт эмас.
//
//  • MAX_DURATION_FOR_QUALITY_DECREASE_MS — стандарт 25_000 сақланади.
//    Бу «буфер шундан кам бўлса пастга туш» чегараси; бизнинг буфер
//    ҳеч қачон 20 сониядан ошмагани учун пастга тушиш ДОИМО рухсат
//    этилган бўлади — заиф тармоқда айнан шу керак.
package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;

@UnstableApi
public final class AvaTrackSelection {
  private AvaTrackSelection() {}

  public static final int MIN_DURATION_FOR_QUALITY_INCREASE_MS = 1_500;
  public static final int MAX_DURATION_FOR_QUALITY_DECREASE_MS = 25_000;
  public static final int MIN_DURATION_TO_RETAIN_AFTER_DISCARD_MS = 3_000;
  public static final float BANDWIDTH_FRACTION = 0.75f;

  @NonNull
  public static DefaultTrackSelector create(@NonNull Context context) {
    AdaptiveTrackSelection.Factory adaptive =
        new AdaptiveTrackSelection.Factory(
            MIN_DURATION_FOR_QUALITY_INCREASE_MS,
            MAX_DURATION_FOR_QUALITY_DECREASE_MS,
            MIN_DURATION_TO_RETAIN_AFTER_DISCARD_MS,
            BANDWIDTH_FRACTION);
    return new DefaultTrackSelector(context, adaptive);
  }
}
